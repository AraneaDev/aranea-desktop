// Production KeyboardPanel host for the workspace overview.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "WorkspaceModel.js" as WorkspaceModel

Aranea.KeyboardPanelFrame {
  id: host
  refined: true
  // Normalized workspace rows supplied by the bar widget.
  property var workspaceStates: []
  // Key of the cursor's workspace (WorkspaceModel.workspaceKey, "" for
  // none); rows re-sort as workspaces come and go, so the cursor follows
  // the workspace, not a position. Only the keyboard places it; hover never
  // does.
  property string cursorKey: ""
  // True while the keyboard drives the cursor; any pointer use clears it.
  // The mint outline shows only then, and the first key after opening or
  // after pointer use only reveals it.
  property bool keyboardCursor: false
  // Row index of cursorKey in workspaceStates, drawn with the mint outline
  // only while the keyboard shows it (WorkspaceModel.outlineIndex).
  readonly property int cursorIndex: WorkspaceModel.outlineIndex(host.workspaceStates, host.cursorKey, host.keyboardCursor)
  // Row index of cursorKey whether or not it is shown, -1 when none.
  readonly property int cursorRow: WorkspaceModel.indexOfKey(host.workspaceStates, host.cursorKey)
  // A workspace that went away takes the cursor with it (after the
  // change settles, so cursorRow never re-evaluates inside its own
  // change signal).
  onCursorRowChanged: if (host.cursorRow < 0 && host.cursorKey)
    Qt.callLater(host.dropLostCursor)

  // Clears cursorKey when it no longer names a shown workspace.
  function dropLostCursor() {
    if (host.cursorRow < 0)
      host.cursorKey = ""
  }
  // Emitted to focus a workspace.
  signal focusWorkspace(int id)
  open: owner ? owner.opened : false
  gap: Style.gapsOut
  contentWidth: fittedContentWidth(Style.space(380))
  contentHeight: fittedContentHeight(content.implicitHeight, Style.space(520))
  // A fresh open starts with the cursor hidden; the first key reveals it.
  onOpenChanged: {
    panel.disarmPointer()
    host.cursorKey = ""
    host.keyboardCursor = false
  }
  onCloseRequested: host.owner.close()
  onTabRequested: function (direction) {
    panel.disarmPointer()
    host.owner.switchPanel(direction)
  }
  onMoveRequested: function (dx, dy) {
    panel.disarmPointer()
    if (dy !== 0) {
      var next = WorkspaceModel.cursorMove(host.workspaceStates, host.cursorKey, host.keyboardCursor, dy)
      host.cursorKey = next.key
      host.keyboardCursor = next.keyboard
    }
  }
  onActivateRequested: {
    panel.disarmPointer()
    var press = WorkspaceModel.cursorPress(host.workspaceStates, host.cursorKey, host.keyboardCursor)
    host.cursorKey = press.key
    host.keyboardCursor = press.keyboard
    if (press.row)
      host.focusWorkspace(press.row.id)
  }
  ColumnLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    WorkspacePanel {
      id: panel
      Layout.fillWidth: true
      workspaceStates: host.workspaceStates
      cursorIndex: host.cursorIndex
      // The one true cap: the card's own maximum (Style.space(520) or a
      // smaller screen, whichever binds) minus the padding and border the
      // card always reserves around the content, so a capped panel can
      // never exceed the space contentHolder actually gives it.
      maxContentHeight: Math.max(0, Math.min(Style.space(520), host.availableCardHeight) - host.verticalContentInset)
      onFocusWorkspace: function (id) {
        host.focusWorkspace(id)
      }
    }
  }
}
