import _ from 'underscore'
import React from 'react'
import ReactDOM from 'react-dom'
import classNames from 'classnames'
import FindInThread from './find-in-thread'
import MessageItemContainer from './message-item-container'

import {Utils,
 Actions,
 MessageStore,
 SearchableComponentStore,
 SearchableComponentMaker} from 'nylas-exports'

import {Spinner,
 RetinaImg,
 MailLabelSet,
 ScrollRegion,
 MailImportantIcon,
 KeyCommandsRegion,
 InjectedComponentSet} from 'nylas-component-kit'

class MessageListScrollTooltip extends React.Component {
  static displayName = 'MessageListScrollTooltip'
  static propTypes = {
    viewportCenter: React.PropTypes.number.isRequired,
    totalHeight: React.PropTypes.number.isRequired,
  }

  componentWillMount() {
    this.setupForProps(this.props)
  }

  componentWillReceiveProps(newProps) {
    this.setupForProps(newProps)
  }

  shouldComponentUpdate(newProps, newState) {
    return !_.isEqual(this.state, newState)
  }

  setupForProps(props) {
    // Technically, we could have MessageList provide the currently visible
    // item index, but the DOM approach is simple and self-contained.
    const els = document.querySelectorAll('.message-item-wrap')
    let idx = _.findIndex(els, (el) => el.offsetTop > props.viewportCenter)
    if (idx === -1) {
      idx = els.length
    }

    this.setState({
      idx: idx,
      count: els.length,
    })
  }

  render() {
    return (
      <div className="scroll-tooltip">
        {this.state.idx} of {this.state.count}
      </div>
    )
  }
}

class MessageList extends React.Component {
  static displayName = 'MessageList'
  static containerRequired = false
  static containerStyles = {
    minWidth: 500,
    maxWidth: 999999,
  }

  constructor(props) {
    super(props)
    this.state = this._getStateFromStores()
    this.state.minified = true
    this._draftScrollInProgress = false
    this.MINIFY_THRESHOLD = 3
  }

  componentDidMount() {
    this._unsubscribers = []
    this._unsubscribers.push(MessageStore.listen(this._onChange))
    this._unsubscribers.push(
      Actions.focusDraft.listen(({draftClientId}) => {
        Utils.waitFor(() => this._getMessageContainer(draftClientId) != null)
          .then(() => this._focusDraft(this._getMessageContainer(draftClientId)))
          .catch(() => { })
      })
    )
  }

  shouldComponentUpdate(nextProps, nextState) {
    return !Utils.isEqualReact(nextProps, this.props) ||
      !Utils.isEqualReact(nextState, this.state)
  }

  componentDidUpdate() { }

  componentWillUnmount() {
    for (const unsubscribe of this._unsubscribers) {
      unsubscribe()
    }
  }

  _globalMenuItems = () => {
    const toggleExpandedLabel = this.state.hasCollapsedItems ? "Expand" : "Collapse"
    return [
      {
        label: "Thread",
        submenu: [{
          label: `${toggleExpandedLabel} conversation`,
          command: "message-list:toggle-expanded",
          position: "endof=view-actions",
        }],
      },
    ]
  }

  _globalKeymapHandlers = () => {
    const handlers = {
      'core:reply': () => {
        Actions.composeReply({
          thread: this.state.currentThread,
          message: this._lastMessage(),
          type: 'reply',
          behavior: 'prefer-existing',
        })
      },
      'core:reply-all': () => {
        Actions.composeReply({
          thread: this.state.currentThread,
          message: this._lastMessage(),
          type: 'reply-all',
          behavior: 'prefer-existing',
        })
      },
      'core:forward': () => this._onForward(),
      'core:print-thread': () => this._onPrintThread(),
      'core:messages-page-up': () => this._onScrollByPage(-1),
      'core:messages-page-down': () => this._onScrollByPage(1),
    }

    if (this.state.canCollapse) {
      handlers['message-list:toggle-expanded'] = () => this._onToggleAllMessagesExpanded()
    }

    return handlers
  }

  _getMessageContainer = (clientId) => this.refs[`message-container-${clientId}`]

  _focusDraft = (draftElement) => {
    // Note: We don't want the contenteditable view competing for scroll offset,
    // so we block incoming childScrollRequests while we scroll to the new draft.
    this._draftScrollInProgress = true
    draftElement.focus()
    this.refs.messageWrap.scrollTo(draftElement, {
      position: ScrollRegion.ScrollPosition.Top,
      settle: true,
      done: () => { this._draftScrollInProgress = false },
    })
  }

