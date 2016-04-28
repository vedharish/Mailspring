import {
  React,
  MetadataComposerStatusStore,
} from 'nylas-exports'
import {RetinaImg} from 'nylas-component-kit'
import classnames from 'classnames'

export default class MetadataComposerToggleButton extends React.Component {

  static displayName = 'MetadataComposerToggleButton';

  static propTypes = {
    title: React.PropTypes.func.isRequired,
    iconUrl: React.PropTypes.string,
    iconName: React.PropTypes.string,
    stickyToggle: React.PropTypes.bool,
    errorMessage: React.PropTypes.func.isRequired,

    draft: React.PropTypes.object.isRequired,
    session: React.PropTypes.object.isRequired,

    store: React.PropTypes.instanceOf(MetadataComposerStatusStore).isRequired,
    onSetEnabled: React.PropTypes.func.isRequired,
  };

  static defaultProps = {
    stickyToggle: false,
  };

  constructor(props) {
    super(props);

    this.state = {
      pending: false,
    };
  }

  _onClick = () => {
    if (this.state.pending) { return; }

    const currentStatus = this.props.store.isEnabled(this.props.draft);
    this.props.onSetEnabled({
      draft: this.props.draft,
      sticky: this.props.stickyToggle,
      session: this.props.session,
      enabled: !currentStatus,
      errorMessage: this.props.errorMessage,
    })
  };

  render() {
    const enabled = this.props.store.isEnabled(this.props.draft);
    const title = this.props.title(enabled);

    const className = classnames({
      btn: true,
      "btn-toolbar": true,
      "btn-pending": this.state.pending,
      "btn-enabled": enabled,
    });

    const attrs = {}
    if (this.props.iconUrl) {
      attrs.url = this.props.iconUrl
    } else if (this.props.iconName) {
      attrs.name = this.props.iconName
    }

    return (
      <button className={className} onClick={this._onClick} title={title} tabIndex={-1}>
        <RetinaImg {...attrs} mode={RetinaImg.Mode.ContentIsMask} />
      </button>
    );
  }

}
