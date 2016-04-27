React = require 'react'
ReactDOM = require 'react-dom'
_ = require 'underscore'
UnsafeComponent = require './unsafe-component'
Flexbox = require './flexbox'
InjectedComponentLabel = require './injected-component-label'
{Utils,
 Actions,
 WorkspaceStore,
 ComponentRegistry} = require "nylas-exports"
{RetinaImg, Menu} = require 'nylas-component-kit'


class MoreBtn extends React.Component
  @displayName: "MoreBtn"

  @width: 75

  @containerRequired: false

  @propTypes:
    onClick: React.PropTypes.func,
    components: React.PropTypes.array,
    exposedProps: React.PropTypes.object,
    overflowVisible: React.PropTypes.bool,
    visibleComponents: React.PropTypes.array,
    overflowData: React.PropTypes.shape
      overflowButtonStyles: React.PropTypes.object
      overflowButtonClassName: React.PropTypes.string

  @defaultProps:
    components: []
    onClick: () ->
    overflowData: {
      overflowButtonStyles: {}
      overflowButtonClassName: ""
    }
    visibleComponents: []

  render: ->
    className = @props.overflowData.overflowButtonClassName
    if @props.overflowVisible then className += " btn-enabled"

    <button style={@props.overflowData.overflowButtonStyles}
            className={className}
            onClick={@props.onClick}>
      <RetinaImg name="icon-composer-overflow.png" mode={RetinaImg.Mode.ContentIsMask}/>
    </button>

###
Public: InjectedComponent makes it easy to include a set of dynamically registered
components inside of your React render method. Rather than explicitly render
an array of buttons, for example, you can use InjectedComponentSet:

```coffee
<InjectedComponentSet className="message-actions"
                  matching={role: 'ThreadActionButton'}
                  exposedProps={thread:@props.thread, message:@props.message}>
```

InjectedComponentSet will look up components registered for the location you provide,
render them inside a {Flexbox} and pass them `exposedProps`. By default, all injected
children are rendered inside {UnsafeComponent} wrappers to prevent third-party code
from throwing exceptions that break React renders.

InjectedComponentSet monitors the ComponentRegistry for changes. If a new component
is registered into the location you provide, InjectedComponentSet will re-render.

If no matching components is found, the InjectedComponent renders an empty span.

