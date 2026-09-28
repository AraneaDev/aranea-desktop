// Update bar widget with a native update center panel.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "UpdateLogic.js" as UpdateLogic

Item {
  id: root
  // Bar host injected by Omarchy.
  property var bar: null
  // Registry identifier for IPC and layout lookup.
  property string moduleName: "araneadev.updates"
  // Per-instance shell settings.
  property var settings: ({})
  // Test-only update status override.
  property var testStatus: null
  // Whether the update panel is open.
  property bool panelOpen: false
  // Open state exposed to the panel host.
  readonly property bool opened: panelOpen
  // Current service status.
  readonly property var status: service.status
  // Compact visibility and severity state.
  readonly property var display: UpdateLogic.displayState(status)

  IpcHandler {
    target: root.moduleName
    function open(): void {
      root.open()
    }
    function close(): void {
      root.close()
    }
    function toggle(): void {
      root.toggle()
    }
  }
  Service {
    id: service
    autoStart: root.testStatus === null
    testStatus: root.testStatus
  }
  visible: display.visible
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Open the update panel.
  function open() {
    panelOpen = true
  }
  // Close the update panel.
  function close() {
    panelOpen = false
  }
  // Toggle the update panel.
  function toggle() {
    panelOpen = !panelOpen
  }
  // Switch to the adjacent panel in the bar.
  function switchPanel(direction) {
    return bar && typeof bar.switchPanelFrom === "function" ? bar.switchPanelFrom(root, direction) : false
  }
  // Launch the system updater.
  function openUpdater() {
    if (bar)
      bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-update")
  }
  // Load the production panel after the bar host is available.
  function loadLivePanel() {
    if (root.testStatus === null && root.bar && panelLoader.item === null)
      panelLoader.setSource(Qt.resolvedUrl("UpdatePanelHost.qml"), {
        anchorItem: button,
        owner: root,
        bar: root.bar
      })
  }
  onBarChanged: loadLivePanel()
  Component.onCompleted: loadLivePanel()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "↥" + root.display.countText
    tooltipText: root.status.rebootRequired ? "Updates available · reboot required" : "Updates available"
    active: root.panelOpen
    horizontalMargin: 7
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.LeftButton)
        root.toggle()
      else if (mouseButton === Qt.RightButton)
        root.openUpdater()
    }
  }

  component PanelContent: Item {
    property var status: ({})
    property int cursorIndex: 0
    signal openUpdater
    signal refresh
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    UpdatePanel {
      id: content
      anchors.fill: parent
      status: parent.status
      cursorIndex: parent.cursorIndex
      onOpenUpdater: parent.openUpdater()
      onRefresh: parent.refresh()
    }
  }

  component TestPanelHost: Item {
    id: testHost
    property var status: ({})
    property int cursorIndex: 0
    property bool open: false
    signal openUpdater
    signal refresh
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) {
        root.switchPanel(direction)
      }
      onMoveRequested: function (dx, dy) {
        if (dy !== 0)
          testHost.cursorIndex = (testHost.cursorIndex + dy + 2) % 2
      }
      onTextKey: function (text) {
        if (text === "r" || text === "R")
          testHost.refresh()
      }
      onActivateRequested: testHost.cursorIndex === 0 ? testHost.openUpdater() : testHost.refresh()
      PanelContent {
        id: content
        anchors.fill: parent
        status: testHost.status
        cursorIndex: testHost.cursorIndex
        onOpenUpdater: testHost.openUpdater()
        onRefresh: testHost.refresh()
      }
    }
  }

  Component {
    id: testPanelHost
    TestPanelHost {}
  }
  Loader {
    id: panelLoader
    sourceComponent: root.testStatus !== null ? testPanelHost : null
    onLoaded: {
      item.status = Qt.binding(function () {
        return root.status
      })
      item.open = Qt.binding(function () {
        return root.panelOpen
      })
    }
  }
  Connections {
    target: panelLoader.item
    function onOpenUpdater() {
      root.openUpdater()
    }
    function onRefresh() {
      service.refresh()
    }
  }
}
