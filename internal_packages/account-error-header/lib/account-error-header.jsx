import {AccountStore, Actions, React} from 'nylas-exports'
import {RetinaImg} from 'nylas-component-kit'

export default class AccountErrorHeader extends React.Component {
  static displayName = 'AccountErrorHeader';

  constructor() {
    super();
    this.state = this.getStateFromStores();
  }

  componentDidMount() {
    this.unsubscribe = AccountStore.listen(() => this._onAccountsChanged());
  }

  getStateFromStores() {
    return {accounts: AccountStore.accounts()}
  }

  _onAccountsChanged() {
    this.setState(this.getStateFromStores())
  }

  reconnect(account) {
    const ipc = require('electron').ipcRenderer;
    ipc.send('command', 'application:add-account', account.provider);
  }

  openPreferences() {
    Actions.switchPreferencesTab('Accounts');
    Actions.openPreferences()
  }

  renderErrorHeader(message, actionCallback) {
    return (
      <div className="notifications-sticky">
        <div className={`notifications-sticky-item notification-error has-default-action`}
             onClick={actionCallback}>
          <RetinaImg
          url="nylas://account-error-header/assets/icon-alert-onred@2x.png`"
          mode={RetinaImg.Mode.ContentIsMask} />
          <div>{message}</div>
          <a className="action default" onClick={actionCallback}>
            {"Reconnect"}
          </a>
        </div>
      </div>)
  }

  render() {
    const errorAccounts = this.state.accounts.filter(a => a.syncState !== "running");
    if (errorAccounts.length === 1) {
      const account = errorAccounts[0];
      return this.renderErrorHeader(
        `Nylas N1 can no longer authenticate with ${account.emailAddress}. You
        will not be able to send or receive mail. Please click here to reconnect your account.`,
        ()=>this.reconnect(account));
    }
    if (errorAccounts.length > 1) {
      return this.renderErrorHeader("Nylas N1 can no longer authenticate with several of your accounts. You will not be able to send or receive mail. Please click here to reconnect your accounts.",
          ()=>this.openPreferences());
    }
    return false;
  }
}