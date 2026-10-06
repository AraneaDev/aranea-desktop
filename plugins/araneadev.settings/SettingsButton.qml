// Keyboard-capable Filament action with disabled activation guards.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Aranea.FilamentPill {
  id: button
  // Guard keyboard and programmatic activation while disabled.
  function activate() {
    if (enabled)
      clicked()
  }
  activeFocusOnTab: enabled && visible
  hasCursor: activeFocus
  implicitHeight: Style.space(32)
  implicitWidth: Math.max(Style.space(92), labelMeasure.implicitWidth + Style.space(24))
  opacity: enabled ? 1 : 0.45
  Accessible.role: Accessible.Button
  Accessible.name: text
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      if (enabled)
        clicked()
      event.accepted = true
    }
  }
  Text {
    id: labelMeasure
    visible: false
    text: button.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }
}
