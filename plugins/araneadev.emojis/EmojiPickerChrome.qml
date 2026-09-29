// Header and footer presentation for the emoji picker.
import QtQuick
import qs.Commons

Item {
  id: root
  property string filterText: ""
  property string selectedName: ""
  property string hintText: ""
  property bool cursorActive: false
  property bool recentVisible: false
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  signal filterChanged(string value)
  signal dismissRequested()
  implicitHeight: content.implicitHeight
  Column {
    id: content
    anchors.fill: parent
    spacing: Style.space(8)
    TextInput { width: parent.width; text: root.filterText; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; onTextChanged: root.filterChanged(text) }
    Text { width: parent.width; text: root.selectedName; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
    Text { width: parent.width; text: root.hintText; color: root.foreground; opacity: 0.6; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
  }
}
