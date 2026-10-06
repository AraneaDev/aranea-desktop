// Header and footer presentation for the emoji picker.
// qmllint disable missing-property unqualified
import QtQuick
import "../araneadev.shared" as Aranea
import qs.Commons

Item {
  id: root
  // Public contract member.
  property string filterText: ""
  // Public contract member.
  property string selectedName: ""
  // Public contract member.
  property string hintText: ""
  // Public contract member.
  property bool showFilter: true
  // Public contract member.
  property bool cursorActive: false
  // Public contract member.
  property bool recentVisible: false
  // Public contract member.
  property string fontFamily: Aranea.Typography.uiFamily
  // Public contract member.
  property color foreground: Color.menu.text
  // Public contract member.
  signal filterChanged(string value)
  // Public contract member.
  signal dismissRequested
  implicitHeight: content.implicitHeight
  Column {
    id: content
    anchors.fill: parent
    spacing: Style.space(8)
    TextInput {
      visible: root.showFilter
      width: parent.width
      text: root.filterText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      onTextChanged: root.filterChanged(text)
    }
    Text {
      width: parent.width
      text: root.selectedName
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Text {
      visible: root.hintText.length > 0
      width: parent.width
      text: root.hintText
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
