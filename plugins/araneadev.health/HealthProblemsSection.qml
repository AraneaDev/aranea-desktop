// Problem list presentation for the health panel.
// qmllint disable missing-property unqualified
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: root
  property var problems: []
  property int cursor: -1
  property color statusColor: Color.urgent
  property color amber: Color.notifications.countdown
  signal problemActivated(var problem)
  implicitHeight: content.implicitHeight

  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(4)
    RowLayout {
      Layout.fillWidth: true
      Rectangle { Layout.preferredWidth: Style.space(3); Layout.preferredHeight: Style.font.body + Style.space(2); radius: width / 2; color: root.statusColor }
      Text { text: "Problems"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; Layout.fillWidth: true }
      Text { text: String(root.problems.length); color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
    }
    Repeater {
      model: root.problems
      delegate: Rectangle {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        implicitHeight: Style.space(32)
        radius: Style.space(6)
        color: root.cursor === index ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          Text { text: modelData.glyph; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
          Text { text: modelData.summary; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.fillWidth: true; elide: Text.ElideRight }
          Text { text: modelData.urgency === 2 ? "critical" : "attention"; color: modelData.urgency === 2 ? Color.urgent : root.amber; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
        MouseArea { anchors.fill: parent; onClicked: root.problemActivated(modelData) }
      }
    }
  }
}
