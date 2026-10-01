// Presentational clock and date block below the lock password field, sized
// and spaced to the compact 24-Sep lock design.
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

  spacing: Style.space(8)

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: clock.clockText
    color: clock.textColor
    font.family: clock.fontFamily
    font.pixelSize: Math.round(Style.font.heading * 1.94)
    font.bold: true
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    // Qt adds letter spacing after the last glyph too; shift by half of it.
    anchors.horizontalCenterOffset: font.letterSpacing / 2
    text: clock.dateText
    color: clock.placeholderColor
    font.family: clock.fontFamily
    font.pixelSize: Math.round(Style.font.bodySmall * 0.82)
    font.letterSpacing: 1
  }
}
