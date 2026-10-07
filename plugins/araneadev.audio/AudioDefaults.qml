// Persistent default-device owner shared by audio panels and desktop search.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "AudioLogic.js" as AudioLogic
import "Model.js" as Model

Item {
  id: owner
  // PipeWire boundary, replaceable without touching real devices in fixtures.
  property var backend: Pipewire
  // Whether external availability observations may run.
  property bool observationsEnabled: true
  // Maximum time to wait for a default-device echo.
  property int confirmationTimeout: AudioLogic.defaultTimeoutMs
  // Number of open panel consumers, including bars on other monitors.
  property int openPanels: 0
  // Number of active search consumers.
  property int searchConsumers: 0
  // Pending output state; panel choices retain last-choice-wins queuing.
  property var outputPending: AudioLogic.defaultIdle()
  // Pending input state.
  property var inputPending: AudioLogic.defaultIdle()
  // Latest physically observed sink availability by node name.
  property var sinkAvailability: ({})
  // Whether the availability helper has returned a valid observation.
  property bool sinkAvailabilityLoaded: false
  // Last populated output list, for panel display only, never dispatch.
  property var cachedAudioSinks: []
  // Last populated input list, for panel display only.
  property var cachedAudioSources: []
  // Search request awaiting a confirmed output, independent of panel visibility.
  property string searchRequestId: ""
  // Exact output identity requested by search.
  property string searchTargetKey: ""
  // Current output from the authoritative backend.
  readonly property var sink: backend ? backend.defaultAudioSink : null
  // Current input from the authoritative backend.
  readonly property var source: backend ? backend.defaultAudioSource : null
  // Current backend nodes, never the panel's cached presentation list.
  readonly property var nodes: backend && backend.nodes ? backend.nodes.values : []
  // Stable observed output key.
  readonly property string sinkKey: AudioLogic.deviceKey(sink)
  // Stable observed input key.
  readonly property string sourceKey: AudioLogic.deviceKey(source)
  // Optimistic output projection used by the existing panel.
  readonly property var outputShown: AudioLogic.defaultView(outputPending, sinkKey)
  // Optimistic input projection used by the existing panel.
  readonly property var inputShown: AudioLogic.defaultView(inputPending, sourceKey)
  // Candidate output devices from live nodes.
  readonly property var candidateSinks: nodes.filter(function (node) {
    return node && node.isSink && !node.isStream
  })
  // Candidate input devices, excluding the shell's own capture.
  readonly property var candidateSources: nodes.filter(function (node) {
    return node && !node.isSink && !node.isStream && Model.isAudioSource(node) && node.name !== "quickshell"
  })
  // Available output list including the observed default for panel display.
  readonly property var rawAudioSinks: {
    var list = candidateSinks.filter(sinkAvailable)
    if (sink && list.indexOf(sink) < 0)
      list.unshift(sink)
    return list
  }
  // Inputs including the observed default.
  readonly property var rawAudioSources: {
    var list = candidateSources.slice()
    if (source && list.indexOf(source) < 0)
      list.unshift(source)
    return list
  }
  // Unavailable outputs for dimmed panel rows.
  readonly property var unpluggedSinks: candidateSinks.filter(function (node) {
    return !sinkAvailable(node)
  })
  // Panel output display projection during transient model gaps.
  readonly property var audioSinks: rawAudioSinks.length ? rawAudioSinks : cachedAudioSinks
  // Panel input display projection during transient model gaps.
  readonly property var audioSources: rawAudioSources.length ? rawAudioSources : cachedAudioSources
  // Whether consumers or in-flight selections require helper observations.
  readonly property bool observing: observationsEnabled && (openPanels > 0 || searchConsumers > 0 || outputPending.target !== null || inputPending.target !== null)
  // Default dispatch boundary: PipeWire preference plus the existing helper.
  property var sendDefault: function (channel, node) {
    if (channel === "output")
      backend.preferredDefaultAudioSink = node
    else
      backend.preferredDefaultAudioSource = node
    if (node.id !== undefined && node.name)
      Quickshell.execDetached([channel === "output" ? "omarchy-audio-output-set-default" : "omarchy-audio-input-set-default", String(node.id), String(node.name)])
  }
  // Notifies active search consumers to coalesce their record publication.
  signal snapshotChanged
  // Reports one confirmed or failed search request.
  signal outputCompleted(string requestId, bool succeeded, string message)

  // Keep the panel's historical nonempty display snapshots.
  onRawAudioSinksChanged: {
    if (rawAudioSinks.length)
      cachedAudioSinks = rawAudioSinks
    snapshotChanged()
  }
  onRawAudioSourcesChanged: if (rawAudioSources.length)
    cachedAudioSources = rawAudioSources
  onOutputPendingChanged: snapshotChanged()
  onSinkAvailabilityChanged: {
    snapshotChanged()
    Qt.callLater(owner.reconcileSearch)
  }
  onSinkAvailabilityLoadedChanged: snapshotChanged()
  onCandidateSinksChanged: {
    snapshotChanged()
    Qt.callLater(owner.reconcileSearch)
  }
  onSinkKeyChanged: {
    if (searchRequestId && sinkKey === searchTargetKey)
      finishSearch(true, "")
    applyDefault("output", AudioLogic.defaultEcho(outputPending, sinkKey))
    snapshotChanged()
  }
  onSourceKeyChanged: applyDefault("input", AudioLogic.defaultEcho(inputPending, sourceKey))

  // Acquire panel observations once per visible panel.
  function panelOpened(): void {
    openPanels += 1
  }
  // Release a panel and drop its queued choices only when no panel remains.
  function panelClosed(): void {
    openPanels = Math.max(0, openPanels - 1)
    if (openPanels === 0) {
      outputPending = AudioLogic.defaultAfter("close", outputPending)
      inputPending = AudioLogic.defaultAfter("close", inputPending)
    }
  }
  // Acquire availability observations for a live search.
  function acquireSearch(): void {
    searchConsumers += 1
  }
  // Release search observations without cancelling an operation.
  function releaseSearch(): void {
    searchConsumers = Math.max(0, searchConsumers - 1)
  }
  // Physical availability check using the last helper observation.
  function sinkAvailable(node): bool {
    return !node || !node.name || !sinkAvailabilityLoaded || sinkAvailability[String(node.name)] !== false
  }
  // Return plain authoritative action records, never cached panel nodes.
  function snapshot(): var {
    return {
      available: !!backend && sinkAvailabilityLoaded,
      outputs: candidateSinks.filter(function (node) {
        return owner.sinkAvailable(node)
      }).map(function (node) {
        return {
          key: AudioLogic.deviceKey(node),
          label: Model.nodeLabel(node),
          current: AudioLogic.deviceKey(node) === owner.sinkKey
        }
      }),
      busy: outputPending.target !== null
    }
  }
  // Submit an exact fresh device for search; repeated pending requests are refused.
  function requestOutput(key: string, requestId: string): bool {
    if (!requestId || searchRequestId || outputPending.target !== null || !sinkAvailabilityLoaded)
      return false
    var node = AudioLogic.nodeByKey(candidateSinks, key, true)
    if (!node || !sinkAvailable(node))
      return false
    if (key === sinkKey) {
      outputCompleted(requestId, true, "")
      return true
    }
    searchRequestId = requestId
    searchTargetKey = key
    requestDefault("output", node)
    return true
  }
  // Retain the panel's existing queued selection semantics through one owner.
  function requestDefault(channel: string, node): void {
    if (!node)
      return
    var output = channel === "output"
    var key = AudioLogic.deviceKey(node)
    var current = AudioLogic.nodeByKey(output ? candidateSinks : candidateSources, key, true)
    if (!current || output && !sinkAvailable(current))
      return
    applyDefault(channel, AudioLogic.defaultClick(output ? outputPending : inputPending, key, output ? sinkKey : sourceKey))
  }
  // Apply the existing state transition, fresh dispatch, and timeout behavior.
  function applyDefault(channel: string, result): void {
    var output = channel === "output"
    if (output)
      outputPending = result.state
    else
      inputPending = result.state
    if (result.send !== null) {
      var node = AudioLogic.nodeByKey(output ? candidateSinks : candidateSources, result.send, true)
      if (!node || output && !sinkAvailable(node)) {
        expire(channel, "Audio output is no longer available")
      } else {
        try {
          sendDefault(channel, node)
        } catch (error) {
          expire(channel, "Could not change audio output")
        }
      }
    }
    var timer = output ? outputTimer : inputTimer
    if ((output ? outputPending : inputPending).target === null)
      timer.stop()
    else if (result.send !== null)
      timer.restart()
  }
  // Settle a search request exactly once before sending a queued panel choice.
  function finishSearch(ok: bool, message: string): void {
    if (!searchRequestId)
      return
    var id = searchRequestId
    searchRequestId = ""
    searchTargetKey = ""
    outputCompleted(id, ok, message)
  }
  // A disappeared or unavailable device cannot complete by selecting another node.
  function reconcileSearch(): void {
    if (!searchRequestId)
      return
    var node = AudioLogic.nodeByKey(candidateSinks, searchTargetKey, true)
    if (!node || !sinkAvailable(node))
      expire("output", "Audio output is no longer available")
  }
  // Timeout clears the queued choice and reports the observed-state failure.
  function expire(channel: string, message: string): void {
    if (channel === "output") {
      outputPending = AudioLogic.defaultAfter("timeout", outputPending)
      outputTimer.stop()
      finishSearch(false, message)
    } else {
      inputPending = AudioLogic.defaultAfter("timeout", inputPending)
      inputTimer.stop()
    }
  }
  Timer {
    id: outputTimer
    interval: owner.confirmationTimeout
    onTriggered: owner.expire("output", "Timed out changing audio output")
  }
  PwObjectTracker {
    objects: owner.candidateSinks
  }
  PwObjectTracker {
    objects: owner.candidateSources
  }
  Timer {
    id: inputTimer
    interval: owner.confirmationTimeout
    onTriggered: owner.expire("input", "Timed out changing audio input")
  }
  Process {
    id: availabilityProcess
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector {
      id: availabilityOutput
      waitForEnd: true
    }
    // Quickshell metadata omits the unused QProcess exit-status enum.
    // qmllint disable signal-handler-parameters
    onExited: function (code) {
      owner.sinkAvailabilityLoaded = code === 0
      if (code === 0)
        owner.sinkAvailability = Model.parseSinkAvailability(availabilityOutput.text)
    }
    // qmllint enable signal-handler-parameters
  }
  Timer {
    interval: 5000
    repeat: true
    running: owner.observing
    triggeredOnStart: true
    onTriggered: if (!availabilityProcess.running)
      availabilityProcess.running = true
  }
}
