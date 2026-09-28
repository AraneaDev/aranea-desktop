// Shared title, hint, divider, and section chrome for keyboard panels.
import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: header
  property string title: ""
  property string hint: ""
  property string hintText: ""
  property string section: ""
  spacing: Style.space(8)

  RowLayout {
    Layout.fillWidth: true

    Text {
      text: header.title
      color: Color.popups.text
      font.pixelSize: Style.font.title
      font.bold: true
      font.family: Style.font.family
      Layout.fillWidth: true
    }

    Text {
      text: header.hint
      color: Color.popups.text
      opacity: 0.75
      font.pixelSize: Style.font.caption
      font.family: Style.font.family
    }
  }

  Text {
    text: header.hintText
    color: Color.popups.text
    opacity: 0.5
    font.pixelSize: Style.font.caption
    font.family: Style.font.family
    visible: text.length > 0
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 1
    color: Util.alpha(Color.popups.text, 0.16)
  }

  Text {
    text: header.section
    color: Color.popups.text
    opacity: 0.7
    font.pixelSize: Style.font.caption
    font.family: Style.font.family
  }
}
