// Production KeyboardPanel host for the update center.
import QtQuick
import qs.Commons
import qs.Ui

KeyboardPanel {
  id: host
  // Current update status rendered by the panel.
  property var status: ({})
  // Keyboard-selected action index.
  property int cursorIndex: 0
  // Request the updater action.
  signal openUpdater
  // Request a status refresh.
  signal refresh
  open: owner ? owner.opened : false
  gap: Style.gapsOut
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Style.space(380))
  contentHeight: fittedContentHeight(content.implicitHeight)
  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: host.owner.close()
    onTabRequested: function (direction) {
      host.owner.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      if (dy !== 0)
        host.cursorIndex = (host.cursorIndex + dy + 2) % 2
    }
    onTextKey: function (text) {
      if (text === "r" || text === "R")
        host.refresh()
    }
    onActivateRequested: host.cursorIndex === 0 ? host.openUpdater() : host.refresh()
    UpdatePanel {
      id: content
      anchors.fill: parent
      status: host.status
      cursorIndex: host.cursorIndex
      onOpenUpdater: host.openUpdater()
      onRefresh: host.refresh()
    }
  }
}
