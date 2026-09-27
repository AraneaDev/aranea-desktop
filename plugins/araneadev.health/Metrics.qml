// Live metrics for the health dropdown. CPU, memory and network are read
// from /proc every 2 s whether or not the dropdown is open (so the history
// and rates are ready when it opens); top processes only while it is open.

import QtQuick
import Quickshell.Io
import "MetricsLogic.js" as MetricsLogic

Item {
  id: metrics

  property var diskRows: []
  property bool topActive: false

  property var cpu: null
  property var cpuHistory: []
  property var load: null
  property var mem: null
  property string iface: ""
  property var rates: ({
      up: 0,
      down: 0
    })
  property string uptime: ""
  property string hostname: ""
  property var topProcs: ({
      cpu: [],
      mem: []
    })

  property var lastCpu: null
  property var lastNet: null
  property real lastNetAt: 0
  property var lastPs: null
  // Kernel page size and clock tick rate, read once (x86_64 defaults until
  // getconf answers; 16K pages on some arm64 systems).
  property int pageSize: 4096
  property int clockTicks: 100
  property real lastPsAt: 0

  FileView {
    id: statFile
    path: "/proc/stat"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: loadFile
    path: "/proc/loadavg"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: memFile
    path: "/proc/meminfo"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: routeFile
    path: "/proc/net/route"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: devFile
    path: "/proc/net/dev"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: uptimeFile
    path: "/proc/uptime"
    blockLoading: true
    printErrors: false
  }
  FileView {
    id: hostFile
    path: "/proc/sys/kernel/hostname"
    blockLoading: true
    printErrors: false
  }

  function read(view): string {
    view.reload()
    return String(view.text() || "")
  }

  function sample(): void {
    var stat = MetricsLogic.parseCpuStat(read(statFile))
    if (stat) {
      var pct = MetricsLogic.cpuPercent(lastCpu, stat)
      lastCpu = stat
      if (pct !== null) {
        cpu = pct
        cpuHistory = MetricsLogic.pushHistory(cpuHistory, pct, 60)
      }
    } else {
      cpu = null
    }
    load = MetricsLogic.parseLoadavg(read(loadFile))
    mem = MetricsLogic.parseMeminfo(read(memFile))
    var nextIface = MetricsLogic.defaultInterface(read(routeFile))
    if (nextIface !== iface) {
      iface = nextIface
      lastNet = null
    }
    var net = MetricsLogic.parseNetDev(read(devFile), iface)
    var now = Date.now()
    rates = MetricsLogic.netRates(lastNet, net, now - lastNetAt)
    lastNet = net
    lastNetAt = now
  }

  function refreshSlow(): void {
    var up = String(read(uptimeFile)).split(" ")[0]
    uptime = up ? MetricsLogic.formatUptime(Number(up)) : ""
    hostname = read(hostFile).trim()
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: metrics.sample()
  }
  Timer {
    interval: 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: metrics.refreshSlow()
  }

  // Top processes: two dumps of /proc/<pid>/stat, CPU from the tick delta
  // (ps only reports whole CPU seconds, too coarse for a 2 s window).
  Timer {
    interval: 2000
    repeat: true
    running: metrics.topActive
    triggeredOnStart: true
    onTriggered: if (!psProc.running)
      psProc.running = true
  }
  onTopActiveChanged: {
    if (!topActive) {
      lastPs = null
      topProcs = ({
          cpu: [],
          mem: []
        })
    }
  }

  Process {
    id: psProc
    // The glob needs a shell; the command is a constant string.
    command: ["timeout", "5", "sh", "-c", "cat /proc/[0-9]*/stat 2>/dev/null; true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A dump still in flight when the dropdown closed belongs to no
        // sampling window; keeping it would skew the first figures on reopen.
        if (!metrics.topActive)
          return
        var list = MetricsLogic.parseProcStat(text, metrics.pageSize)
        var now = Date.now()
        if (!list || list.length === 0) {
          metrics.topProcs = ({
              cpu: [],
              mem: []
            })
          return
        }
        if (metrics.lastPs)
          metrics.topProcs = MetricsLogic.topProcesses(metrics.lastPs, list, now - metrics.lastPsAt, 3, metrics.clockTicks)
        metrics.lastPs = list
        metrics.lastPsAt = now
      }
    }
  }

  Process {
    command: ["getconf", "PAGESIZE"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(text, 10)
        if (n > 0)
          metrics.pageSize = n
      }
    }
  }

  Process {
    command: ["getconf", "CLK_TCK"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(text, 10)
        if (n > 0)
          metrics.clockTicks = n
      }
    }
  }
}
