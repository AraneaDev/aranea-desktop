// Live metrics for the health dropdown (Service.qml's `metrics`, shown by
// Panel.qml). CPU, memory and network are read
// from /proc every 2 s whether or not the dropdown is open (so the history
// and rates are ready when it opens); top processes only while it is open.

import QtQuick
import Quickshell.Io
import "MetricsLogic.js" as MetricsLogic

Item {
  id: metrics

  // df rows from Monitor.qml, bound by Service.qml; only passed through for
  // the dropdown's disk list.
  property var diskRows: []
  // Sample top processes; Service.qml sets it while a dropdown is open.
  property bool topActive: false

  // CPU use in whole percent, null when /proc/stat could not be parsed.
  property var cpu: null
  // The last 60 CPU percentages (one per 2 s sample).
  property var cpuHistory: []
  // [1, 5, 15] minute load averages, or null.
  property var load: null
  // MemInfo from MetricsLogic.parseMeminfo (bytes), or null.
  property var mem: null
  // Interface of the default route, "" when there is none.
  property string iface: ""
  // Network throughput of `iface` in bytes per second.
  property var rates: ({
      up: 0,
      down: 0
    })
  // Formatted uptime ("up 3h 12m"), refreshed every minute.
  property string uptime: ""
  // Kernel hostname, refreshed every minute.
  property string hostname: ""
  // Top 3 processes by CPU and by memory (MetricsLogic.topProcesses); empty
  // lists while topActive is false.
  property var topProcs: ({
      cpu: [],
      mem: []
    })

  // Previous /proc/stat sample, for the CPU delta.
  property var lastCpu: null
  // Previous byte counters of `iface`; reset when the interface changes.
  property var lastNet: null
  // Time (ms) of lastNet.
  property real lastNetAt: 0
  // CPU cores (cpuN lines in /proc/stat), for the TOP percentage cap.
  property int cores: 1
  // Previous /proc/<pid>/stat dump, for the per-process CPU delta.
  property var lastPs: null
  // Kernel page size and clock tick rate, read once (x86_64 defaults until
  // getconf answers; 16K pages on some arm64 systems).
  property int pageSize: 4096
  // Clock ticks per second (getconf CLK_TCK).
  property int clockTicks: 100
  // Time (ms) of lastPs.
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

  // Reloads a FileView synchronously and returns its text ("" on failure).
  function read(view): string {
    view.reload()
    return String(view.text() || "")
  }

  // Takes the 2 s sample: CPU, load, memory, default interface and rates.
  function sample(): void {
    var statText = read(statFile)
    cores = MetricsLogic.countCores(statText)
    var stat = MetricsLogic.parseCpuStat(statText)
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
    // Elapsed time from the boot clock: a wall-clock step or a suspend must
    // not distort the rates. Unreadable uptime means no rate this sample.
    var uptime = MetricsLogic.uptimeMs(read(uptimeFile))
    var now = uptime === null ? lastNetAt : uptime
    rates = MetricsLogic.netRates(lastNet, net, now - lastNetAt)
    lastNet = net
    lastNetAt = now
  }

  // Refreshes uptime and hostname; also called when a dropdown opens.
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
        var uptime = MetricsLogic.uptimeMs(metrics.read(uptimeFile))
        var now = uptime === null ? metrics.lastPsAt : uptime
        if (!list || list.length === 0) {
          metrics.topProcs = ({
              cpu: [],
              mem: []
            })
          return
        }
        if (metrics.lastPs)
          metrics.topProcs = MetricsLogic.topProcesses(metrics.lastPs, list, now - metrics.lastPsAt, 3, metrics.clockTicks, metrics.cores)
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
