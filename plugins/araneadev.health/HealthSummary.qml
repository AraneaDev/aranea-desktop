// Health decision and compact resources, arranged independently by the host.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "HealthSummaryLogic.js" as SummaryLogic
import "MetricsLogic.js" as MetricsLogic

Item {
  id: root
  // Whether a health service with metrics is published.
  property bool available: false
  // Existing health severity from the service.
  property string status: "healthy"
  // All actionable problems in service order.
  property var problems: []
  // The service metrics, or null while unavailable.
  property var metrics: null
  // Whether to render the health decision and severity.
  property bool showHealth: true
  // Whether to render the three compact resource values.
  property bool showResources: true
  // Availability-aware health decision or nullable compact resources.
  readonly property var summary: SummaryLogic.summaryFor(available, status, problems)
  // Known CPU/memory/fullest-disk values, with null for missing readings.
  readonly property var resourceValues: SummaryLogic.resourceSummary(available ? metrics : null)
  // Semantic severity color; the label also conveys the state.
  readonly property color toneColor: summary.tone === "critical" ? Aranea.DesignTokens.urgent : summary.tone === "attention" ? Aranea.DesignTokens.attention : summary.tone === "healthy" ? Aranea.DesignTokens.ceremony : Util.alpha(Aranea.DesignTokens.foreground, 0.55)
  implicitHeight: content.implicitHeight

  ColumnLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(16)
    ColumnLayout {
      visible: root.showHealth
      Layout.fillWidth: true
      spacing: Style.space(4)
      Text {
        objectName: "healthSummaryLabel"
        Layout.fillWidth: true
        text: root.summary.label
        wrapMode: Text.Wrap
        color: root.toneColor
        // qmllint disable missing-property
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.subtitle
        // qmllint enable missing-property
        font.bold: true
      }
      Text {
        objectName: "healthSeverity"
        visible: root.summary.tone === "critical" || root.summary.tone === "attention"
        text: root.summary.tone
        color: root.toneColor
        // qmllint disable missing-property
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.caption
        // qmllint enable missing-property
      }
    }
    ColumnLayout {
      visible: root.showResources
      Layout.fillWidth: true
      spacing: Style.space(8)
      ResourceValue {
        label: "CPU"
        value: root.resourceValues.cpu === null ? "—" : Math.round(root.resourceValues.cpu) + "%"
      }
      ResourceValue {
        label: "Memory"
        value: root.resourceValues.memory === null ? "—" : MetricsLogic.humanBytes(root.resourceValues.memory.used) + " / " + MetricsLogic.humanBytes(root.resourceValues.memory.total)
      }
      ResourceValue {
        label: "Disk"
        value: root.resourceValues.disk === null ? "—" : root.resourceValues.disk.target + " · " + root.resourceValues.disk.percent + "%"
      }
    }
  }
  component ResourceValue: ColumnLayout {
    property string label: ""
    property string value: "—"
    Layout.fillWidth: true
    spacing: Style.space(4)
    Text {
      text: parent.label
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      // qmllint disable missing-property
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      // qmllint enable missing-property
    }
    Text {
      text: parent.value
      Layout.fillWidth: true
      elide: Text.ElideMiddle
      color: Aranea.DesignTokens.foreground
      // qmllint disable missing-property
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.subtitle
      // qmllint enable missing-property
      font.bold: true
    }
  }
}
