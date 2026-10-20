// Globe button and the bar-slot owner for the Elsewhen-compatible panel.
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  // Runtime bar geometry token object; the host supplies its members dynamically.
  readonly property var barSizes: Style.bar
  moduleName: "omarchy.elsewhen"
  // The slot itself is the coordinator identity, as with Aranea Clock.
  // qmllint disable missing-property
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  // Forwards the outgoing popout handoff state to the coordinator.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  // This slot's loaded world-clock panel.
  readonly property var worldClockPanel: panelLoader.item
  // Refreshes host settings and zone observations before showing the panel.
  function open() {
    if (panelLoader.item)
      panelLoader.item.open()
  }
  // Closes through the shared controller; lifecycle cleanup discards search.
  function close() {
    if (panelLoader.item)
      panelLoader.item.close()
  }
  // Toggles this slot's panel.
  function togglePanel() {
    if (panelLoader.item)
      panelLoader.item.toggle()
  }
  // Closes with the shared popout handoff protocol.
  function closeForPopoutSwitch() {
    if (panelLoader.item)
      panelLoader.item.closeForPopoutSwitch()
  }
  // Applies a display-only override to this instance when loaded.
  function showcaseHere(payload) {
    return panelLoader.item ? panelLoader.item.showcase(payload) : "closed"
  }
  // Routes display-only screenshot data to whichever monitor owns the open panel.
  function showcase(payload) {
    let hosts = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : [root]
    for (let i = 0; i < hosts.length; i++)
      if (hosts[i] && hosts[i].opened && typeof hosts[i].showcaseHere === "function")
        return hosts[i].showcaseHere(payload)
    return "closed"
  }
  // qmllint enable missing-property
  // Dynamic Loader item exposes the panel host contract.
  // qmllint disable missing-property
  function injectPanel() {
    let target = panelLoader.item
    if (!target)
      return
    if ("bar" in target)
      target.bar = root.bar
    if ("settings" in target)
      target.settings = root.settings
    if ("anchorItem" in target)
      target.anchorItem = button
    if ("hostWidget" in target)
      target.hostWidget = root
  }
  // qmllint enable missing-property
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
  IpcHandler {
    target: "omarchy.elsewhen"
    function open(): void {
      root.open()
    }
    function close(): void {
      root.close()
    }
    function show(): void {
      root.open()
    }
    function hide(): void {
      root.close()
    }
    function toggle(): void {
      root.togglePanel()
    }
    function showcase(payload: string): string {
      return root.showcase(payload)
    }
  }
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xf01e7)
    slotSize: root.barSizes.statusSlot
    // Tooltip uses the last open sample; closed panels have no clock tick.
    // qmllint disable missing-property
    tooltipText: panelLoader.item && panelLoader.item.tooltipText ? panelLoader.item.tooltipText : "World clock"
    // qmllint enable missing-property
    onPressed: function (button) {
      if (button === Qt.LeftButton)
        root.togglePanel()
    }
  }
}