  _onForward = () => {
    if (!this.state.currentThread) {
      return;
    }
    Actions.composeForward({thread: this.state.currentThread})
  }

  _renderSubject() {
    let subject = this.state.currentThread.subject
    if (!subject || subject.length === 0) {
      subject = "(No Subject)"
    }

    return (
      <div className="message-subject-wrap">
        <MailImportantIcon thread={this.state.currentThread} />
        <div style={{flex: 1}}>
          <span className="message-subject">{subject}</span>
          <MailLabelSet removable thread={this.state.currentThread} includeCurrentCategories />
        </div>
        {this._renderIcons()}
      </div>
    )
  }

  _renderIcons() {
    return (
      <div className="message-icons-wrap">
        {this._renderExpandToggle()}
        <div onClick={this._onPrintThread}>
          <RetinaImg name="print.png" title="Print Thread" mode={RetinaImg.Mode.ContentIsMask} />
        </div>
      </div>
    )
  }

  _renderExpandToggle() {
    if (!this.state.canCollapse) {
      return <span />
    }

    if (this.state.hasCollapsedItems) {
      return (
        <div onClick={this._onToggleAllMessagesExpanded}>
          <RetinaImg name={"expand.png"} title={"Expand All"} mode={RetinaImg.Mode.ContentIsMask} />
        </div>
      )
    }
    return (
      <div onClick={this._onToggleAllMessagesExpanded}>
        <RetinaImg name={"collapse.png"} title={"Collapse All"} mode={RetinaImg.Mode.ContentIsMask} />
      </div>
    )
  }

  _renderReplyArea() {
    return (
      <div className="footer-reply-area-wrap" onClick={this._onClickReplyArea} key="reply-area">
        <div className="footer-reply-area">
          <RetinaImg name="#{this._replyType()}-footer.png" mode={RetinaImg.Mode.ContentIsMask} />
          <span className="reply-text">Write a reply…</span>
        </div>
      </div>
    )
  }

  _lastMessage() {
    _.last(_.filter(
      (this.state.messages ? this.state.messages : []),
      (m) => !m.draft
    ))
  }

  // Returns either "reply" or "reply-all"
  _replyType() {
    const defaultReplyType = NylasEnv.config.get('core.sending.defaultReplyType')
    const lastMessage = this._lastMessage()

    if (lastMessage && lastMessage.canReplyAll()) {
      if (defaultReplyType === 'reply-all') {
        return 'reply-all'
      }
    }
    return 'reply'
  }

  _onToggleAllMessagesExpanded = () => Actions.toggleAllMessagesExpanded()

  _onPrintThread = () => {
    const node = ReactDOM.findDOMNode(this)
    Actions.printThread(this.state.currentThread, node.innerHTML)
  }

  _onClickReplyArea = () => {
    if (!this.state.currentThread) {
      return;
    }
    Actions.composeReply({
      thread: this.state.currentThread,
      message: this._lastMessage(),
      type: this._replyType(),
      behavior: 'prefer-existing-if-pristine',
    })
  }

  _messageElements() {
    const elements = []
    const lastMessage = _.last(this.state.messages)
    const hasReplyArea = !(lastMessage ? lastMessage.draft : null)
    const messages = this._messagesWithMinification(this.state.messages)
    messages.forEach((message, idx) => {
      if (message.type === "minifiedBundle") {
        elements.push(this._renderMinifiedBundle(message))
        return;
      }

      const collapsed = !this.state.messagesExpandedState[message.id]
      const isLastMsg = (messages.length - 1 === idx)
      const isBeforeReplyArea = isLastMsg && hasReplyArea

      elements.push(
        <MessageItemContainer
          key={message.clientId}
          ref={"message-container-#{message.clientId}"}
          thread={this.state.currentThread}
          message={message}
          collapsed={collapsed}
          isLastMsg={isLastMsg}
          isBeforeReplyArea={isBeforeReplyArea}
          scrollTo={this._scrollTo}
        />
      )
    })

    if (hasReplyArea) {
      elements.push(this._renderReplyArea())
    }

    return elements
  }

  _renderMinifiedBundle(bundle) {
    const BUNDLE_HEIGHT = 36
    const lines = bundle.messages.slice(0, 10)
    const h = Math.round(BUNDLE_HEIGHT / lines.length)

    return (
      <div
        className="minified-bundle"
        onClick={() => this.setState({minified: false})}
        key={Utils.generateTempId()}
      >
        <div className="num-messages">{bundle.messages.length} older messages</div>
        <div className="msg-lines" style={{height: h * lines.length}}>
          {lines.map((msg, i) =>
            <div key={msg.id} style={{height: h * 2, top: -h * i}} className="msg-line"></div>
          )}
        </div>
      </div>
    )
  }

