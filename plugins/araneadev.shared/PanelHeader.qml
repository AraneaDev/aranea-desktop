// Shared title, hint, divider, and section chrome for keyboard panels.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: header
  // Main header title.
  property string title: ""
  // Short right-aligned hint.
  property string hint: ""
  // Secondary explanatory text.
  property string hintText: ""
  // Optional section label.
  property string section: ""
  spacing: Style.space(8)

  RowLayout {
    Layout.fillWidth: true

    Text {
      text: header.title
      color: DesignTokens.foreground
      font.pixelSize: Style.font.title
      font.bold: true
      font.family: Style.font.family
      Layout.fillWidth: true
    }

    Text {
      text: header.hint
      color: DesignTokens.foreground
      opacity: 0.75
      font.pixelSize: Style.font.caption
      font.family: Style.font.family
    }
  }

  Text {
    text: header.hintText
    color: DesignTokens.foreground
    opacity: 0.5
    font.pixelSize: Style.font.caption
    font.family: Style.font.family
    visible: text.length > 0
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 1
    color: Util.alpha(DesignTokens.foreground, 0.16)
  }

  Text {
    text: header.section
    color: DesignTokens.foreground
    opacity: 0.7
    font.pixelSize: Style.font.caption
    font.family: Style.font.family
  }
}
