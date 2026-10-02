// Aranea Weather (araneadev.weather, cloned from omarchy.weather): the
// bar's weather pill and the host for the detail popup. This is the Task 2
// clone: the stock root logic, markup and IPC target below are unchanged
// from Omarchy's Weather, so the bar entry keeps working identically while
// the Aranea-native dropdown view lands in a later task.
// Temporary for this clone (stock's dynamic root.bar.* access and its lack
// of ComponentBehavior: Bound); Task 4 removes this once the view is rebuilt.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons
import qs.Ui

// Weather pill for the bar, and the host for the detail popup.
//
// Left click opens the detail popup, right click sends the current status
// as a notification, and middle click forces a refresh.
BarWidget {
  id: root
  moduleName: "omarchy.weather"

  // Hands the loaded Panel.qml instance the bar, settings and anchor it
  // needs; called again after load since the loader's onLoaded can race the
  // bindings below.
  function injectPanel() {
    var target = panelLoader.item
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

  // Re-fetches the forecast through the open panel, if any (the IPC refresh
  // method and the middle-click handler below both call this).
  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh)
      panelLoader.item.refresh()
  }

  // Opens the popup if closed, closes it if open.
  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle)
      panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). Open maps to the
  // panel's hotkey path so summoning suppresses the center hover reveal,
  // matching what the old per-plugin IpcHandler did.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // Opens the detail popup via the panel's hotkey path.
  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey)
      panelLoader.item.openFromHotkey()
  }

  // Closes the detail popup.
  function close() {
    if (panelLoader.item && panelLoader.item.close)
      panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  // Closes the popup for a popout hand-off rather than a normal dismissal.
  function closeForPopoutSwitch() {
    if (panelLoader.item)
      panelLoader.item.closeForPopoutSwitch()
  }

  visible: panelLoader.item && panelLoader.item.label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : ""
    slotSize: Style.bar.statusSlot
    // Tooltip suppressed because the panel is the detail view.
    tooltipText: ""

    onPressed: function (b) {
      if (!root.bar)
        return
      if (b === Qt.RightButton)
        root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
      else if (b === Qt.MiddleButton)
        root.refresh()
      else
        root.togglePanel()
    }
  }
}
