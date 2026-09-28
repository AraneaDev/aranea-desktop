// Workspace bar widget with a native overview panel and direct workspace targets.
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "WorkspaceModel.js" as WorkspaceModel

Item {
  id: root
  // Bar host injected by Omarchy.
  property var bar: null
  // Registry identifier for IPC and layout lookup.
  property string moduleName: "araneadev.workspaces"
  // Per-instance shell settings.
  property var settings: ({})
  // Test-only workspace rows for offscreen QML tests.
  property var testWorkspaces: null
  // Test-only focused workspace override.
  property var testFocusedWorkspace: null
  // Whether the overview panel is open.
  property bool panelOpen: false
  // Open state exposed to the panel host.
  readonly property bool opened: panelOpen
  // Read live workspace rows without indexing unstable toplevel objects.
  function liveWorkspaceRows() {
    var values = Hyprland.workspaces ? Hyprland.workspaces.values : []
    var rows = []
    for (var index = 0; index < values.length; index++) {
      var workspace = values[index]
      var toplevels = workspace.toplevels ? workspace.toplevels.values : []
      var windows = Number(toplevels.length || 0) > 0 ? Number(toplevels.length) : workspace.windows
      rows.push({
        id: workspace.id,
        name: workspace.name,
        windows: windows,
        urgent: workspace.urgent || workspace.hasUrgentWindow,
        special: workspace.special
      })
    }
    return rows
  }
  // Raw workspace rows before standard workspace synthesis.
  readonly property var rawWorkspaces: testWorkspaces !== null ? testWorkspaces : liveWorkspaceRows()
  // Workspace rows including standard empty workspaces.
  readonly property var workspaceRows: testWorkspaces !== null ? rawWorkspaces : WorkspaceModel.ensureStandardWorkspaces(rawWorkspaces)
  // Live focused workspace object.
  readonly property var focusedWorkspaceObject: testFocusedWorkspace !== null ? null : Hyprland.focusedWorkspace
  // Numeric focused workspace id.
  readonly property int activeWorkspaceId: testFocusedWorkspace !== null ? Number(testFocusedWorkspace) : (focusedWorkspaceObject ? Number(focusedWorkspaceObject.id) : 0)
  // Normalized workspace state rows.
  readonly property var workspaceStates: WorkspaceModel.normalizeWorkspaces(workspaceRows, activeWorkspaceId, "")
  // Rows shown in the overview panel.
  readonly property var visibleStates: WorkspaceModel.visibleWorkspaces(workspaceStates)
  // Standard workspace indicators shown in the bar.
  readonly property var indicatorDots: WorkspaceModel.indicatorDots(workspaceStates)
  // Width used by the shell's open-panel indicator.
  readonly property real openPanelIndicatorWidth: button.implicitWidth

  QtObject {
    id: panelCoordinator
    readonly property bool opened: root.panelOpen
    function close() {
      root.close()
    }
    function closeForPopoutSwitch() {
      root.close()
    }
    function switchPanel(direction) {
      return root.switchPanel(direction)
    }
  }

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

  implicitWidth: button.implicitWidth + indicators.implicitWidth
  implicitHeight: Math.max(button.implicitHeight, indicators.implicitHeight)
  // Open the overview panel.
  function open() {
    panelOpen = true
  }
  // Close the overview panel.
  function close() {
    panelOpen = false
  }
  // Toggle the overview panel.
  function toggle() {
    panelOpen = !panelOpen
  }
  // Switch to the adjacent panel in the bar.
  function switchPanel(direction) {
    return bar && typeof bar.switchPanelFrom === "function" ? bar.switchPanelFrom(root, direction) : false
  }
  // Focus a workspace through Hyprland.
  function focusWorkspace(id) {
    var target = Number(id)
    if (!Number.isFinite(target) || !bar)
      return
    bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + target + "\" })"))
  }
  // Focus a workspace and close the panel.
  function focusPanelWorkspace(id) {
    focusWorkspace(id)
    close()
  }
  // Cycle through visible normal workspaces.
  function cycle(direction) {
    var target = WorkspaceModel.cycleTarget(workspaceStates, activeWorkspaceId, direction)
    if (target !== null)
      focusWorkspace(target)
  }
  // Load the production panel after the bar host is available.
  function loadLivePanel() {
    if (root.testWorkspaces === null && root.bar && panelLoader.item === null)
      panelLoader.setSource(Qt.resolvedUrl("WorkspacePanelHost.qml"), {
        anchorItem: button,
        owner: panelCoordinator,
        bar: root.bar
      })
  }
  onBarChanged: loadLivePanel()
  Component.onCompleted: loadLivePanel()

  WidgetButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    bar: root.bar
    text: "workspace"
    labelVisible: false
    keepSpace: true
    fixedWidth: Style.space(30)
    fixedHeight: root.bar ? root.bar.barSize : Style.space(32)
    tooltipText: "Workspace overview"
    active: root.panelOpen
    horizontalMargin: 7
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.LeftButton)
        root.toggle()
      else if (mouseButton === Qt.MiddleButton)
        root.focusWorkspace(root.activeWorkspaceId)
    }
    onWheelMoved: function (delta) {
      root.cycle(delta > 0 ? -1 : 1)
    }
    Text {
      anchors.centerIn: parent
      text: "☷"
      color: root.bar ? root.bar.foreground : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      enabled: false
    }
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(18)
      height: Style.space(2)
      radius: height / 2
      color: root.bar ? root.bar.urgent : Color.accent
      visible: root.panelOpen
    }
  }

  Item {
    id: indicators
    anchors.left: button.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    implicitWidth: Style.space(64)
    implicitHeight: root.bar ? root.bar.barSize : Style.space(32)

    Row {
      z: 1
      anchors.left: parent.left
      anchors.leftMargin: 0
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)
      Repeater {
        model: root.indicatorDots
        delegate: WidgetButton {
          required property var modelData
          bar: root.bar
          text: String(modelData.id)
          labelVisible: true
          keepSpace: true
          horizontalMargin: 0
          verticalPadding: 0
          fixedWidth: Style.space(12)
          fixedHeight: root.bar ? root.bar.barSize : Style.space(32)
          active: modelData.urgent || modelData.active
          opacity: active ? 1 : 0.55
          onPressed: function (mouseButton) {
            if (mouseButton === Qt.LeftButton)
              root.focusWorkspace(modelData.id)
          }
        }
      }
    }
  }

  component PanelContent: Item {
    property var workspaceStates: []
    property int cursorIndex: -1
    signal focusWorkspace(int id)
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    ColumnLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      WorkspacePanel {
        Layout.fillWidth: true
        workspaceStates: parent.parent.workspaceStates
        cursorIndex: parent.parent.cursorIndex
        onFocusWorkspace: parent.parent.focusWorkspace(id)
      }
    }
  }

  component TestPanelHost: Item {
    id: testHost
    property var workspaceStates: []
    property int cursorIndex: -1
    property bool open: false
    signal focusWorkspace(int id)
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    function moveCursor(delta) {
      if (!workspaceStates.length)
        return
      cursorIndex = cursorIndex < 0 ? (delta > 0 ? 0 : workspaceStates.length - 1) : (cursorIndex + delta + workspaceStates.length) % workspaceStates.length
    }
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) {
        root.switchPanel(direction)
      }
      onMoveRequested: function (dx, dy) {
        if (dy !== 0)
          testHost.moveCursor(dy)
      }
      onActivateRequested: if (testHost.cursorIndex >= 0)
        testHost.focusWorkspace(testHost.workspaceStates[testHost.cursorIndex].id)
      PanelContent {
        id: content
        anchors.fill: parent
        workspaceStates: testHost.workspaceStates
        cursorIndex: testHost.cursorIndex
        onFocusWorkspace: testHost.focusWorkspace(id)
      }
    }
  }

  Component {
    id: testPanelHost
    TestPanelHost {}
  }
  Loader {
    id: panelLoader
    sourceComponent: root.testWorkspaces !== null ? testPanelHost : null
    onLoaded: {
      item.workspaceStates = Qt.binding(function () {
        return root.visibleStates
      })
      item.open = Qt.binding(function () {
        return root.panelOpen
      })
    }
  }
  Connections {
    target: panelLoader.item
    function onFocusWorkspace(id) {
      root.focusPanelWorkspace(id)
    }
  }
}
