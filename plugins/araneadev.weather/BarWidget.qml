// Aranea Weather (araneadev.weather, cloned from omarchy.weather): the
// bar's weather pill and the host for the dropdown. Stock's pill, click
// handling, popup host and IPC target stay. Added: weatherPanel, through
// which the per-monitor instances share one fetch per interval.
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

  // Re-fetches the forecast through the panel, if loaded (the middle-click
  // handler below calls this): an explicit refresh, so it fetches even
  // when another instance's report is still fresh.
  function refresh() {
    // qmllint disable missing-property
    if (panelLoader.item && panelLoader.item.refresh)
      panelLoader.item.refresh()
    // qmllint enable missing-property
  }

  // Opens the popup if closed, closes it if open.
  function togglePanel() {
    // qmllint disable missing-property
    if (panelLoader.item && panelLoader.item.toggle)
      panelLoader.item.toggle()
    // qmllint enable missing-property
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). Open maps to the
  // panel's hotkey path so summoning suppresses the center hover reveal,
  // matching what the old per-plugin IpcHandler did.
  // qmllint disable missing-property
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  // qmllint enable missing-property

  // Opens the detail popup via the panel's hotkey path.
  function open() {
    // qmllint disable missing-property
    if (panelLoader.item && panelLoader.item.openFromHotkey)
      panelLoader.item.openFromHotkey()
    // qmllint enable missing-property
  }

  // Closes the detail popup.
  function close() {
    // qmllint disable missing-property
    if (panelLoader.item && panelLoader.item.close)
      panelLoader.item.close()
    // qmllint enable missing-property
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  // qmllint disable missing-property
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  // qmllint enable missing-property

  // Closes the popup for a popout hand-off rather than a normal dismissal.
  function closeForPopoutSwitch() {
    // qmllint disable missing-property
    if (panelLoader.item)
      panelLoader.item.closeForPopoutSwitch()
    // qmllint enable missing-property
  }

  // This instance's loaded Panel.qml, or null; the other monitors' panels
  // read its published report and fetch state through it
  // (Panel.instancePanels).
  readonly property var weatherPanel: panelLoader.item

  // qmllint disable missing-property
  visible: panelLoader.item && panelLoader.item.label !== ""
  // qmllint enable missing-property
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
    // qmllint disable missing-property
    text: panelLoader.item ? panelLoader.item.label : ""
    // qmllint enable missing-property
    slotSize: Style.bar.statusSlot
    // Tooltip suppressed because the panel is the detail view.
    tooltipText: ""

    onPressed: function (b) {
      if (!root.bar)
        return
      // qmllint disable missing-property
      if (b === Qt.RightButton)
        root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
      else if (b === Qt.MiddleButton)
        root.refresh()
      else
        root.togglePanel()
    // qmllint enable missing-property
    }
  }
}
