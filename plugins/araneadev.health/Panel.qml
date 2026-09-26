// Health bar icon + dropdown: open problems (also in the notification
// center) and live metrics. State lives in the health service (Service.qml),
// read through HealthBridge.js because the Aranea bar gives widgets a
// service-less facade.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "HealthBridge.js" as HealthBridge
import "MetricsLogic.js" as MetricsLogic

Panel {
  id: root
  moduleName: "araneadev.health"
  manageIpc: false

  property var service: HealthBridge.current()
  Timer {
    interval: 1000; repeat: true; running: true
    onTriggered: {
      var next = HealthBridge.current()
      if (next !== root.service) root.service = next
    }
  }

  readonly property bool available: !!(service && service.metrics)
  readonly property string status: available ? service.status : "healthy"
  readonly property var problems: available ? service.problems : []
  readonly property var m: available ? service.metrics : null
  readonly property color amber: "#ffbd2e"
  readonly property color statusColor: status === "critical" ? Color.urgent
    : (status === "attention" ? amber : Color.notifications.countdown)
  property int cursor: -1

  function levelColor(level: string): color {
    return level === "critical" ? Color.urgent : (level === "attention" ? root.amber : Color.popups.text)
  }

  function runRow(row): void {
    if (row && row.execArgv && row.execArgv.length) Util.execArgv(row.execArgv)
  }

  onOpenedChanged: {
    if (service && service.metrics) service.metrics.topActive = opened
    if (opened && service) {
      service.metrics.refreshSlow()
      service.monitor.checkDisk()
      root.cursor = -1
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰗶"
    foreground: root.available ? root.statusColor : root.barForeground
    dimmed: !root.available
    tooltipText: !root.available ? "Health unavailable"
      : (root.problems.length === 0 ? "Healthy"
        : root.problems.length + (root.problems.length === 1 ? " problem" : " problems")
          + (root.problems.filter(function(p) { return p.urgency === 2 }).length > 0
             ? " · " + root.problems.filter(function(p) { return p.urgency === 2 }).length + " critical" : ""))
    onPressed: function(b) {
      if (!root.available) return
      if (b === Qt.RightButton) Util.execArgv(["xdg-terminal-exec", "btop"])
      else root.toggle()
    }
  }

  component Rail: Rectangle {
    width: Style.space(3); height: Style.font.body + Style.space(2); radius: width / 2
  }

  component Label: Text {
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  component UsageBar: Item {
    property real fraction: 0
    property string level: "normal"
    property color base: Color.popups.text
    implicitHeight: Style.space(4)
    Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.08) }
    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, parent.fraction)); height: parent.height; radius: height / 2
      color: parent.level === "normal" ? parent.base : root.levelColor(parent.level)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.available
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.problems.length === 0 || dy === 0) return
        root.cursor = root.cursor < 0 ? 0 : (root.cursor + dy + root.problems.length) % root.problems.length
      }
      onActivateRequested: if (root.cursor >= 0) root.runRow(root.problems[root.cursor])

      ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // Header
        RowLayout {
          Layout.fillWidth: true
          Label { text: root.m ? root.m.hostname : ""; font.bold: true; font.pixelSize: Style.font.title; Layout.fillWidth: true }
          Label { text: root.m ? root.m.uptime : ""; color: Qt.darker(Color.popups.text, 1.4) }
        }

        // Problems
        RowLayout {
          visible: root.problems.length === 0
          spacing: Style.space(8)
          Image {
            Layout.preferredWidth: Style.space(16); Layout.preferredHeight: Style.space(16)
            source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/branding/marks/aranea-glyph.svg"
            sourceSize: Qt.size(32, 32)
          }
          Label { text: "All systems healthy"; color: Color.notifications.countdown }
        }
        ColumnLayout {
          visible: root.problems.length > 0
          Layout.fillWidth: true
          spacing: Style.space(4)
          RowLayout {
            Layout.fillWidth: true
            Rail { color: root.statusColor }
            Label { text: "Problems"; font.bold: true; Layout.fillWidth: true }
            Label { text: String(root.problems.length) }
          }
          Repeater {
            model: root.problems
            delegate: Rectangle {
              required property var modelData
              required property int index
              Layout.fillWidth: true
              implicitHeight: problemRow.implicitHeight + Style.space(8)
              radius: Style.space(6)
              color: root.cursor === index || rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
              RowLayout {
                id: problemRow
                anchors.fill: parent
                anchors.leftMargin: Style.space(8); anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)
                Label { text: modelData.glyph }
                Label { text: modelData.summary; elide: Text.ElideRight; Layout.fillWidth: true }
                Label {
                  text: modelData.muted ? "muted (bell)" : (modelData.urgency === 2 ? "critical" : "attention")
                  color: modelData.muted ? Qt.darker(Color.popups.text, 1.4) : (modelData.urgency === 2 ? Color.urgent : root.amber)
                  font.pixelSize: Style.font.caption
                }
              }
              MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runRow(modelData) }
            }
          }
        }

        // CPU
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(4)
          RowLayout {
            Layout.fillWidth: true
            Rail { color: Color.notifications.countdown }
            Label { text: "CPU"; font.bold: true }
            Label { text: root.m && root.m.cpu !== null ? root.m.cpu + "%" : "—"; Layout.fillWidth: true }
            Label {
              text: root.m && root.m.load ? "load " + root.m.load.map(function(v) { return v.toFixed(2) }).join(" ") : ""
              color: Qt.darker(Color.popups.text, 1.3)
            }
          }
          Canvas {
            id: spark
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(28)
            property var values: root.m ? root.m.cpuHistory : []
            onValuesChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var v = values || []
              if (v.length < 2) return
              ctx.strokeStyle = Color.notifications.countdown
              ctx.lineWidth = 1.5
              ctx.beginPath()
              for (var i = 0; i < v.length; i++) {
                var x = (width - 1) * (i + 60 - v.length) / 59
                var y = height - 1 - (height - 2) * Math.min(100, v[i]) / 100
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
              }
              ctx.stroke()
            }
          }
        }

        // Memory
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(4)
          readonly property real pct: root.m && root.m.mem ? root.m.mem.memUsed * 100 / root.m.mem.memTotal : 0
          RowLayout {
            Layout.fillWidth: true
            Rail { color: "#7a5cff" }
            Label { text: "MEM"; font.bold: true; Layout.fillWidth: true }
            Label { text: root.m && root.m.mem ? MetricsLogic.humanBytes(root.m.mem.memUsed) + " / " + MetricsLogic.humanBytes(root.m.mem.memTotal) : "—" }
          }
          UsageBar { Layout.fillWidth: true; fraction: parent.pct / 100; level: MetricsLogic.usageLevel(parent.pct); base: "#7a5cff" }
          Label {
            visible: !!(root.m && root.m.mem && root.m.mem.swapUsed > 0)
            text: root.m && root.m.mem ? "swap " + MetricsLogic.humanBytes(root.m.mem.swapUsed) + " / " + MetricsLogic.humanBytes(root.m.mem.swapTotal) : ""
            color: Qt.darker(Color.popups.text, 1.3)
            font.pixelSize: Style.font.caption
          }
        }

        // Disk
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(4)
          RowLayout {
            Layout.fillWidth: true
            Rail { color: "#d6a483" }
            Label { text: "DISK"; font.bold: true }
          }
          Repeater {
            model: root.m ? root.m.diskRows : []
            delegate: ColumnLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(2)
              RowLayout {
                Layout.fillWidth: true
                Label { text: modelData.target; Layout.fillWidth: true; elide: Text.ElideMiddle }
                Label { text: modelData.percent + "%" }
                Label { text: MetricsLogic.humanBytes(modelData.avail) + " free"; color: Qt.darker(Color.popups.text, 1.3) }
              }
              UsageBar { Layout.fillWidth: true; fraction: modelData.percent / 100; level: MetricsLogic.usageLevel(modelData.percent); base: "#d6a483" }
            }
          }
        }

        // Network
        RowLayout {
          Layout.fillWidth: true
          Rail { color: "#5b8cff" }
          Label { text: "NET"; font.bold: true }
          Label { text: root.m && root.m.iface ? root.m.iface : "offline"; Layout.fillWidth: true; color: Qt.darker(Color.popups.text, 1.3) }
          Label { text: root.m ? "↑ " + MetricsLogic.formatRate(root.m.rates.up) + "   ↓ " + MetricsLogic.formatRate(root.m.rates.down) : "—" }
        }

        // Top processes
        ColumnLayout {
          visible: !!(root.m && (root.m.topProcs.cpu.length > 0 || root.m.topProcs.mem.length > 0))
          Layout.fillWidth: true
          spacing: Style.space(2)
          RowLayout {
            Layout.fillWidth: true
            Rail { color: Qt.darker(Color.popups.text, 1.3) }
            Label { text: "TOP"; font.bold: true }
          }
          Repeater {
            model: root.m ? Math.max(root.m.topProcs.cpu.length, root.m.topProcs.mem.length) : 0
            delegate: RowLayout {
              required property int index
              Layout.fillWidth: true
              readonly property var c: root.m.topProcs.cpu[index]
              readonly property var mm: root.m.topProcs.mem[index]
              Label { text: c ? c.comm : ""; Layout.preferredWidth: Style.space(110); elide: Text.ElideRight }
              Label { text: c ? c.percent + "%" : ""; Layout.preferredWidth: Style.space(50); horizontalAlignment: Text.AlignRight }
              Item { Layout.preferredWidth: Style.space(16) }
              Label { text: mm ? mm.comm : ""; Layout.fillWidth: true; elide: Text.ElideRight }
              Label { text: mm ? MetricsLogic.humanBytes(mm.rss) : "" }
            }
          }
        }
      }
    }
  }
}
