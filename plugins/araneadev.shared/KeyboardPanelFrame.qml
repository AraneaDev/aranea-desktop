// Shared KeyboardPanel and key-catcher plumbing. Plugin hosts retain their
// own cursor and activation policy through the forwarded signals.
import QtQuick
import qs.Ui
import qs.Commons

KeyboardPanel {
  id: frame
  // Opt into neutral panel chrome while keeping the configured width and radius.
  property bool refined: false
  borderSpec: PanelChrome.popupBorder(refined)
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
  // Emitted for Return or Enter (not Space), just before activateRequested.
  signal returnRequested
  // Emitted when the focused item's deletion is requested ("x").
  signal deleteRequested
  // Emitted for a key the catcher left unaccepted (Delete, for example);
  // a handler sets event.accepted to take it.
  signal unhandledKey(var event)
  // Content rendered inside the keyboard frame.
  default property alias panelContent: input.content
  focusTarget: input.focusTarget
  // Blocks all keys while true (forwarded from the input frame's key catcher).
  property alias blocked: input.blocked

  KeyboardInputFrame {
    id: input
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
    onReturnRequested: frame.returnRequested()
    onActivateRequested: frame.activateRequested()
    onDeleteRequested: frame.deleteRequested()
    onUnhandledKey: function (event) {
      frame.unhandledKey(event)
    }
  }
}
