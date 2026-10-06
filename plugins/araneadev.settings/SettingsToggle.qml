// Keyboard-capable Filament switch using owner-observed values.
import QtQuick
import "../araneadev.shared" as Aranea

Aranea.FilamentSwitch {
  activeFocusOnTab: enabled && visible
  hasCursor: activeFocus
  Accessible.role: Accessible.CheckBox
  Accessible.checked: checked
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      activate()
      event.accepted = true
    }
  }
}
