// Health service (the plugin's "service" entry point, loaded by
// omarchy-shell): runs the checks (Monitor.qml) and the metrics sampler
// (Metrics.qml), and answers the "health" IPC target. The bar widget
// (Panel.qml) reads it through HealthBridge.js.

import QtQuick
import Quickshell.Io
import "HealthLogic.js" as HealthLogic
import "HealthBridge.js" as HealthBridge

Item {
  id: service

  // Injected by omarchy-shell.
  property var shell: null

  // The health checks; Panel.qml calls monitor.checkDisk() when it opens.
  property alias monitor: monitor
  Monitor {
    id: monitor
  }

  // The live metrics sampler the dropdown reads.
  property alias metrics: metrics
  // Dropdowns currently open (one bar per monitor can each have one). Top
  // processes are sampled only while at least one is open.
  property int openPanels: 0
  // Called by a Panel.qml whose dropdown opened.
  function panelOpened(): void {
    openPanels++
  }
  // Called by a Panel.qml whose dropdown closed; never goes below 0.
  function panelClosed(): void {
    openPanels = Math.max(0, openPanels - 1)
  }

  Metrics {
    id: metrics
    diskRows: monitor.diskRows
    topActive: service.openPanels > 0
  }

  // Annotated open problems (HealthLogic.annotateProblems rows).
  readonly property var problems: monitor.openProblems
  // "healthy", "attention" or "critical" (HealthLogic.statusFor).
  readonly property string status: HealthLogic.statusFor(monitor.openProblems)

  // Toggles the health dropdown through the shell, if one was injected.
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
      return JSON.stringify({
        cpu: service.metrics.cpu,
        mem: service.metrics.mem,
        iface: service.metrics.iface,
        rates: service.metrics.rates,
        uptime: service.metrics.uptime,
        hostname: service.metrics.hostname,
        samples: service.metrics.cpuHistory.length
      })
    }
  }
}
