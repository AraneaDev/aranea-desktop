// Shared keyboard input frame for panel content and offscreen test hosts.
import QtQuick
import qs.Ui

Item {
  id: frame

  signal closeRequested
  signal tabRequested(int direction)
  signal moveRequested(int dx, int dy)
  signal textKey(string text)
  signal activateRequested
  property alias focusTarget: keyCatcher
  default property alias content: body.data

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: frame.closeRequested()
    onTabRequested: function (direction) {
      frame.tabRequested(direction)
    }
    onMoveRequested: function (dx, dy) {
      frame.moveRequested(dx, dy)
    }
    onTextKey: function (text) {
      frame.textKey(text)
    }
    onActivateRequested: frame.activateRequested()

    Item {
      id: body
      anchors.fill: parent
    }
  }
}
