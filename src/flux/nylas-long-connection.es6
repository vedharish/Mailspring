import Rx from 'rx-lite'


const DEFAULT_TIMEOUT = 30 * 60 * 1000
const MAX_BUFFER_SIZE = 100000
const {UNSENT, OPENED, HEADERS_RECEIVED, LOADING, DONE} = XMLHttpRequest

export const Status = {
  None: 'none',
  Connecting: 'connecting',
  Connected: 'connected',
  Closed: 'closed', // Socket has been closed for any reason
  Ended: 'ended', // We have received 'end()' and will never open again.
}

function XhrStreamingConnection({url, method = 'GET', timeout = DEFAULT_TIMEOUT}) {
  const xhr = new XMLHttpRequest()
  xhr.timeout = timeout

  const statusStreamObservable = Rx.Observable.create((observer) => {
    let lastReadyState = UNSENT
    xhr.onreadystatechange = () => {
      if (lastReadyState === xhr.readyState) { return }
      lastReadyState = xhr.readyState
      switch (xhr.readyState) {
      case OPENED:
        observer.onNext(Status.Connecting)
        break
      case HEADERS_RECEIVED:
        observer.onNext(Status.Connected)
        break
      case DONE:
        observer.onNext(Status.Closed)
        observer.onComplete()
        break
      default:
        return
      }
    }
  })

  const responseStreamObservable = Rx.Observable.create((observer) => {
    let offset = 0

    xhr.onreadystatechange = () => {
      const {status, responseText, readyState} = xhr
      if (responseText.length > MAX_BUFFER_SIZE) {
        xhr.abort()
        return
      }
      if (status !== 200) {
        observer.onError(responseText)
        return
      }
      if (!responseText) { return }
      if (readyState === LOADING) {
        const chunk = responseText.slice(offset)
        offset += chunk.length
        observer.onNext(chunk)
      }
      if (readyState === DONE) {
        const chunk = responseText.slice(offset)
        offset += chunk.length
        observer.onNext(chunk)
        observer.onComplete()
      }
    }

    xhr.onerror = (error) => {
      observer.onError(error)
    }
  })

  xhr.open(method, url)
  xhr.send()
  return {xhr, responseStreamObservable, statusStreamObservable}
}

function JSONStreamObservable(dataObservable) {
  let buffer = ''

  return Rx.Observable.create((observer) => {
    const onData = (data) => {
      buffer += data
      const rawJSONArray = buffer.split('\n')

      // We can't parse the last block - we don't know whether we've
      // received the entire delta or only part of it. Wait
      // until we have more.
      buffer = rawJSONArray.pop()

      try {
        const jsonData = rawJSONArray
          .filter(str => str.length > 0)
          .map(str => JSON.parse(str))
        observer.onNext(jsonData)
      } catch (e) {
        observer.onError(e)
      }
    }

    const disposable = dataObservable.subscribe(onData, observer.onError, observer.onCompleted)
    return Rx.Disposable.create(() => disposable.dispose())
  })
}

export default class NylasStreamingConnection {

  constructor({accountId, ...opts}) {
    this._accountId = accountId
    this._opts = opts
    this._status = Status.None

    this.xhr = null
    this._statusObservable = null
    this._jsonStreamObservable = null
    this._disposables = []
  }

  get accountId() {
    return this._accountId
  }

  get status() {
    return this._status
  }

  get statusObservable() {
    return this._statusObservable
  }

  get jsonStreamObservable() {
    return this._jsonStreamObservable
  }

  start() {
    if (![Status.None, Status.Closed].includes(this._status)) {
      return this
    }

    const {apiRoot, path, method, timeout} = this._opts
    const url = `${apiRoot}${path}`

    const {xhr, statusStreamObservable, responseStreamObservable} = XhrStreamingConnection({url, method, timeout})
    this.xhr = xhr
    this._statusObservable = statusStreamObservable
    this._jsonStreamObservable = JSONStreamObservable(responseStreamObservable)
    this._disposables = [
      this._statusObservable.subscribe(::this._onStatusChanged),
    ]

    return this
  }

  _onStatusChanged(status) {
    this._status = status
  }

  _dispose(status) {
    if (this.xhr) {
      this.xhr.abort()
    }
    this._setStatus(status)
    this._disposables.forEach(disposable => disposable.dispose())
  }

  close() {
    this._dispose(Status.Closed)
  }

  end() {
    this._dispose(Status.Ended)
  }
}
