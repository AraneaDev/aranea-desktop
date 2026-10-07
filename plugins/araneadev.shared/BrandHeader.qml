// Shared glyph, title, subtitle, and optional count header.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: header

  // First-party hierarchy; external hosts retain the legacy spacing.
  property bool refined: false
  // Primary heading text.
  property string title: ""
  // Secondary heading text.
  property string subtitle: ""
  // Optional trailing count or status text.
  property string counts: ""
  // Font family for all header text.
  property string fontFamily: Style.font.menuFamily
  // Main header text color.
  property color foreground: Color.menu.text
  // Accent color for the count text.
  property color accent: Color.menu.selectedText
  // Letter spacing applied to header text.
  property real letterSpacing: 0.20
  // Glyph image shown before the heading.
  property url glyphSource: RuntimePaths.glyphUrl
  // Logical glyph size.
  property int glyphSize: Style.space(22)
  // Heading font size.
  property int titleSize: Style.font.title
  // Subtitle font size.
  property int subtitleSize: Style.font.caption

  spacing: Style.space(10)

  Image {
    Layout.preferredWidth: header.glyphSize
    Layout.preferredHeight: header.glyphSize
    source: header.glyphSource
    sourceSize: Qt.size(header.glyphSize * 2, header.glyphSize * 2)
    fillMode: Image.PreserveAspectFit
    smooth: true
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.space(header.refined ? 4 : 2)

    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: header.title
      color: header.foreground
      font.family: header.fontFamily
      font.pixelSize: header.titleSize
      font.weight: Font.Medium
      font.letterSpacing: header.letterSpacing
      elide: Text.ElideRight
    }

    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: header.subtitle
      color: Util.alpha(header.foreground, header.refined ? DesignTokens.secondaryOpacity : 0.58)
      font.family: header.fontFamily
      font.pixelSize: header.subtitleSize
      font.weight: Font.Medium
      font.letterSpacing: header.letterSpacing
      elide: Text.ElideRight
    }
  }

  Text {
    visible: header.counts.length > 0
    textFormat: Text.PlainText
    text: header.counts
    color: header.accent
    opacity: 0.8
    font.family: header.fontFamily
    font.pixelSize: header.subtitleSize
    font.weight: Font.Medium
    font.letterSpacing: header.letterSpacing
  }
}
