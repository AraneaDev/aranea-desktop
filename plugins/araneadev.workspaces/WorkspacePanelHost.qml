// Production KeyboardPanel host for the workspace overview.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Aranea.KeyboardPanelFrame {
  id: host
  // Normalized workspace rows supplied by the bar widget.
  property var workspaceStates: []
  // Keyboard-selected row index.
  property int cursorIndex: -1
  // Request focus for a workspace row.
  signal focusWorkspace(int id)
  open: owner ? owner.opened : false
  gap: Style.gapsOut
  contentWidth: fittedContentWidth(Style.space(380))
  contentHeight: fittedContentHeight(content.implicitHeight, Style.space(520))
  // Move the keyboard cursor through the workspace rows.
  function moveCursor(delta) {
    if (!workspaceStates.length)
      return
    cursorIndex = cursorIndex < 0 ? (delta > 0 ? 0 : workspaceStates.length - 1) : (cursorIndex + delta + workspaceStates.length) % workspaceStates.length
  }
  onCloseRequested: host.owner.close()
  onTabRequested: function (direction) {
    host.owner.switchPanel(direction)
  }
  onMoveRequested: function (dx, dy) {
    if (dy !== 0)
      host.moveCursor(dy)
  }
  onActivateRequested: if (host.cursorIndex >= 0)
    host.focusWorkspace(host.workspaceStates[host.cursorIndex].id)
  ColumnLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    WorkspacePanel {
      Layout.fillWidth: true
      workspaceStates: host.workspaceStates
      cursorIndex: host.cursorIndex
      // The one true cap: the card's own maximum (Style.space(520) or a
      // smaller screen, whichever binds) minus the padding and border the
      // card always reserves around the content, so a capped panel can
      // never exceed the space contentHolder actually gives it.
      maxContentHeight: Math.max(0, Math.min(Style.space(520), host.availableCardHeight) - host.verticalContentInset)
      onFocusWorkspace: host.focusWorkspace(id)
    }
  }
}
