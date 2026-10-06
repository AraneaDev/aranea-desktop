// Presentational branding block above the lock password field: a small,
// crisp spider, the product name and the lock subtitle, stacked with the
// compact spacing of the 24-Sep lock design.
// qmllint disable missing-property
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: branding

  // URL of the lock spider artwork (the generated vector brand mark).
  property string logoSource: ""
  // Font family shared by the lock surface.
  property string fontFamily: Aranea.Typography.uiFamily
  // Primary branding text colour.
  property color textColor: Color.lock.text
  // Secondary branding text colour.
  property color placeholderColor: Color.lock.placeholder
  // Edge length of the square spider box in logical pixels. The mark is
  // rasterized at exactly this size times the device pixel ratio, so it is
  // never upscaled.
  property int logoSize: Style.space(74)
  // Gap between the spider box and the product name.
  property int logoGap: Style.space(32)
  // Gap between the product name and the subtitle.
  property int subtitleGap: Style.space(11)

  implicitWidth: Math.max(logo.width, title.implicitWidth, subtitle.implicitWidth)
  implicitHeight: logo.height + logoGap + title.implicitHeight + subtitleGap + subtitle.implicitHeight
  height: implicitHeight

  Image {
    id: logo
    width: branding.logoSize
    height: width
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    source: branding.logoSource
    sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
  }

  Text {
    id: title
    anchors.top: logo.bottom
    anchors.topMargin: branding.logoGap
    anchors.horizontalCenter: parent.horizontalCenter
    // Qt adds letter spacing after the last glyph too; shift by half of it
    // so the visible text sits on the centre line.
    anchors.horizontalCenterOffset: font.letterSpacing / 2
    text: Aranea.BrandConfig.shortName
    color: branding.textColor
    font.family: branding.fontFamily
    font.pixelSize: Math.round(Style.font.heading * 1.125)
    font.letterSpacing: 5.5
    font.bold: true
  }

  Text {
    id: subtitle
    anchors.top: title.bottom
    anchors.topMargin: branding.subtitleGap
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: font.letterSpacing / 2
    text: Aranea.BrandConfig.lockSubtitle
    color: branding.placeholderColor
    font.family: branding.fontFamily
    font.pixelSize: Math.round(Style.font.bodySmall * 0.82)
    font.letterSpacing: 3.4
  }
}
