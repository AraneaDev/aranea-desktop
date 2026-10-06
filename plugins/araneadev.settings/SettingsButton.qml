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
  // Pointer press feedback is presentation only; inherited guards own activation.
  property bool pointerPressed: false
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
  labelVisible: false
  labelColor: Aranea.DesignTokens.foreground
  labelFontFamily: variant === 'segment' ? Aranea.Typography.technicalFamily : Aranea.Typography.uiFamily
  opacity: enabled ? 1 : 0.55
  onEnabledChanged: if (!enabled)
    pointerPressed = false
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
    color: Util.alpha(Color.foreground, button.pointerPressed ? 0.14 : button.variant === 'secondary' ? 0.065 : 0)
    Behavior on color {
      enabled: Aranea.DesignTokens.motionEnabled
      ColorAnimation {
        duration: 90
      }
    }
  }
  Connections {
    target: button
    function onPressed() {
      button.pointerPressed = true
    }
    function onPressCanceled() {
      button.pointerPressed = false
    }
    function onClicked() {
      button.pointerPressed = false
    }
  }
  Text {
    id: labelMeasure
    objectName: 'settingsActionLabel'
    visible: button.variant !== 'navigation' && !!button.text
    anchors.centerIn: parent
    width: Math.max(0, Math.min(implicitWidth, button.width - Style.space(8)))
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
    color: button.labelColor
    text: button.text
    font.family: button.labelFontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 0
  }
}
