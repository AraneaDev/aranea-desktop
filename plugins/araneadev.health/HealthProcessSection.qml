// Top CPU and memory process rows for the health panel.
// qmllint disable missing-property unqualified
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: root
  property var cpuProcesses: []
  property var memoryProcesses: []
  implicitHeight: content.implicitHeight
  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(2)
    Text { text: "TOP"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
    Repeater {
      model: Math.max(root.cpuProcesses.length, root.memoryProcesses.length)
      delegate: RowLayout {
        required property int index
        Layout.fillWidth: true
        Text { text: root.cpuProcesses[index] ? root.cpuProcesses[index].comm : ""; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(110); elide: Text.ElideRight }
        Text { text: root.cpuProcesses[index] ? root.cpuProcesses[index].percent + "%" : ""; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(50); horizontalAlignment: Text.AlignRight }
        Item { Layout.preferredWidth: Style.space(16) }
        Text { text: root.memoryProcesses[index] ? root.memoryProcesses[index].comm : ""; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.caption; Layout.fillWidth: true; elide: Text.ElideRight }
      }
    }
  }
}
