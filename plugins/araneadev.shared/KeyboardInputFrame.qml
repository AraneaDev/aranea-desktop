// Shared keyboard input frame for panel content and offscreen test hosts.
import QtQuick
import qs.Ui

Item {
  id: frame

  // Requests that the input frame close.
  signal closeRequested
  // Requests tab navigation by direction.
  signal tabRequested(int direction)
  // Requests cursor movement by x/y delta.
  signal moveRequested(int dx, int dy)
  // Emits printable text input.
  signal textKey(string text)
  // Requests activation of the current value.
  signal activateRequested
  // Requests deletion of the current selection (stock emits it for "x").
  signal deleteRequested
  // Item receiving keyboard focus.
  property alias focusTarget: keyCatcher
  // Content rendered inside the frame.
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
    onDeleteRequested: frame.deleteRequested()

    Item {
      id: body
      anchors.fill: parent
    }
  }
}
