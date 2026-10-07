// Top CPU and memory process rows for the health panel.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "MetricsLogic.js" as MetricsLogic
import "HealthSummaryLogic.js" as SummaryLogic

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
    spacing: Style.space(8)
    Text {
      visible: root.cpuProcesses.length === 0 && root.memoryProcesses.length === 0
      text: "No process data"
      color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
      // qmllint disable missing-property
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.body
      // qmllint enable missing-property
    }
    RowLayout {
      visible: root.cpuProcesses.length > 0 || root.memoryProcesses.length > 0
      Layout.fillWidth: true
      spacing: Style.space(16)
      ProcessCell {
        name: "CPU"
        value: "USE"
        dim: true
      }
      ProcessCell {
        name: "Memory"
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
          value: !processRow.cpuProcess ? "" : SummaryLogic.knownNumber(processRow.cpuProcess.percent) === null ? "—" : processRow.cpuProcess.percent + "%"
        }
        ProcessCell {
          name: processRow.memoryProcess ? processRow.memoryProcess.comm : ""
          value: !processRow.memoryProcess ? "" : SummaryLogic.knownNumber(processRow.memoryProcess.rss) === null ? "—" : MetricsLogic.humanBytes(processRow.memoryProcess.rss)
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
      color: cell.dim ? Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity) : Aranea.DesignTokens.foreground
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      Layout.fillWidth: true
      elide: Text.ElideRight
    }
    Text {
      text: cell.value
      color: cell.dim ? Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity) : Aranea.DesignTokens.foreground
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
    }
  }
}
