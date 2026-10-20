// Update bar widget with a native update center panel.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "UpdateLogic.js" as UpdateLogic
import "../araneadev.shared" as Aranea
import "../araneadev.shared/CursorLogic.js" as CursorLogic

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
  onPanelOpenChanged: if (panelOpen)
    service.refresh()
  // Current service status.
  readonly property var status: service.status
  // Whether Service is running a check right now.
  readonly property bool checking: service.checking
  // Compact visibility and severity state.
  readonly property var display: UpdateLogic.displayState(status)
  // Reveal the inactive icon while the center section is being hovered.
  readonly property bool hoverRevealed: !!(bar && bar.centerSectionRevealHeld === true)
  // Whether the compact update button should occupy and paint its slot.
  readonly property bool iconVisible: root.display.visible || root.hoverRevealed || root.panelOpen
  // Inactive hover previews use the same subdued treatment as other indicators.
  readonly property bool iconDimmed: !root.display.visible
  // Tooltip text distinguishes the inactive hover preview from actionable state.
  readonly property string iconTooltip: root.display.visible ? (root.status.rebootRequired ? "Updates available · reboot required" : "Updates available") : "No updates available"

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
  visible: true
  implicitWidth: iconVisible ? button.implicitWidth : 0
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
    visible: root.iconVisible
    dimmed: root.iconDimmed
    tooltipText: root.iconTooltip
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
    // The update status shown (see UpdatePanel.status).
    property var status: ({})
    // Whether a check is running: the Refresh pill pulses and ignores clicks.
    property bool checking: false
    // The pill the keyboard cursor is on.
    property int cursorIndex: 0
    // Whether the keyboard cursor shows (keyboard use only).
    property bool keyboardCursor: false
    // Emitted to open the updater.
    signal openUpdater
    // Emitted to start a check.
    signal refresh
    // Emitted when a real pointer move lands on pill INDEX.
    signal pillHovered(int index)
    implicitWidth: contentObject.implicitWidth
    implicitHeight: contentObject.implicitHeight
    // Resets the inner panel's pointer gate; forwarded so a host's key
    // handling can disarm it without reaching into the panel directly.
    function disarmPointer() {
      contentObject.disarmPointer()
    }
    UpdatePanel {
      id: contentObject
      anchors.fill: parent
      status: parent.status
      checking: parent.checking
      cursorIndex: parent.cursorIndex
      keyboardCursor: parent.keyboardCursor
      onOpenUpdater: parent.openUpdater()
      onRefresh: parent.refresh()
      onPillHovered: function (index) {
        parent.pillHovered(index)
      }
    }
  }

  component TestPanelHost: Item {
    id: testHost
    // The update status shown.
    property var status: ({})
    // Whether a check is running.
    property bool checking: false
    // The pill the keyboard cursor is on.
    property int cursorIndex: 0
    // Whether the keyboard cursor shows.
    property bool keyboardCursor: false
    // Whether the test host counts as open.
    property bool open: false
    // Emitted to open the updater.
    signal openUpdater
    // Emitted to start a check.
    signal refresh
    implicitWidth: contentObject.implicitWidth
    implicitHeight: contentObject.implicitHeight
    // A fresh open starts with the cursor hidden; the first key reveals it.
    onOpenChanged: {
      contentObject.disarmPointer()
      testHost.cursorIndex = 0
      testHost.keyboardCursor = false
    }
    Aranea.KeyboardInputFrame {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) {
        contentObject.disarmPointer()
        root.switchPanel(direction)
      }
      onMoveRequested: function (dx, dy) {
        contentObject.disarmPointer()
        if (dy !== 0) {
          let next = UpdateLogic.moveCursor(testHost.cursorIndex, testHost.keyboardCursor, dy)
          testHost.cursorIndex = next.index
          testHost.keyboardCursor = next.keyboardCursor
        }
      }
      onTextKey: function (text) {
        contentObject.disarmPointer()
        if ((text === "r" || text === "R") && !testHost.checking)
          testHost.refresh()
      }
      onActivateRequested: {
        contentObject.disarmPointer()
        var intent = CursorLogic.pressIntent(true, testHost.keyboardCursor)
        if (intent === "reveal") {
          testHost.keyboardCursor = true
          return
        }
        if (testHost.cursorIndex === 0)
          testHost.openUpdater()
        else if (!testHost.checking)
          testHost.refresh()
      }
      PanelContent {
        id: contentObject
        anchors.fill: parent
        status: testHost.status
        checking: testHost.checking
        cursorIndex: testHost.cursorIndex
        keyboardCursor: testHost.keyboardCursor
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
    // Production and offscreen hosts implement the same reactive panel interface.
    readonly property var loadedPanel: item
    onLoaded: {
      loadedPanel.status = Qt.binding(function () {
        return root.status
      })
      loadedPanel.open = Qt.binding(function () {
        return root.panelOpen
      })
      loadedPanel.checking = Qt.binding(function () {
        return root.checking
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
