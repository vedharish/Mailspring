import {React} from 'nylas-exports';

export default class ClickToCopyField extends React.Component {
  static displayName = 'ClickToCopyField';
  static propTypes = {
    value: React.PropTypes.string,
    width: React.PropTypes.string,
  };

  constructor(props) {
    super(props)
    this.state = {justCopied: false};
    this.timeout = null;
  }

  componentWillUnmount() {
    clearTimeout(this.timeout);
  }

  // TODO: this isn't necessary if the popover definitely disappears before a
  // user copies something else. It doesn't stay open on my system, but maybe
  // it's possible on another?
  _timePassed = () => {
    this.setState({justCopied: false});
  }

  _onClick = (e) => {
    e.target.select();
    if (document.execCommand('copy')) {
      this.setState({justCopied: true});
      this.timeout = setTimeout(this._timePassed, 2000);
    }
  }

  render() {
    let caption = this.state.justCopied ? "Copied successfully!" :
      "Click to copy.";

  // TODO: don't inline style on caption div, use ui-variables
    return (
      <div>
        <input
          type="text"
          value={this.props.value}
          onClick={this._onClick}
          style={{width: this.props.width}}
          onChange={() => null}
        />
        <div style={{fontSize: "11px"}}>
          {caption}
        </div>
      </div>
    )
  }
}
