// Presentational tooltip surface for the bar's popup window.
import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: bubble

  // Plain-text tooltip content supplied by the bar root.
  property string text: ""
  // Font family shared with the active bar configuration.
  property string fontFamily: Style.font.menuFamily
  // Tooltip fill colour from the semantic palette.
  property color backgroundColor: Color.tooltip.background
  // Tooltip border colour from the semantic palette.
  property color borderColor: Color.tooltip.border
  // Tooltip text colour from the semantic palette.
  property color textColor: Color.tooltip.text

  implicitWidth: label.implicitWidth + Style.space(20)
  implicitHeight: label.implicitHeight + Style.space(14)
  color: bubble.backgroundColor
  borderSpec: Border.surfaceSpec("tooltip", "border", bubble.borderColor, 1)
  radius: Style.cornerRadius

  Text {
    id: label
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: bubble.text
    color: bubble.textColor
    font.family: bubble.fontFamily
    font.pixelSize: Style.font.body
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}
