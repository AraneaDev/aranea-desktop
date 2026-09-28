// Shared KeyboardPanel and key-catcher plumbing. Plugin hosts retain their
// own cursor and activation policy through the forwarded signals.
import QtQuick
import qs.Ui

KeyboardPanel {
  id: frame
  signal closeRequested
  signal tabRequested(int direction)
  signal moveRequested(int dx, int dy)
  signal textKey(string text)
  signal activateRequested
  default property alias panelContent: body.data
  focusTarget: keyCatcher

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
