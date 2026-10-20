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
  // Return or Enter (not Space), emitted just before its activateRequested.
  signal returnRequested
  // Requests deletion of the current selection (stock emits it for "x").
  signal deleteRequested
  // A key the catcher left unaccepted (Delete, for example) while not
  // blocked; a handler sets event.accepted to take it.
  signal unhandledKey(var event)
  // Item receiving keyboard focus.
  property alias focusTarget: keyCatcher
  // Content rendered inside the frame.
  default property alias content: body.data
  // Blocks all keys (forwarded to descendants) while true, e.g. an inline
  // editor has focus and must receive keys normally.
  property alias blocked: keyCatcher.blocked

  // Unaccepted keys propagate from the catcher to this item.
  Keys.onPressed: function (event) {
    if (!keyCatcher.blocked)
      frame.unhandledKey(event)
  }

  // Omarchy 4.5's catcher turns Delete into deleteRequested and accepts it,
  // which would hide Shift+Delete. The catcher forwards every key here
  // before its own handler, so Delete keeps reaching unhandledKey with its
  // modifiers and deleteRequested stays the stock "x"/"X" signal.
  Item {
    id: deleteGate
    Keys.onPressed: function (event) {
      event.accepted = false
      if (keyCatcher.blocked || event.key !== Qt.Key_Delete)
        return
      frame.unhandledKey(event)
      // Taken or not, the catcher must not reinterpret it.
      event.accepted = true
    }
  }

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    Keys.forwardTo: [deleteGate]
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
    onReturnRequested: frame.returnRequested()
    onActivateRequested: frame.activateRequested()
    onDeleteRequested: frame.deleteRequested()

    Item {
      id: body
      anchors.fill: parent
    }
  }
}
