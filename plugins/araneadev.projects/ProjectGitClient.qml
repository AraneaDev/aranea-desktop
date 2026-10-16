// Visible-window, read-only Git observations share one bounded helper slot.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea

Item {
  id: client
  // Visibility permits observation, never controls accepted workspace operations.
  property bool active: false
  // Capture invalidates callbacks as well as refusing new native work.
  property bool captureActive: false
  // Exact selected registration and checkout, without any fallback identity.
  property string projectId: ''
  // Selected checkout identity is independent of the registered project's identity.
  property string checkoutId: ''
  // Pair-keyed entries retain {data,error}; data carries its original observedAt.
  property var cache: ({})
  // Selected presentation is derived only from its exact pair's cache entry.
  readonly property var current: (cache[cacheKey(projectId, checkoutId)] || {}).data || null
  // A failed read never erases the last good observation.
  readonly property var error: (cache[cacheKey(projectId, checkoutId)] || {}).error || null
  // Background work and old selections do not make this selection look busy.
  readonly property bool loading: active && !captureActive && ((foreground && foreground.key === cacheKey(projectId, checkoutId)) || (inFlight && inFlight.epoch === epoch && inFlight.key === cacheKey(projectId, checkoutId)))
  // Fixed deployed collector path; argument values never pass through a shell.
  property string backendPath: Aranea.RuntimePaths.projectGitStatePath
  // Monotonic per-key freshness prevents an earlier refresh publishing late.
  property int serial: 0
  // Each key retains the newest requested read token.
  property var latest: ({})
  // Inert transactions invalidate every callback from their previous epoch.
  property int epoch: 0
  // One physical process remains occupied even after its selection is hidden.
  property var inFlight: null
  // At most one newest foreground intent and twelve background targets wait.
  property var foreground: null
  // Replaceable viewport pass keeps background work bounded.
  property var background: []
  // Coalesce the two bound selection properties before observing their final pair.
  property bool selectionRefreshPending: false
  // Tests replace only the external process boundary with held completions.
  property var runner: function (argv, done) {
    if (client.captureActive || !client.active)
      return
    var process = processComponent.createObject(client, {
      command: argv,
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  // Short-lived read-only helpers finish exactly once, including failed starts.
  property Component processComponent: Component {
    Process {
      id: process
      // One completion covers both failed starts and normal helper exits.
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool completed: false
      function finish(code, text, diagnostics) {
        if (completed)
          return
        completed = true
        completion(code, text, diagnostics)
        process.destroy()
      }
      onStarted: startedSuccessfully = true
      onRunningChanged: if (startRequested && !running && !startedSuccessfully)
        finish(-1, '', 'The Git observer is not available.')
      stdout: StdioCollector {
        id: collected
      }
      stderr: StdioCollector {
        id: diagnostics
      }
      // Quickshell metadata omits the unused exit-status enum.
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode, collected.text, diagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }
  Timer {
    interval: 10000
    repeat: true
    running: client.active && !client.captureActive
    onTriggered: client.refresh()
  }
  onProjectIdChanged: selectionChanged()
  onCheckoutIdChanged: selectionChanged()
  onActiveChanged: {
    if (active)
      selectionChanged()
    else
      clearQueue()
  }
  onCaptureActiveChanged: {
    epoch++
    clearQueue()
  }
  // JSON tuples avoid ambiguous separator collisions in exact opaque IDs.
  function cacheKey(project, checkout) {
    return JSON.stringify([project, checkout])
  }
  // Stop queued reads without interfering with an already running collector.
  function clearQueue() {
    foreground = null
    background = []
    selectionRefreshPending = false
  }
  // Selection stays synchronous; observation starts after bindings settle.
  function selectionChanged() {
    foreground = null
    selectionRefreshPending = active && !captureActive
    Qt.callLater(refreshSelection)
  }
  // Explicit refresh already fulfills a deferred selection observation.
  function refreshSelection() {
    if (selectionRefreshPending)
      refresh()
  }
  // Queue the latest selected read even when an older helper occupies the slot.
  function refresh(): bool {
    selectionRefreshPending = false
    if (!active || captureActive || !projectId || !checkoutId)
      return false
    var key = cacheKey(projectId, checkoutId)
    var token = ++serial
    latest = Object.assign({}, latest, {
      [key]: token
    })
    foreground = {
      projectId: projectId,
      checkoutId: checkoutId,
      key: key,
      token: token,
      epoch: epoch
    }
    background = background.filter(function (target) {
      return target.key !== key
    })
    drain()
    return true
  }
  // A new viewport pass replaces old queued rows and accepts at most twelve pairs.
  function queueBackground(targets): void {
    if (!active || captureActive)
      return
    var queued = [], seen = {}, now = Date.now()
    for (var i = 0; i < targets.length && queued.length < 12; i++) {
      var target = targets[i]
      if (!target || !target.projectId || !target.checkoutId)
        continue
      var key = cacheKey(target.projectId, target.checkoutId)
      if (seen[key])
        continue
      seen[key] = true
      var data = (cache[key] || {}).data
      if ((inFlight && inFlight.key === key) || (foreground && foreground.key === key) || (data && now - data.observedAt < 30000))
        continue
      queued.push({
        projectId: target.projectId,
        checkoutId: target.checkoutId,
        key: key
      })
    }
    background = queued
    drain()
  }
  // Only this scheduler may occupy the collector slot; foreground always wins.
  function drain() {
    if (!active || captureActive || inFlight)
      return
    // A viewport notification may arrive before deferred selection bindings settle.
    if (selectionRefreshPending && projectId && checkoutId) {
      refresh()
      return
    }
    var read = foreground
    if (read)
      foreground = null
    else if (background.length) {
      read = Object.assign({}, background[0], {
        token: ++serial,
        epoch: epoch
      })
      background = background.slice(1)
      latest = Object.assign({}, latest, {
        [read.key]: read.token
      })
    }
    if (!read)
      return
    inFlight = read
    var complete = function (code, text, diagnostics) {
      if (client.inFlight !== read)
        return
      client.inFlight = null
      if (!client.captureActive && read.epoch === client.epoch && client.latest[read.key] === read.token) {
        var response = null
        try {
          response = JSON.parse(text)
        } catch (e) {}
        var valid = response && response.ok === true && code === 0 && response.data && response.data.projectId === read.projectId && response.data.checkoutId === read.checkoutId && typeof response.data.observedAt === 'number' && isFinite(response.data.observedAt)
        var previous = client.cache[read.key] || {}
        var failure = response && response.ok === false && response.error && typeof response.error.code === 'string' ? response.error : {
          code: 'READ_FAILED',
          message: diagnostics || 'Git observation could not be read.',
          recovery: 'Refresh the selected checkout.'
        }
        client.cache = Object.assign({}, client.cache, {
          [read.key]: {
            data: valid ? response.data : previous.data || null,
            error: valid ? null : failure
          }
        })
      }
      client.drain()
    }
    try {
      runner([backendPath, '--project', read.projectId, '--checkout', read.checkoutId, '--json'], complete)
    } catch (e) {
      complete(-1, '', String(e))
    }
  }
}
