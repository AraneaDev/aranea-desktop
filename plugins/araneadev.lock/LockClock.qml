// Presentational clock and date block below the lock password field.
// qmllint disable missing-property
import QtQuick
import qs.Commons

Column {
  id: clock

  // Current time formatted by the lock service.
  property string clockText: ""
  // Current date formatted by the lock service.
  property string dateText: ""
  // Font family shared by the lock surface.
  property string fontFamily: Style.font.family
  // Primary time colour.
  property color textColor: Color.lock.text
  // Secondary date colour.
  property color placeholderColor: Color.lock.placeholder

  spacing: Style.space(5)

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: clock.clockText
    color: clock.textColor
    font.family: clock.fontFamily
    font.pixelSize: Math.max(28, Math.round(Style.font.heading * 1.45))
    font.bold: true
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: clock.dateText
    color: clock.placeholderColor
    font.family: clock.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.letterSpacing: 1
  }
}
