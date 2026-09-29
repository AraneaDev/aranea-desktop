// CPU, memory, disk and network summary presentation for the health panel.
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: root
  property real cpu: 0
  property real memoryPercent: 0
  property var diskRows: []
  property string networkLabel: "offline"
  property string networkRateText: ""
  implicitHeight: content.implicitHeight
  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(6)
    RowLayout {
      Layout.fillWidth: true
      Text { text: "CPU"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
      Text { text: Math.round(root.cpu) + "%"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.fillWidth: true }
    }
    RowLayout {
      Layout.fillWidth: true
      Text { text: "MEM"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
      Text { text: Math.round(root.memoryPercent) + "%"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
    }
    ColumnLayout {
      Layout.fillWidth: true
      Text { text: "DISK"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
      Repeater {
        model: root.diskRows
        delegate: Text {
          required property var modelData
          text: modelData.target + "  " + modelData.percent + "%"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
    RowLayout {
      Layout.fillWidth: true
      Text { text: "NET"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
      Text { text: root.networkLabel; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
      Text { text: root.networkRateText; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.caption }
    }
  }
}
