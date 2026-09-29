// Presentational branding block above the lock password field.
// qmllint disable missing-property
import QtQuick
import qs.Commons

Column {
  id: branding

  // Cache-busted URL of the lock spider artwork.
  property string logoSource: ""
  // Font family shared by the lock surface.
  property string fontFamily: Style.font.family
  // Primary branding text colour.
  property color textColor: Color.lock.text
  // Secondary branding text colour.
  property color placeholderColor: Color.lock.placeholder

  spacing: Style.space(14)

  Image {
    width: Math.min(260, branding.width * 0.2)
    height: width
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: -2
    source: branding.logoSource
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: "ARANEA"
    color: branding.textColor
    font.family: branding.fontFamily
    font.pixelSize: Math.max(16, Math.round(Style.font.heading * 0.9))
    font.letterSpacing: 5
    font.bold: true
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: "SECURE SESSION"
    color: branding.placeholderColor
    font.family: branding.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.letterSpacing: 3
  }
}
