// Health service: runs the checks (Monitor) and, from Task 5, the metrics
// sampler; the bar widget (Panel.qml) reads it through HealthBridge.js.

import QtQuick
import Quickshell.Io
import "HealthLogic.js" as HealthLogic
import "HealthBridge.js" as HealthBridge

Item {
  id: service

  // Injected by omarchy-shell.
  property var shell: null

  property alias monitor: monitor
  Monitor { id: monitor }

  property alias metrics: metrics
  // Dropdowns currently open (one bar per monitor can each have one). Top
  // processes are sampled only while at least one is open.
  property int openPanels: 0
  function panelOpened(): void { openPanels++ }
  function panelClosed(): void { openPanels = Math.max(0, openPanels - 1) }

  Metrics {
    id: metrics
    diskRows: monitor.diskRows
    topActive: service.openPanels > 0
  }

  readonly property var problems: monitor.openProblems
  readonly property string status: HealthLogic.statusFor(monitor.openProblems)

  function toggle(): void {
    if (service.shell && typeof service.shell.toggle === "function")
      service.shell.toggle("araneadev.health")
  }

  Component.onCompleted: HealthBridge.publish(service)
  Component.onDestruction: HealthBridge.retract(service)

  IpcHandler {
    target: "health"
    function toggle(): string {
      service.toggle()
      return "ok"
    }
    function status(): string {
      return service.status
    }
    // Rerun the checks now instead of waiting for their timers.
    function refresh(): string {
      service.monitor.checkUnits()
      service.monitor.checkDisk()
      service.monitor.checkReboot()
      return "ok"
    }
    function metrics(): string {
      return JSON.stringify({ cpu: service.metrics.cpu, mem: service.metrics.mem, iface: service.metrics.iface,
        rates: service.metrics.rates, uptime: service.metrics.uptime, hostname: service.metrics.hostname,
        samples: service.metrics.cpuHistory.length })
    }
  }
}
