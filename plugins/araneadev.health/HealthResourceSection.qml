// CPU, memory, disk and network presentation for the health panel.
// qmllint disable missing-property unqualified
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "MetricsLogic.js" as MetricsLogic

Item {
  id: root
  // Public contract member.
  property var metrics: null
  // Public contract member.
  property bool active: false
  // Public contract member.
  property real cpu: metrics && metrics.cpu !== null && metrics.cpu !== undefined ? metrics.cpu : 0
  // Public contract member.
  property real memoryPercent: metrics && metrics.mem ? metrics.mem.memUsed * 100 / metrics.mem.memTotal : 0
  // Public contract member.
  property var diskRows: metrics && metrics.diskRows ? metrics.diskRows : []
  // Public contract member.
  property string networkLabel: metrics && metrics.iface ? metrics.iface : "offline"
  // Public contract member.
  property string networkRateText: metrics && metrics.rates ? "↑ " + MetricsLogic.formatRate(metrics.rates.up) + "   ↓ " + MetricsLogic.formatRate(metrics.rates.down) : "-"
  // Public contract member.
  property string fontFamily: Style.font.family
  // Public contract member.
  property color foreground: Color.popups.text

  // Maps metric severity to the panel's semantic foreground colour.
  function levelColor(level: string): color {
    return level === "critical" ? Color.urgent : (level === "attention" ? Aranea.DesignTokens.attention : root.foreground)
  }

  implicitHeight: content.implicitHeight

  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(10)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)
      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "CPU"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
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
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Canvas {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(28)
        property var values: root.metrics ? root.metrics.cpuHistory : []
        onValuesChanged: if (root.active)
          requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          // The chart floor spans the width even before 60 samples exist.
          ctx.globalAlpha = 0.25
          ctx.strokeStyle = root.foreground
          ctx.lineWidth = 1
          ctx.beginPath()
          ctx.moveTo(0, height - 0.5)
          ctx.lineTo(width, height - 0.5)
          ctx.stroke()
          ctx.globalAlpha = 1
          var v = values || []
          if (v.length < 2)
            return
          ctx.strokeStyle = Color.notifications.countdown
          ctx.lineWidth = 1.5
          ctx.beginPath()
          for (var i = 0; i < v.length; i++) {
            var x = (width - 1) * (i + 60 - v.length) / 59
            var y = height - 1 - (height - 2) * Math.min(100, v[i]) / 100
            if (i === 0)
              ctx.moveTo(x, y)
            else
              ctx.lineTo(x, y)
          }
          ctx.stroke()
        }
        onWidthChanged: requestPaint()
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)
      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "MEM"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          Layout.fillWidth: true
        }
        Text {
          text: root.metrics && root.metrics.mem ? MetricsLogic.humanBytes(root.metrics.mem.memUsed) + " / " + MetricsLogic.humanBytes(root.metrics.mem.memTotal) : Math.round(root.memoryPercent) + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(4)
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.08)
        Rectangle {
          width: parent.width * Math.max(0, Math.min(1, root.memoryPercent / 100))
          height: parent.height
          radius: height / 2
          color: root.levelColor(MetricsLogic.usageLevel(root.memoryPercent))
        }
      }
      Text {
        visible: !!(root.metrics && root.metrics.mem && root.metrics.mem.swapUsed > 0)
        text: root.metrics && root.metrics.mem ? "swap " + MetricsLogic.humanBytes(root.metrics.mem.swapUsed) + " / " + MetricsLogic.humanBytes(root.metrics.mem.swapTotal) : ""
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)
      Text {
        text: "DISK"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Repeater {
        model: root.diskRows
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.space(2)
          RowLayout {
            Layout.fillWidth: true
            Text {
              text: modelData.target
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              Layout.fillWidth: true
              elide: Text.ElideMiddle
            }
            Text {
              text: modelData.percent + "%"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              text: MetricsLogic.humanBytes(modelData.avail) + " free"
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(4)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.08)
            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, modelData.percent / 100))
              height: parent.height
              radius: height / 2
              color: root.levelColor(MetricsLogic.usageLevel(modelData.percent))
            }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Text {
        text: "NET"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        text: root.networkLabel
        color: Qt.darker(root.foreground, 1.3)
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
