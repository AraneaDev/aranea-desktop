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

Item {
  id: root
  // The health service's Metrics.qml, or null.
  property var metrics: null
  // Whether the dropdown is open; the trace only follows the samples then.
  property bool active: false
  // CPU use in percent, 0 without a reading.
  property real cpu: metrics && metrics.cpu !== null && metrics.cpu !== undefined ? metrics.cpu : 0
  // Memory use in percent.
  property real memoryPercent: metrics && metrics.mem ? metrics.mem.memUsed * 100 / metrics.mem.memTotal : 0
  // Disk rows ({target, percent, avail}) from the metrics.
  property var diskRows: metrics && metrics.diskRows ? metrics.diskRows : []
  // The default route's interface, "offline" without one.
  property string networkLabel: metrics && metrics.iface ? metrics.iface : "offline"
  // Upload and download rates, "-" without a reading.
  property string networkRateText: metrics && metrics.rates ? "↑ " + MetricsLogic.formatRate(metrics.rates.up) + "   ↓ " + MetricsLogic.formatRate(metrics.rates.down) : "-"
  // Font family of every text here.
  property string fontFamily: Style.font.family
  // Colour of the values and labels.
  property color foreground: Aranea.DesignTokens.foreground
  // Colour of captions and secondary text.
  readonly property color muted: Util.alpha(root.foreground, 0.55)

  // Maps metric severity to the panel's semantic foreground colour.
  function levelColor(level: string): color {
    return level === "critical" ? Aranea.DesignTokens.urgent : (level === "attention" ? Aranea.DesignTokens.attention : root.foreground)
  }

  implicitHeight: content.implicitHeight

  // A section label in the Filament caption style.
  component Caption: Text {
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
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
    spacing: Style.space(10)

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
          text: Math.round(root.cpu) + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          Layout.fillWidth: true
        }
        Text {
          text: root.metrics && root.metrics.load ? "load " + root.metrics.load.map(function (v) {
            return v.toFixed(2)
          }).join(" ") : ""
          color: root.muted
          font.family: root.fontFamily
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
          text: root.metrics && root.metrics.mem ? MetricsLogic.humanBytes(root.metrics.mem.memUsed) + " / " + MetricsLogic.humanBytes(root.metrics.mem.memTotal) : Math.round(root.memoryPercent) + "%"
          color: root.levelColor(MetricsLogic.usageLevel(root.memoryPercent))
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
      Aranea.FilamentBar {
        objectName: "memBar"
        Layout.fillWidth: true
        value: HealthLogic.barFraction(root.memoryPercent)
      }
      Text {
        visible: !!(root.metrics && root.metrics.mem && root.metrics.mem.swapUsed > 0)
        text: root.metrics && root.metrics.mem ? "swap " + MetricsLogic.humanBytes(root.metrics.mem.swapUsed) + " / " + MetricsLogic.humanBytes(root.metrics.mem.swapTotal) : ""
        color: root.muted
        font.family: root.fontFamily
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
          spacing: Style.space(2)
          RowLayout {
            Layout.fillWidth: true
            Text {
              text: diskRow.modelData.target
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              Layout.fillWidth: true
              elide: Text.ElideMiddle
            }
            Text {
              text: diskRow.modelData.percent + "%"
              color: root.levelColor(MetricsLogic.usageLevel(diskRow.modelData.percent))
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              text: MetricsLogic.humanBytes(diskRow.modelData.avail) + " free"
              color: root.muted
              font.family: root.fontFamily
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
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
      }
      Text {
        text: root.networkRateText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
