// Top CPU and memory process rows for the health panel.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "MetricsLogic.js" as MetricsLogic

Item {
  id: root
  // The busiest processes by CPU ({comm, percent}), busiest first.
  property var cpuProcesses: []
  // The largest processes by resident memory ({comm, rss} in bytes),
  // largest first.
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
        id: processRow
        required property int index
        // This row's CPU process, or undefined past the list's end.
        readonly property var cpuProcess: root.cpuProcesses[processRow.index]
        // This row's memory process, or undefined past the list's end.
        readonly property var memoryProcess: root.memoryProcesses[processRow.index]
        Layout.fillWidth: true
        spacing: Style.space(16)
        ProcessCell {
          name: processRow.cpuProcess ? processRow.cpuProcess.comm : ""
          value: processRow.cpuProcess ? processRow.cpuProcess.percent + "%" : ""
        }
        ProcessCell {
          name: processRow.memoryProcess ? processRow.memoryProcess.comm : ""
          value: processRow.memoryProcess ? MetricsLogic.humanBytes(processRow.memoryProcess.rss) : ""
        }
      }
    }
  }

  // One half of a TOP row: process name and its right-aligned value.
  component ProcessCell: RowLayout {
    id: cell
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
      text: cell.name
      color: cell.dim ? Util.alpha(Aranea.DesignTokens.foreground, 0.55) : Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      Layout.fillWidth: true
      elide: Text.ElideRight
    }
    Text {
      text: cell.value
      color: cell.dim ? Util.alpha(Aranea.DesignTokens.foreground, 0.55) : Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
    }
  }
}
