// CPU, memory, disk and network presentation for the health panel. The CPU
// trace is the shared Aranea.LinkGraph (the network graph's mint to violet
// strand, here with a soft fill and no send line) over the last 60 one-
// second samples; memory and disk use are Aranea.FilamentBar strand bars,
// their values tinted by usage level. NET keeps its content, with the
// same caption label as the other sections.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "HealthLogic.js" as HealthLogic
import "MetricsLogic.js" as MetricsLogic
import "HealthSummaryLogic.js" as SummaryLogic

Item {
  id: root
  // The health service's Metrics.qml, or null.
  property var metrics: null
  // Whether the dropdown is open; the trace only follows the samples then.
  property bool active: false
  // CPU use in percent, null without a reading.
  property var cpu: SummaryLogic.resourceSummary(metrics).cpu
  // Memory use in percent.
  property var memoryPercent: summary.memory ? summary.memory.used * 100 / summary.memory.total : null
  // Availability-aware health decision or nullable compact resources.
  readonly property var summary: SummaryLogic.resourceSummary(metrics)
  // Disk rows ({target, percent, avail}) from the metrics.
  property var diskRows: metrics && metrics.diskRows ? metrics.diskRows : []
  // The default route's interface, an em dash without a reading.
  property string networkLabel: metrics && metrics.iface ? metrics.iface : "—"
  // Upload and download rates, an em dash without a reading.
  property string networkRateText: "↑ " + root.rateText(metrics && metrics.rates ? metrics.rates.up : null) + "   ↓ " + root.rateText(metrics && metrics.rates ? metrics.rates.down : null)
  // Font family of every text here.
  property string fontFamily: Aranea.Typography.uiFamily
  // Colour of the values and labels.
  property color foreground: Aranea.DesignTokens.foreground
  // Colour of captions and secondary text.
  readonly property color muted: Util.alpha(root.foreground, 0.55)

  // Maps metric severity to the panel's semantic foreground colour.
  function levelColor(level: string): color {
    return level === "critical" ? Aranea.DesignTokens.urgent : (level === "attention" ? Aranea.DesignTokens.attention : root.foreground)
  }

  // Formats known network rates and preserves unknown readings.
  function rateText(value): string {
    var rate = SummaryLogic.knownNumber(value)
    return rate === null ? "—" : MetricsLogic.formatRate(rate)
  }

  // Formats known byte counts and preserves unknown readings.
  function bytesText(value): string {
    var bytes = SummaryLogic.knownNumber(value)
    return bytes === null ? "—" : MetricsLogic.humanBytes(bytes)
  }

  implicitHeight: content.implicitHeight

  // A section label in the Filament caption style.
  component Caption: Text {
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0
  }

  // The hairline between sections.
  component Hairline: Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }

  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(16)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)
      RowLayout {
        Layout.fillWidth: true
        Caption {
          text: "CPU"
        }
        Text {
          objectName: "cpuValue"
          text: root.cpu === null ? "—" : Math.round(root.cpu) + "%"
          color: root.foreground
          font.family: Aranea.Typography.technicalFamily
          font.pixelSize: Style.font.body
          Layout.fillWidth: true
        }
        Text {
          text: "load " + (root.metrics && root.metrics.load ? root.metrics.load.map(function (v) {
              var value = SummaryLogic.knownNumber(v)
              return value === null ? "—" : value.toFixed(2)
            }).join(" ") : "—")
          color: root.muted
          font.family: Aranea.Typography.technicalFamily
          font.pixelSize: Style.font.caption
        }
      }
      Aranea.LinkGraph {
        objectName: "cpuTrace"
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(34)
        // Today's source and window: one sample a second, the last 60,
        // on a fixed 0..100 % scale.
        samples: root.active && root.metrics ? HealthLogic.cpuSamples(root.metrics.cpuHistory) : []
        slots: 60
        floor: 100
        secondary: false
        softFill: true
      }
    }

    Hairline {}

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)
      RowLayout {
        Layout.fillWidth: true
        Caption {
          text: "MEM"
          Layout.fillWidth: true
        }
        Text {
          objectName: "memValue"
          text: root.summary.memory ? MetricsLogic.humanBytes(root.summary.memory.used) + " / " + MetricsLogic.humanBytes(root.summary.memory.total) : "—"
          color: root.levelColor(MetricsLogic.usageLevel(root.memoryPercent))
          font.family: Aranea.Typography.technicalFamily
          font.pixelSize: Style.font.body
        }
      }
      Aranea.FilamentBar {
        objectName: "memBar"
        Layout.fillWidth: true
        value: HealthLogic.barFraction(root.memoryPercent)
      }
      Text {
        text: "swap " + root.bytesText(root.metrics && root.metrics.mem ? root.metrics.mem.swapUsed : null) + " / " + root.bytesText(root.metrics && root.metrics.mem ? root.metrics.mem.swapTotal : null)
        color: root.muted
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.caption
      }
    }

    Hairline {}

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)
      Caption {
        text: "DISK"
      }
      Repeater {
        model: root.diskRows
        delegate: ColumnLayout {
          id: diskRow
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.space(4)
          RowLayout {
            Layout.fillWidth: true
            Text {
              text: diskRow.modelData.target
              color: root.foreground
              font.family: Aranea.Typography.technicalFamily
              font.pixelSize: Style.font.body
              Layout.fillWidth: true
              elide: Text.ElideMiddle
            }
            Text {
              text: SummaryLogic.knownNumber(diskRow.modelData.percent) === null ? "—" : diskRow.modelData.percent + "%"
              color: root.levelColor(MetricsLogic.usageLevel(diskRow.modelData.percent))
              font.family: Aranea.Typography.technicalFamily
              font.pixelSize: Style.font.body
            }
            Text {
              text: root.bytesText(diskRow.modelData.avail) + " free"
              color: root.muted
              font.family: Aranea.Typography.technicalFamily
              font.pixelSize: Style.font.caption
            }
          }
          Aranea.FilamentBar {
            objectName: "diskBar"
            Layout.fillWidth: true
            value: HealthLogic.barFraction(diskRow.modelData.percent)
          }
        }
      }
    }

    Hairline {}

    RowLayout {
      Layout.fillWidth: true
      Caption {
        text: "NET"
      }
      Text {
        text: root.networkLabel
        color: root.muted
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
      }
      Text {
        text: root.networkRateText
        color: root.foreground
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