Section: Component Kit
###
class InjectedComponentSet extends React.Component
  @displayName: 'InjectedComponentSet'

  ###
  Public: React `props` supported by InjectedComponentSet:

   - `matching` Pass an {Object} with ComponentRegistry descriptors
      This set of descriptors is provided to {ComponentRegistry::findComponentsForDescriptor}
      to retrieve components for display.
   - `matchLimit` (optional) A {Number} that indicates the max number of matching elements to render
   - `className` (optional) A {String} class name for the containing element.
   - `children` (optional) Any React elements rendered inside the InjectedComponentSet
      will always be displayed.
   - `onComponentsDidRender` Callback that will be called when the injected component set
      is successfully rendered onto the DOM.
   - `exposedProps` (optional) An {Object} with props that will be passed to each
      item rendered into the set.
   - `containersRequired` (optional). Pass false to optionally remove the containers
      placed around injected components to isolate them from the rest of the app.

   -  Any other props you provide, such as `direction`, `data-column`, etc.
      will be applied to the {Flexbox} rendered by the InjectedComponentSet.
  ###
  @propTypes:
    matching: React.PropTypes.object.isRequired
    children: React.PropTypes.array
    maxWidth: React.PropTypes.number
    className: React.PropTypes.string
    matchLimit: React.PropTypes.number
    exposedProps: React.PropTypes.object
    overflowData: React.PropTypes.object
    containersRequired: React.PropTypes.bool
    onComponentsDidRender: React.PropTypes.func

  @defaultProps:
    direction: 'row'
    exposedProps: {}
    containersRequired: true
    onComponentsDidRender: ->

  constructor: (@props) ->
    @state = @_getStateFromStores()
    @state.overflowVisible = false
    @_renderedElements = new Set()

  componentDidMount: =>
    @_componentUnlistener = ComponentRegistry.listen =>
      @setState(@_getStateFromStores())
    @delayedComponentsDidUpdate()

  componentWillUnmount: =>
    @_componentUnlistener() if @_componentUnlistener

  componentWillReceiveProps: (newProps) =>
    components = @state.components
    state = @_getStateFromStores(newProps)
    state.visibleComponents = components
    @setState(state)

  componentDidUpdate: =>
    @delayedComponentsDidUpdate()

  delayedComponentsDidUpdate: ({notify}={}) ->
    if @props.maxWidth
      visibleComponents = []
      widthAcc = 0
      spaceAvailable = @props.maxWidth - MoreBtn.width

      for data in @_getRenderedComponentData()
        continue unless data
        {component, element} = data
        widthAcc += ReactDOM.findDOMNode(element).getBoundingClientRect().width
        break if widthAcc > spaceAvailable
        visibleComponents.push(component)

      if not _.isEqual(visibleComponents, @state.visibleComponents)
        @setState({visibleComponents})

    if notify or @props.containersRequired is false
      @props.onComponentsDidRender()

  _elementsAtCurrentWidth: ->
    if @props.maxWidth
      if @state.visibleComponents.length is @state.components.length
        return @state.visibleComponents
      else
        return @state.visibleComponents.concat(MoreBtn)
    else
      return @state.components

  _overflowComponents: ->
    _.difference @state.components, @_elementsAtCurrentWidth()

  _onMoreClick: =>
    @setState(overflowVisible: !@state.overflowVisible)

  _renderMoreBtn: (component) ->
    <component
      onClick={@_onMoreClick}
      components={@state.components}
      overflowData={@props.overflowData}
      exposedProps={@props.exposedProps}
      overflowVisible={@state.overflowVisible}
      visibleComponents={@state.visibleComponents}
      ref={component.displayName} key={component.displayName} />

  _renderComponents: (components) ->
    return components.map (component, i) =>
      return @_renderMoreBtn(component) if component is MoreBtn
      if @props.containersRequired is false or component.containerRequired is false
        return <component ref={component.displayName} key={component.displayName} {...@props.exposedProps} />
      else
        return (
          <UnsafeComponent
            ref={component.displayName}
            key={component.displayName}
            component={component}
            onComponentDidRender={@_onComponentDidRender.bind(@, component.displayName)}
            {...@props.exposedProps} />
        )

  render: =>
    @_renderedElements = new Set()
    flexboxProps = Utils.fastOmit(@props, Object.keys(@constructor.propTypes))
    flexboxClassName = @props.className ? ""

    visibleElements = @_renderComponents(@_elementsAtCurrentWidth())
    overflowElements = @_renderComponents(@_overflowComponents())

    displayOverflow = "none"
    if @state.overflowVisible && overflowElements.length > 0
      displayOverflow = "flex"

    if @state.visible
      flexboxClassName += " registered-region-visible"
      visibleElements.splice(0,0, <InjectedComponentLabel key="_label" matching={@props.matching} {...@props.exposedProps} />)
      visibleElements.push(<span key="_clear" style={clear:'both'}/>)

    <Flexbox className={flexboxClassName} {...flexboxProps}>
      {visibleElements}
      <div className="overflow-wrap" style={display: displayOverflow}>{overflowElements}</div>
      {@props.children ? []}
    </Flexbox>

  _onComponentDidRender: (componentName) =>
    @_renderedElements.add(componentName)
    if @_renderedElements.size is @_elementsAtCurrentWidth().length
      @delayedComponentsDidUpdate(notify: true)

  _getRenderedComponentData: ->
    componentsByName = {}
    for component, i in @state.components
      componentsByName[component.displayName] = {component, i}

    elData = _.map @refs, (element, displayName) =>
      c = componentsByName[displayName]
      return null if ReactDOM.findDOMNode(element).closest(".overflow-wrap")
      return null unless c
      {element, displayName, component: c.component, i: c.i}

    elData = _.compact(elData)

    elementData = _.sortBy(elData, ({element, displayName, component, i}) =>
      order = parseInt(window.getComputedStyle(ReactDOM.findDOMNode(element)).order ? 0)
      return order + i/100
    )
    return elementData

  _getStateFromStores: (props) =>
    props ?= @props
    state = @state ? {}
    limit = props.matchLimit
    components = ComponentRegistry.findComponentsMatching(@props.matching)[...limit]

    if not _.isEqual(components, (state.components ? []))
      visibleComponents = (state.visibleComponents ? [])
    else
      visibleComponents = components

    return {
      components: components,
      visibleComponents: visibleComponents,
      visible: ComponentRegistry.showComponentRegions(),
    }


module.exports = InjectedComponentSet
