// Shared KeyboardPanel and key-catcher plumbing. Plugin hosts retain their
// own cursor and activation policy through the forwarded signals.
import QtQuick
import qs.Ui

KeyboardPanel {
  id: frame
  // Emitted when the panel should close.
  signal closeRequested
  // Emitted when focus moves between tabs.
  signal tabRequested(int direction)
  // Emitted when navigation moves in a direction.
  signal moveRequested(int dx, int dy)
  // Emitted for text input.
  signal textKey(string text)
  // Emitted when the focused item is activated.
  signal activateRequested
  // Content rendered inside the keyboard frame.
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
