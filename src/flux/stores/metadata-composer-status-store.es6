import NylasStore from 'nylas-store'
import Actions from '../actions'

export default class MetadataComposerStatusStore extends NylasStore {
  configKey() {
    return `plugins.${this.PLUGIN_ID}.defaultOn`
  }

  isEnabledByDefault() {
    return NylasEnv.config.get(this.configKey())
  }

  isEnabled(draft) {
    return draft.metadataForPluginId(this.PLUGIN_ID)[this.METADATA_KEY]
  }

  setEnabled = ({draft, session, enabled, sticky, errorMessage}) => {
    const {NylasAPI, APIError} = require('nylas-exports')

    NylasAPI.authPlugin(this.PLUGIN_ID, this.PLUGIN_NAME, draft.accountId)
    .then(() => {
      const dir = enabled ? "Enabled" : "Disabled"
      Actions.recordUserEvent(`${this.PLUGIN_NAME} ${dir}`)
      const newValue = this.initialValue()
      session.changes.addPluginMetadata(this.PLUGIN_ID, newValue);
      if (sticky) {
        NylasEnv.config.set(this.configKey(), enabled)
      }
    })
    .catch((error) => {
      if (sticky) {
        NylasEnv.config.set(this.configKey(), false)
      }

      let title = "Error"
      if (!(error instanceof APIError)) {
        NylasEnv.reportError(error);
      } else if (error.statusCode === 400) {
        NylasEnv.reportError(error);
      } else if (NylasAPI.TimeoutErrorCodes.includes(error.statusCode)) {
        title = "Offline"
      }

      NylasEnv.showErrorDialog({title, message: errorMessage(error)});
    }).finally(() => {
      this.setState({pending: false})
    });
  }

}
