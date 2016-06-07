{Utils, DraftStore, React, Actions, DatabaseStore, Contact, ReactDOM} = require 'nylas-exports'
PGPKeyStore = require './pgp-key-store'
Identity = require './identity'
PassphrasePopover = require './passphrase-popover'
EncryptButton = require './encrypt-button'
{RetinaImg} = require 'nylas-component-kit'
{remote} = require 'electron'
pgp = require 'kbpgp'
_ = require 'underscore'

class SignMessageButton extends React.Component

  @displayName: 'SignMessageButton'

  # require that we have a draft object available
  @propTypes:
    draft: React.PropTypes.object.isRequired
    session: React.PropTypes.object.isRequired

  constructor: (props) ->
    super(props)

    # plaintext: store the message's plaintext in case the user wants to edit
    # further after hitting the "sign" button (i.e. so we can "undo" the signing)

    # cryptotext: store the message's body here, for comparison purposes (so
    # that if the user edits an encrypted message, we can revert it)
    @state = {plaintext: "", cryptotext: "", currentlySigned: false}

  componentDidMount: ->
    @unlistenKeystore = PGPKeyStore.listen(@_onKeystoreChange, @)

  componentWillUnmount: ->
    @unlistenKeystore()

  _onKeystoreChange: =>
    console.warn("Keystore Change! Check private keys!")

  _getKeyAndSign: ->
    popoverTarget = ReactDOM.findDOMNode(@refs.signbutton).getBoundingClientRect()
    keys = PGPKeyStore.privKeys(address: @props.draft.from[0].email)
    if keys.length < 1
      # no cached keys. get a passphrase and go unlock some
      Actions.openPopover(
        <PassphrasePopover onPopoverDone={ @_signPopoverDone } />,
        {originRect: popoverTarget, direction: 'up'}
      )
    else if keys.length > 1
      console.error("too many private keys. fuuuuuuck")
      return
    else
      if keys[0].key?
        # only one key, not timed out, km already loaded, good to go
        @_sign(keys[0])
      else
        # only one key, not timed out, but km not loaded. (?!?!?) need passphrase
        Actions.openPopover(
          <PassphrasePopover onPopoverDone={ @_contentsPopoverDone } />,
          {originRect: popoverTarget, direction: 'up'}
        )

  _contentsPopoverDone: (passphrase) =>
    keys = PGPKeyStore.privKeys(address: @props.draft.from[0].email)
    PGPKeyStore.getKeyContents(key: keys[0], passphrase: passphrase, callback: @_sign)

  _signPopoverDone: (passphrase) =>
    keys = PGPKeyStore.privKeys(address: @props.draft.from[0].email, timed: false)
    if keys.length < 1
      NylasEnv.showErrorDialog("Could not find a PGP private key for the sending email
        address. Go to Encryption Preferences to import one, then try again.")
      return
    else if keys.length > 1
      console.error("too many private keys. fuuuuuuck")
      return
    else
      PGPKeyStore.getKeyContents(key: keys[0], passphrase: passphrase, callback: @_sign)

  _toggleSign: =>
    # if unsigned, sign. if signed, put plaintext back in draft (i.e. unsign)
    if @state.currentlySigned
      @props.session.changes.add({body: @state.plaintext})
      @setState({currentlySigned: false})
    else
      @_getKeyAndSign()

  _formatSignature: (plaintext, cryptotext) =>
    # format a signed message the way that other mail clients are expecting
    pgpStart = "-----BEGIN PGP MESSAGE-----"
    pgpEnd = "-----END PGP MESSAGE-----"

    cryptosigned = cryptotext.replace(pgpStart, "-----BEGIN PGP SIGNATURE-----")
      .replace(pgpEnd, "-----END PGP SIGNATURE-----")

    header = "<pre>-----BEGIN PGP SIGNED MESSAGE-----</pre>"
    signature = "<pre>#{cryptosigned}</pre>"
    return header + plaintext + signature

  _sign: (identity) =>
    plaintext = @props.draft.body
    km = identity.key
    params =
      sign_with: km
      msg: plaintext
    pgp.box(params, (err, cryptotext) =>
        if err
          NylasEnv.showErrorDialog(err)
        if cryptotext? and cryptotext != ""
          # <pre> tag prevents gross HTML formatting in-flight
          cryptotext = @_formatSignature(plaintext, cryptotext)
          @setState({
            currentlySigned: true
            plaintext: plaintext
            cryptotext: cryptotext
          })
          @props.session.changes.add({body: cryptotext})
      )

  render: ->
    classnames = "btn btn-toolbar"
    if @state.currentlySigned
      classnames += " btn-enabled"

    <div className="n1-keybase">
      <button title="Sign email body" className={ classnames } onClick={ => @_toggleSign()} ref="signbutton">
        <RetinaImg url="nylas://keybase/key-present@2x.png" mode={RetinaImg.Mode.ContentIsMask} />
      </button>
    </div>

module.exports = SignMessageButton
