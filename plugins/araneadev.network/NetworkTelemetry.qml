// Persistent connection telemetry; the host supplies polling and reset policy.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "Model.js" as Model
import "../araneadev.shared/GraphLogic.js" as GraphLogic

Item {
  id: root
  visible: false

  // Poll and record graph samples while the host is open, on any hosted page.
  property bool pollingEnabled: false
  // Retain the last good sample while a band change temporarily loses its route.
  property bool bandBusy: false

  // Live connection details from `ip` / /sys / iw.
  property var info: ({})  // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq, bitrate, rx_bytes, tx_bytes, router_ping_ms, internet_ping_ms }

  // Throughput tracking. Rates are computed as deltas between successive
  // `omarchy-network-status --verbose` samples (~1.5s apart via detailsPoll).
  // We hold "prev" alongside a timestamp so the first sample after open or
  // after an interface switch doesn't manufacture a spike.
  property real prevRxBytes: 0
  // Bytes sent as of the last sample.
  property real prevTxBytes: 0
  // Wall-clock time of the last sample, in seconds.
  property real prevSampleTime: 0
  // Interface the last sample was taken on; a change resets the rate calc.
  property string prevIface: ""
  // Download rate in bytes/sec, derived from the last two samples.
  property real downloadRate: 0  // bytes/sec
  // Upload rate in bytes/sec, derived from the last two samples.
  property real uploadRate: 0    // bytes/sec
  // Interface the ping history was sampled on; a change resets the window.
  property string pingIface: ""
  // Recent router ping samples, newest last, windowed to pingHistoryWindow.
  property var routerPingSamples: []
  // Recent internet ping samples, newest last, windowed to pingHistoryWindow.
  property var internetPingSamples: []
  // Rolling average router ping latency in ms, or -1 before enough samples.
  property real routerPingLatency: -1
  // Rolling average internet ping latency in ms, or -1 before enough samples.
  property real internetPingLatency: -1
  // Percentage of the recent internet ping samples that were lost.
  property int internetPingPacketLoss: 0
  // How many ping samples routerPingSamples/internetPingSamples retain.
  readonly property int pingHistoryWindow: 24
  // How many of the most recent samples the rolling average is taken over.
  readonly property int pingAverageWindow: 5
  // Whether there is at least one internet ping sample to report on.
  readonly property bool hasInternetPing: internetPingSamples.length > 0
  // Every stat row stays mounted whether or not there is data behind it, so a
  // sample arriving late never reflows the grid. This says whether the numbers
  // are real yet or the row should read "--".
  readonly property bool hasTransferStats: info.rx_bytes !== undefined
  // Throughput samples for the Link graph, oldest first: [{iface, rx, tx}].
  property var linkHistory: []

  // A direct refresh is allowed while closed; never overlap an existing read.
  function refresh() {
    if (!detailsProc.running)
      detailsProc.running = true
  }

  // The host invokes this at the original close-handler position.
  function resetMeasurements() {
    prevSampleTime = 0
    downloadRate = 0
    uploadRate = 0
    pingIface = ""
    routerPingSamples = []
    internetPingSamples = []
    routerPingLatency = -1
    internetPingLatency = -1
    internetPingPacketLoss = 0
  }

  // Kept separate because the host clears graph history later in close handling.
  function resetLinkHistory() {
    linkHistory = []
  }

  // Applies a freshly parsed `omarchy-network-status --verbose` sample.
  function updateDetails(raw) {
    var next = Model.parseKeyValue(raw)

    // A band change tears the link down and brings it back, and the status
    // command reports nothing at all while there is no route. Publishing that
    // would blank every stat and unmount the whole section mid-toggle, so the
    // last good sample stands until the reconnect settles. A real disconnect is
    // still reported, because nothing is in flight then.
    if (bandBusy && !next.iface)
      return
    info = next
    updateThroughput(next)
    updatePingLatency(next)
    recordLinkSample()
  }

  // Recomputes download/upload rates from the latest sample.
  function updateThroughput(next) {
    var state = Model.throughputState({
      prevIface: prevIface,
      prevRxBytes: prevRxBytes,
      prevTxBytes: prevTxBytes,
      prevSampleTime: prevSampleTime,
      downloadRate: downloadRate,
      uploadRate: uploadRate
    }, next, Date.now() / 1000)

    prevIface = state.prevIface
    prevRxBytes = state.prevRxBytes
    prevTxBytes = state.prevTxBytes
    prevSampleTime = state.prevSampleTime
    downloadRate = state.downloadRate
    uploadRate = state.uploadRate
  }

  // Recomputes rolling ping latency/loss from the latest sample.
  function updatePingLatency(next) {
    var state = Model.pingLatencyState({
      pingIface: pingIface,
      routerPingSamples: routerPingSamples,
      internetPingSamples: internetPingSamples
    }, next, pingHistoryWindow, pingAverageWindow)

    pingIface = state.pingIface
    routerPingSamples = state.routerPingSamples
    internetPingSamples = state.internetPingSamples
    routerPingLatency = state.routerPingLatency
    internetPingLatency = state.internetPingLatency
    internetPingPacketLoss = state.internetPingPacketLoss
  }

  // Records one Link graph sample from the rates stock just computed. Only
  // while open, so the occasional refresh of a closed panel adds nothing.
  function recordLinkSample() {
    if (!pollingEnabled || !info.iface || !hasTransferStats)
      return
    linkHistory = GraphLogic.pushSample(linkHistory, {
      iface: info.iface,
      rx: downloadRate,
      tx: uploadRate
    }, 40)
  }

  // Pulls everything we want about the active route's interface in one shot.
  Process {
    id: detailsProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDetails(text)
    }
  }

  // Poll details while the panel is open so the IP/route header catches up
  // as soon as NetworkManager finishes activating a connection.
  Timer {
    id: detailsPoll
    interval: 1500
    repeat: true
    running: root.pollingEnabled
    onTriggered: if (!detailsProc.running)
      detailsProc.running = true
  }
}
