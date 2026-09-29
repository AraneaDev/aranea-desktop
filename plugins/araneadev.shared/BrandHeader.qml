// Shared glyph, title, subtitle, and optional count header.
import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
  id: header

  property string title: ""
  property string subtitle: ""
  property string counts: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property real letterSpacing: 0.20
  property url glyphSource: RuntimePaths.glyphUrl
  property int glyphSize: Style.space(22)
  property int titleSize: Style.font.title
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
    spacing: Style.space(2)

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
      color: Util.alpha(header.foreground, 0.58)
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
