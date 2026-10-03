// Top CPU and memory process rows for the health panel.
// qmllint disable missing-property unqualified
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "MetricsLogic.js" as MetricsLogic

Item {
  id: root
  // Public contract member.
  property var cpuProcesses: []
  // Public contract member.
  property var memoryProcesses: []
  implicitHeight: content.implicitHeight
  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(2)
    Text {
      text: "TOP"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(16)
      ProcessCell {
        name: "CPU"
        value: "USE"
        dim: true
      }
      ProcessCell {
        name: "MEM"
        value: "RSS"
        dim: true
      }
    }
    Repeater {
      model: Math.max(root.cpuProcesses.length, root.memoryProcesses.length)
      delegate: RowLayout {
        required property int index
        Layout.fillWidth: true
        spacing: Style.space(16)
        ProcessCell {
          name: root.cpuProcesses[index] ? root.cpuProcesses[index].comm : ""
          value: root.cpuProcesses[index] ? root.cpuProcesses[index].percent + "%" : ""
        }
        ProcessCell {
          name: root.memoryProcesses[index] ? root.memoryProcesses[index].comm : ""
          value: root.memoryProcesses[index] ? MetricsLogic.humanBytes(root.memoryProcesses[index].rss) : ""
        }
      }
    }
  }

  // One half of a TOP row: process name and its right-aligned value.
  component ProcessCell: RowLayout {
    // Process name (or column heading).
    property string name: ""
    // Value (or unit heading), right-aligned.
    property string value: ""
    // Heading style.
    property bool dim: false
    // Equal halves: both cells prefer the same width and fill.
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    spacing: Style.space(8)
    Text {
      text: parent.name
      color: parent.dim ? Util.alpha(Aranea.DesignTokens.foreground, 0.55) : Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      Layout.fillWidth: true
      elide: Text.ElideRight
    }
    Text {
      text: parent.value
      color: parent.dim ? Util.alpha(Aranea.DesignTokens.foreground, 0.55) : Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
    }
  }
}