  _messagesWithMinification(origMessages = []) {
    if (!this.state.minified) {
      return origMessages;
    }

    const messages = _.clone(origMessages)
    const minifyRanges = []
    let consecutiveCollapsed = 0

    messages.forEach((message, idx) => {
      if (idx === 0) {
        // Never minify the 1st message
        return;
      }

      const expandState = this.state.messagesExpandedState[message.id]

      if (!expandState) {
        consecutiveCollapsed += 1
      } else {
        // We add a +1 because we don't minify the last collapsed message,
        // but the MINIFY_THRESHOLD refers to the smallest N that can be in
        // the "N older messages" minified block.
        let minifyOffset = 0; // Stays 0 if expandState is "explicit"
        if (expandState === "default") {
          minifyOffset = 1
        }

        if (consecutiveCollapsed >= this.MINIFY_THRESHOLD + minifyOffset) {
          minifyRanges.push({
            start: idx - consecutiveCollapsed,
            length: (consecutiveCollapsed - minifyOffset),
          })
        }
        consecutiveCollapsed = 0
      }
    })

    let indexOffset = 0
    for (const range of minifyRanges) {
      const start = range.start - indexOffset
      const minified = {
        type: "minifiedBundle",
        messages: messages.splice(start, (start + range.length)),
      }
      messages.splice(start, range.length, minified)

      // While we removed `range.length` items, we also added 1 back in.
      indexOffset += (range.length - 1)
    }

    return messages
  }

  // Some child components (like the composer) might request that we scroll
  // to a given location. If `selectionTop` is defined that means we should
  // scroll to that absolute position.
  //
  // If messageId and location are defined, that means we want to scroll
  // smoothly to the top of a particular message.
  _scrollTo = ({clientId, rect, position} = {}) => {
    if (this._draftScrollInProgress) {
      return;
    }

    if (clientId) {
      const messageElement = this._getMessageContainer(clientId)
      if (!messageElement) {
        return;
      }
      const pos = position != null ? position : ScrollRegion.ScrollPosition.Visible
      this.refs.messageWrap.scrollTo(messageElement, {
        position: pos,
      })
    } else if (rect) {
      this.refs.messageWrap.scrollToRect(rect, {
        position: ScrollRegion.ScrollPosition.CenterIfInvisible,
      })
    } else {
      throw new Error("onChildScrollRequest: expected clientId or rect")
    }
  }

  _onScrollByPage = (direction) => {
    const height = ReactDOM.findDOMNode(this.refs.messageWrap).clientHeight
    this.refs.messageWrap.scrollTop += height * direction
  }

  _onChange = () => {
    const newState = this._getStateFromStores()
    if (this.state.currentThread && newState.currentThread &&
     this.state.currentThread.id !== newState.currentThread.id) {
      newState.minified = true
    }
    this.setState(newState)
  }

  _getStateFromStores= () => {
    return {
      messages: (MessageStore.items() ? MessageStore.items() : []),
      messagesExpandedState: MessageStore.itemsExpandedState(),
      canCollapse: MessageStore.items().length > 1,
      hasCollapsedItems: MessageStore.hasCollapsedItems(),
      currentThread: MessageStore.thread(),
      loading: MessageStore.itemsLoading(),
    }
  }

  render() {
    if (!this.state.currentThread) {
      return <span />
    }

    const wrapClass = classNames({
      "messages-wrap": true,
      "ready": !this.state.loading,
    })

    const messageListClass = classNames({
      "message-list": true,
      "height-fix": SearchableComponentStore.searchTerm != null,
    })

    return (
      <KeyCommandsRegion
        globalHandlers={this._globalKeymapHandlers()}
        globalMenuItems={this._globalMenuItems()}
      >
        <FindInThread ref="findInThread" />
        <div className={messageListClass} id="message-list">
          <ScrollRegion
            tabIndex="-1"
            className={wrapClass}
            scrollbarTickProvider={SearchableComponentStore}
            scrollTooltipComponent={MessageListScrollTooltip}
            ref="messageWrap"
          >
            {this._renderSubject()}
            <div className="headers" style={{position: 'relative'}}>
              <InjectedComponentSet
                className="message-list-headers"
                matching={{role: "MessageListHeaders"}}
                exposedProps={{thread: this.state.currentThread}}
                direction="column"
              />
            </div>
            {this._messageElements()}
          </ScrollRegion>
          <Spinner visible={this.state.loading} />
        </div>
      </KeyCommandsRegion>
    )
  }
}

SearchableComponentMaker.extend(MessageList)
export default MessageList
