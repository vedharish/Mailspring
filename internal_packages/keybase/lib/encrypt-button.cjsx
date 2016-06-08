{Utils, DraftStore, React, Actions, DatabaseStore, Contact, ReactDOM} = require 'nylas-exports'
PGPKeyStore = require './pgp-key-store'
Identity = require './identity'
ModalKeyRecommender = require './modal-key-recommender'
PassphrasePopover = require './passphrase-popover'
{RetinaImg} = require 'nylas-component-kit'
{remote} = require 'electron'
pgp = require 'kbpgp'
_ = require 'underscore'

class EncryptMessageButton extends React.Component

  @displayName: 'EncryptMessageButton'

  # require that we have a draft object available
  @propTypes:
    draft: React.PropTypes.object.isRequired
    session: React.PropTypes.object.isRequired

  constructor: (props) ->
    super(props)

    # plaintext: store the message's plaintext in case the user wants to edit
    # further after hitting the "encrypt" or "sign" buttons (i.e. so we can
    # "undo" the encryption and/or signing)

    # cryptotext: store the message's body here, for comparison purposes (so
    # that if the user edits an encrypted/signed message, we can revert it)
    @state =
      plaintext: ""
      cryptotext: ""
      currentlyEncrypted: false
      currentlySigned: false

  componentDidMount: ->
    @unlistenKeystore = PGPKeyStore.listen(@_onKeystoreChange, @)

  componentWillUnmount: ->
    @unlistenKeystore()

  componentWillReceiveProps: (nextProps) ->
    if @state.currentlyEncrypted and nextProps.draft.body != @props.draft.body and nextProps.draft.body != @state.cryptotext
      # A) we're encrypted
      # B) someone changed something
      # C) the change was AWAY from the "correct" cryptotext
      body = @state.cryptotext
      @props.session.changes.add({body: body})

  _onKeystoreChange: =>
    # TODO this doesn't do shit

    # if something changes with the keys, check to make sure the recipients
    # haven't changed (thus invalidating our encrypted message)
    if @state.currentlyEncrypted
      newKeys = _.map(@props.draft.participants(), (participant) ->
        return PGPKeyStore.pubKeys(participant.email)
      )
      newKeys = _.flatten(newKeys)

      oldKeys = _.map(@props.draft.participants(), (participant) ->
        return PGPKeyStore.pubKeys(participant.email)
      )
      oldKeys = _.flatten(oldKeys)

      if newKeys.length != oldKeys.length
        # someone added/removed a key - our encrypted body is now out of date
        @_toggleCrypt()

  ### Encrypt Button ###

  _toggleCrypt: =>
    # if decrypted, encrypt, and vice versa
    if @state.currentlyEncrypted
      if @state.currentlySigned
        @setState({cryptotext: @_deformatEncrypted(@props.draft.body)})
        @props.session.changes.add({body: @_deformatEncrypted(@props.draft.body)})
      else
        @setState({cryptotext: @state.plaintext})
        @props.session.changes.add({body: @state.plaintext})
      @setState({currentlyEncrypted: false})
    else
      # if not encrypted, save the plaintext, then encrypt
      if !@state.currentlySigned
        plaintext = @props.draft.body
        @setState({plaintext: @props.draft.body})
      else
        plaintext = @state.plaintext
      @_checkKeysAndEncrypt(plaintext)

  _getKeys: ->
    # TODO: make this async-safe. the getKeyContents call is risky
    keys = []
    for recipient in @props.draft.participants({includeFrom: false, includeBcc: true})
      publicKeys = PGPKeyStore.pubKeys(recipient.email)
      if publicKeys.length < 1
        # no key for this user
        keys.push(new Identity({addresses: [recipient.email]}))
      else
        # TODO: don't encrypt using every public key associated with the address
        for publicKey in publicKeys
          if not publicKey.key?
            PGPKeyStore.getKeyContents(key: publicKey)
          else
            keys.push(publicKey)

    return keys

  _checkKeysAndEncrypt: (text) =>
    identities = @_getKeys()
    emails = _.chain(identities)
      .pluck("addresses")
      .flatten()
      .uniq()
      .value()
    if _.every(identities, (identity) -> identity.key?)
      # every key is present and valid
      @_encrypt(text, identities)
    else
      # open a popover to correct null keys
      DatabaseStore.findAll(Contact, {email: emails}).then((contacts) =>
        component = (<ModalKeyRecommender contacts={contacts} emails={emails} callback={ (newIdentities) => @_encrypt(text, newIdentities) }/>)
        Actions.openPopover(
          component,
        {
          originRect: ReactDOM.findDOMNode(@).getBoundingClientRect(),
          direction: 'up',
          closeOnAppBlur: false,
        })
      )

  _encrypt: (text, identities) =>
    # get the actual key objects
    keys = _.pluck(identities, "key")
    # remove the nulls
    kms = _.compact(keys)
    if kms.length == 0
      NylasEnv.showErrorDialog("There are no PGP public keys loaded, so the message cannot be
        encrypted. Compose a message, add recipients in the To: field, and try again.")
      return
    params =
      encrypt_for: kms
      msg: text
    pgp.box(params, (err, cryptotext) =>
      if err
        NylasEnv.showErrorDialog(err)
      if cryptotext? and cryptotext != ""
        # <pre> tag prevents gross HTML formatting in-flight
        cryptotext = if !@state.currentlySigned then "<pre>#{cryptotext}</pre>" else cryptotext
        cryptobody = @props.draft.body.replace(@state.plaintext, cryptotext)
        @setState({
          currentlyEncrypted: true
          cryptotext: cryptobody
        })
        @props.session.changes.add({body: cryptobody})
    )

  ### Sign Button ###

  _toggleSign: =>
    # if unsigned, sign, and vice versa
    if @state.currentlySigned
      # play nice with encrypted block, if it exists
      if @state.currentlyEncrypted
        @setState({cryptotext: @_deformatSignature(@props.draft.body)})
        @props.session.changes.add({body: @_deformatSignature(@props.draft.body)})
      else
        @setState({cryptotext: @state.plaintext})
        @props.session.changes.add({body: @state.plaintext})
      @setState({currentlySigned: false})
    else
      # if body neither encrypted nor signed, save the plaintext
      if !@state.currentlyEncrypted
        plaintext = @props.draft.body
        @setState({plaintext: @props.draft.body})
      else
        plaintext = @state.plaintext
      @_getKeyAndSign(plaintext)

  _getKeyAndSign: (text) ->
    popoverTarget = ReactDOM.findDOMNode(@refs.signbutton).getBoundingClientRect()
    keys = PGPKeyStore.privKeys(address: @props.draft.from[0].email)

    if keys.length < 1
      # might be timed out - go look
      untimedkeys = PGPKeyStore.privKeys(address: @props.draft.from[0].email, timed: false)
      if untimedkeys.length < 1
        # no private key saved for email address. error out
        NylasEnv.showErrorDialog("Could not find a PGP private key for the sending email
          address. Go to Encryption Preferences to import one, then try again.")
        return
      else
        # private key for email address saved, but timed out. password needed
        Actions.openPopover(
          <PassphrasePopover onPopoverDone={ (passphrase) => @_signPopoverDone(passphrase, text) } />,
          {originRect: popoverTarget, direction: 'up'}
        )

    else if keys.length > 1
      console.error("too many private keys. fuuuuuuck")
      return

    else if not keys[0].key?
      # only one key, not timed out, but km not loaded. (?!?!?) need passphrase
      Actions.openPopover(
        <PassphrasePopover identity={keys[0]} onPopoverDone={ (passphrase, identity) => @_contentsPopoverDone(passphrase, identity, text) } />,
        {originRect: popoverTarget, direction: 'up'}
      )

    else
      # only one key, not timed out, km already loaded, good to go
      @_sign(keys[0], text)

  _signPopoverDone: (passphrase, text) =>
    keys = PGPKeyStore.privKeys(address: @props.draft.from[0].email, timed: false)
    if keys.length > 1
      console.error("too many private keys. fuuuuuuck")
      return
    else
      PGPKeyStore.getKeyContents(key: keys[0], passphrase: passphrase, callback: (identity) => @_sign(identity, text))

  _contentsPopoverDone: (passphrase, identity, text) =>
    PGPKeyStore.getKeyContents(key: identity, passphrase: passphrase, callback: (identity) => @_sign(identity, text))

  _sign: (identity, text) =>
    km = identity.key
    params =
      sign_with: km
      msg: text
    pgp.box(params, (err, cryptotext) =>
        if err
          NylasEnv.showErrorDialog(err)
        if cryptotext? and cryptotext != ""
          # <pre> tag prevents gross HTML formatting in-flight
          cryptotext = @_formatSignature(@props.draft.body, cryptotext)
          @setState({
            currentlySigned: true
            cryptotext: cryptotext
          })
          @props.session.changes.add({body: cryptotext})
      )

  ### Draft Body Formatting ###

  _deformatEncrypted: (cryptotext) =>
    plaintext = @state.plaintext
    # strip the encrypted block from a signed message body
    header = "<pre>-----BEGIN PGP SIGNED MESSAGE-----\n"
    sigStart = "\n-----BEGIN PGP SIGNATURE-----"

    signature = cryptotext.slice(cryptotext.indexOf(sigStart), cryptotext.length)

    return header + plaintext + signature

  _formatSignature: (plaintext, cryptotext) =>
    # format a signed message the way that other mail clients are expecting
    pgpStart = "-----BEGIN PGP MESSAGE-----"
    pgpEnd = "-----END PGP MESSAGE-----"

    cryptosigned = cryptotext.replace(pgpStart, "\n-----BEGIN PGP SIGNATURE-----")
      .replace(pgpEnd, "-----END PGP SIGNATURE-----")

    header = "<pre>-----BEGIN PGP SIGNED MESSAGE-----\n"
    signature = "#{cryptosigned}</pre>"

    plaintext = plaintext.replace("<pre>", "").replace("</pre>", "")

    return header + plaintext + signature

  _deformatSignature: (cryptotext) =>
    # strip the signature from a signed message body
    header = "<pre>-----BEGIN PGP SIGNED MESSAGE-----\n"
    sigStart = "\n-----BEGIN PGP SIGNATURE-----"

    noSignature = cryptotext.slice(0, cryptotext.indexOf(sigStart))
    noHeader = noSignature.slice(noSignature.indexOf(header) + header.length, noSignature.length)

    body = if @state.currentlyEncrypted then "<pre>#{noHeader}</pre>" else noHeader
    return body

  ### Render ###

  render: ->
    encryptClassnames = "btn btn-toolbar"
    if @state.currentlyEncrypted
      encryptClassnames += " btn-enabled"

    signClassnames = "btn btn-toolbar"
    if @state.currentlySigned
      signClassnames += " btn-enabled"

    <div className="n1-keybase">
      <button title="Encrypt email body" className={ encryptClassnames } onClick={ => @_toggleCrypt()} ref="button">
        <RetinaImg url="nylas://keybase/encrypt-composer-button@2x.png" mode={RetinaImg.Mode.ContentIsMask} />
      </button>
      <button title="Sign email body" className={ signClassnames } onClick={ => @_toggleSign()} ref="signbutton">
        <RetinaImg url="nylas://keybase/key-present@2x.png" mode={RetinaImg.Mode.ContentIsMask} />
      </button>
    </div>

module.exports = EncryptMessageButton
