// Keyboard-capable Filament action with disabled activation guards.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Aranea.FilamentPill {
  id: button
  // Presentation only: primary, secondary, navigation, segment or quiet.
  property string variant: 'secondary'
  // Guard keyboard and programmatic activation while disabled.
  function activate() {
    if (enabled)
      clicked()
  }
  activeFocusOnTab: enabled && visible
  hasCursor: activeFocus
  implicitHeight: Style.space(28)
  implicitWidth: labelMeasure.implicitWidth + Style.space(16)
  selected: variant === 'primary'
  borderVisible: false
  underlineVisible: false
  labelVisible: variant !== 'navigation'
  labelColor: Aranea.DesignTokens.foreground
  labelFontFamily: Style.font.menuFamily
  opacity: enabled ? 1 : 0.45
  Accessible.role: Accessible.Button
  Accessible.name: text
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      activate()
      event.accepted = true
    }
  }
  Rectangle {
    anchors.fill: parent
    z: -1
    radius: Style.space(3)
    color: Util.alpha(Color.foreground, 0.04)
    visible: button.variant === 'secondary'
  }
  Text {
    id: labelMeasure
    visible: false
    text: button.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 0.6
  }
}
