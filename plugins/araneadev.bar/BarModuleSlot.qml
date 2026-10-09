// Registry-backed bar module slot. Bar.qml remains the owner of lifecycle,
// registry state, click routing, and drag persistence.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Item {
  id: slot

  // Public contract member.
  property var owner: null
  // Public contract member.
  property var entry: null
  // Public contract member.
  property string moduleId: ""
  // Public contract member.
  property string region: ""
  // Public contract member.
  property bool openIndicatorVisible: false
  // Public contract member.
  property real openIndicatorPosition: 0.5

  // Canonical entry identity.
  readonly property string moduleName: owner && entry ? owner.entryId(entry) : moduleId
  // Settings passed to the loaded widget.
  readonly property var moduleSettings: owner && entry ? owner.entrySettings(entry) : ({})
  // Custom entry mode, if configured.
  readonly property string customType: owner && entry ? owner.customModuleType(entry) : ""
  // Registry metadata used to select the plugin API surface.
  readonly property var registryMetadata: owner && owner.barWidgetRegistry && owner.barWidgetRegistry.metadataFor ? owner.barWidgetRegistry.metadataFor(owner.canonicalWidgetId(moduleName)) : null
  // Whether this is a first-party widget.
  readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
  // Stable API identifier for the loaded widget.
  readonly property string pluginApiId: registered && owner ? owner.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
  // Reading the registry widgets property keeps this binding live when the
  // host enables, disables, or replaces a bar widget.
  readonly property var registryComponent: {
    if (!owner || !owner.barWidgetRegistry || customType)
      return null
    var w = owner.barWidgetRegistry.widgets
    var registryName = owner.canonicalWidgetId(moduleName)
    return w[registryName] ? w[registryName].component : null
  }
  // Whether the entry loads a custom QML source.
  readonly property bool qmlCustom: customType === "qml"
  // Whether the entry runs a configured command.
  readonly property bool commandCustom: customType === "command"
  // Whether the host registry supplied a widget component.
  readonly property bool registered: registryComponent !== null
  // Currently loaded widget item.
  readonly property var activeItem: {
    if (registered)
      return registryLoader.item
    if (qmlCustom)
      return qmlLoader.item
    return componentLoader.item
  }
  // Whether the pointer is over this slot.
  readonly property bool hovered: moduleHover.hovered
  // Whether this slot is the active drag source.
  readonly property bool dragSource: owner && owner.barDragSource === slot
  // Whether this slot owns the open panel.
  readonly property bool panelOpen: owner && owner.activePopout === slot.activeItem
  // Length of the panel-open indicator along the bar.
  readonly property real panelIndicatorExtent: {
    var vertical = owner && owner.vertical
    var key = vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
    var hint = activeItem && key in activeItem ? activeItem[key] : undefined
    if (hint !== undefined && hint !== null && hint > 0)
      return Math.round(hint)
    return Math.max(Style.space(10), Math.round((vertical ? slot.height : slot.width) * 0.55))
  }

  implicitWidth: activeItem && activeItem.visible ? (owner && owner.vertical ? owner.barSize : activeItem.implicitWidth) : 0
  implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight
  z: modulePointer.dragging ? 100 : 0

  Component.onCompleted: if (owner)
    owner.registerModuleSlot(slot)
  Component.onDestruction: {
    if (!owner)
      return
    if (owner.barDragSource === slot)
      owner.clearBarDrag()
    owner.unregisterModuleSlot(slot)
  }

  HoverHandler {
    id: moduleHover
  }

  BorderSurface {
    visible: slot.dragSource
    anchors.fill: parent
    anchors.margins: Style.space(1)
    color: owner && owner.transparent ? "transparent" : owner ? owner.background : "transparent"
    borderSpec: Border.flat(owner ? owner.barForeground : Color.bar.text, 1)
    radius: Math.min(Style.cornerRadius, height / 2)
    opacity: owner && owner.transparent ? 0.22 : 0.32
  }

  Loader {
    id: componentLoader
    active: !slot.qmlCustom && !slot.registered
    sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Loader {
    id: registryLoader
    active: slot.registered
    sourceComponent: slot.registered ? slot.registryComponent : null
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Loader {
    id: qmlLoader
    active: slot.qmlCustom
    source: slot.qmlCustom && owner ? owner.customModuleSource(slot.entry) : ""
    anchors.fill: parent
    opacity: slot.dragSource ? 0.22 : 1.0
    onLoaded: {
      slot.injectProps()
      Qt.callLater(slot.injectProps)
    }
  }

  Rectangle {
    id: openPanelIndicator
    readonly property int inset: Style.space(3)

    visible: opacity > 0
    opacity: (slot.panelOpen || slot.openIndicatorVisible) && !slot.dragSource ? 0.75 : 0
    color: Color.accent
    radius: Math.min(width, height) / 2
    width: owner && owner.vertical ? Style.space(2) : (slot.openIndicatorVisible ? Style.space(12) : slot.panelIndicatorExtent)
    height: owner && owner.vertical ? (slot.openIndicatorVisible ? Style.space(12) : slot.panelIndicatorExtent) : Style.space(2)
    x: owner && owner.vertical ? (owner.position === "left" ? parent.width - width - inset : inset) : (slot.openIndicatorVisible ? Math.max(0, Math.min(parent.width - width, parent.width * slot.openIndicatorPosition - width / 2)) : Math.round((parent.width - width) / 2))
    y: owner && owner.vertical ? (slot.openIndicatorVisible ? Math.max(0, Math.min(parent.height - height, parent.height * slot.openIndicatorPosition - height / 2)) : Math.round((parent.height - height) / 2)) : (owner && owner.position === "top" ? parent.height - height - inset : inset)
    z: 50

    Behavior on opacity {
      enabled: !!(slot.owner && slot.owner.motionEnabled)
      NumberAnimation {
        duration: Aranea.DesignTokens.feedbackDuration
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    id: modulePointer
    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property bool canReorder: !!(owner && owner.shell && typeof owner.shell.mutateShellConfig === "function")
    readonly property real dragThreshold: Style.space(4)

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    enabled: !!owner && slot.visible && slot.width > 0 && slot.height > 0
    propagateComposedEvents: true
    cursorShape: owner && owner.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor

    onPressed: function (mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
      if (owner)
        owner.clearBarDrag()
    }

    onPositionChanged: function (mouse) {
      if (!owner || !canReorder || !(mouse.buttons & Qt.LeftButton))
        return
      var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
      if (distance >= dragThreshold) {
        if (!dragging) {
          owner.barDragWindow = owner.targetWindow(slot.activeItem) || owner.targetWindow(slot)
          owner.barDragScreen = owner.barDragWindow ? owner.barDragWindow.screen : null
          owner.barDragOffsetX = pressedX
          owner.barDragOffsetY = pressedY
          owner.captureBarDragGhost(slot)
          owner.barDragSource = slot
        }
        dragging = true
        owner.hideTooltip(slot.activeItem)
      }

      if (dragging) {
        var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
        var screenPoint = owner.barDragScreenPoint(scenePoint)
        owner.barDragSceneX = scenePoint.x
        owner.barDragSceneY = scenePoint.y
        owner.barDragScreenX = screenPoint.x
        owner.barDragScreenY = screenPoint.y
        var drop = owner.moduleDropAtScene(scenePoint, slot)
        owner.barDragTarget = drop ? drop.slot : null
        owner.barDragAfter = drop ? drop.after : false
        owner.barDragTargetGeometry = drop ? owner.dropMarkerRect(drop.slot, drop.after) : null
      }
    }

    onReleased: function (mouse) {
      if (!owner)
        return
      var wasDragging = dragging
      var targetSlot = owner.barDragTarget
      var afterTarget = owner.barDragAfter
      if (wasDragging)
        suppressClick = true
      dragging = false
      owner.clearBarDrag()
      if (wasDragging && targetSlot) {
        owner.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
        mouse.accepted = true
      } else if (!wasDragging) {
        mouse.accepted = false
      }
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      if (owner)
        owner.clearBarDrag()
    }

    onClicked: function (mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
        return
      }
      if (owner && !owner.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y))
        mouse.accepted = false
    }
  }

  onActiveItemChanged: Qt.callLater(injectProps)
  onModuleSettingsChanged: injectProps()

  // Injects bar, module identity, and settings into the loaded widget.
  function injectProps() {
    var target = activeItem
    if (!target || !owner)
      return
    if ("bar" in target)
      target.bar = firstParty ? owner : owner.pluginBarApiFor(pluginApiId, moduleName, registered)
    if ("moduleName" in target)
      target.moduleName = moduleName
    if ("settings" in target)
      target.settings = moduleSettings
  }

  Component {
    id: emptyModuleComponent
    Item {
      implicitWidth: 0
      implicitHeight: 0
      visible: false
    }
  }

  Component {
    id: customCommandModuleComponent
    CustomCommandModule {
      owner: slot.owner
      entry: slot.entry
    }
  }
}
