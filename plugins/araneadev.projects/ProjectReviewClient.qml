// Reads how a task checkout differs from its base, and opens one fixed diff. Reads never fetch.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea
import "ProjectReview.js" as Review

Item {
  id: client
  // Visibility permits reads, never accepted work.
  property bool active: false
  // Capture invalidates callbacks as well as refusing new native work.
  property bool captureActive: false
  // Selected project and checkout, bound by the owner.
  property string projectId: ''
  // Selected checkout, bound by the owner.
  property string checkoutId: ''
  // Agent tasks from the activity snapshot; only checkouts with a finished task are read.
  property var tasks: []
  // The shared Git command client; a finished fetch, pull or push re-reads the review.
  property var commands: null
  // checkoutId to {data, error}; a failed read keeps the last good data.
  property var reviews: ({})
  // Fixed deployed helper paths; values never pass through a shell.
  property string backendPath: Aranea.RuntimePaths.projectGitPath
  // Fixed deployed launcher path.
  property string launcherPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-launch'
  // Opening the diff is running, and its last failure as {code, message, recovery}, or null.
  property bool diffPending: false
  // Last Open diff failure as {code, message, recovery}, or null.
  property var diffError: null
  // Inert transactions invalidate every callback from their previous epoch.
  property int epoch: 0
  // One physical read at a time; a newer wish for another pair waits here.
  property var inFlight: null
  // Newest read waiting for the slot.
  property var wanted: null
  // Changes whenever the selected checkout's task report changes.
  readonly property string signature: JSON.stringify(Review.tasksFor(tasks, projectId, checkoutId).map(function (t) {
    return [t.id, t.reportedState, t.lastReceivedAt]
  }))
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
  // The launcher takes one JSON request on stdin.
  property var launcherRunner: function (argv, input, done) {
    if (client.captureActive)
      return
    var process = launcherComponent.createObject(client, {
      command: argv,
      input: input,
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  // Short-lived read helper that finishes exactly once.
  property Component processComponent: Component {
    Process {
      id: process
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
        finish(-1, '', 'The Git helper is not available.')
      stdout: StdioCollector {
        id: collected
      }
      stderr: StdioCollector {
        id: diagnostics
      }
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode, collected.text, diagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }
  // Short-lived launcher helper that takes one JSON request on stdin.
  property Component launcherComponent: Component {
    Process {
      id: process
      property string input: ''
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool completed: false
      stdinEnabled: true
      function finish(code, text, diagnostics) {
        if (completed)
          return
        completed = true
        completion(code, text, diagnostics)
        process.destroy()
      }
      onStarted: {
        startedSuccessfully = true
        write(input + '\n')
        stdinEnabled = false
      }
      onRunningChanged: if (startRequested && !running && !startedSuccessfully)
        finish(-1, '', 'The launcher is not available.')
      stdout: StdioCollector {
        id: launched
      }
      stderr: StdioCollector {
        id: launchDiagnostics
      }
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode, launched.text, launchDiagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }
  Timer {
    interval: 10000
    repeat: true
    running: client.active && !client.captureActive
    onTriggered: client.refreshSelected()
  }
  Connections {
    target: client.commands
    function onFinished(operation, project, checkout) {
      if (operation === 'fetch' || operation === 'pull' || operation === 'push')
        client.refresh(project, checkout)
    }
  }
  onProjectIdChanged: {
    diffError = null
    Qt.callLater(refreshSelected)
  }
  onCheckoutIdChanged: {
    diffError = null
    Qt.callLater(refreshSelected)
  }
  onActiveChanged: if (active)
    Qt.callLater(refreshSelected)
  onSignatureChanged: Qt.callLater(refreshSelected)
  onCaptureActiveChanged: {
    epoch++
    wanted = null
    diffPending = false
  }
  // The checkout has a finished agent task, so a review is worth reading.
  function eligible(project, checkout): bool {
    return !!Review.latestFinished(Review.tasksFor(tasks, project, checkout))
  }
  // Read the selected pair again.
  function refreshSelected(): bool {
    return refresh(projectId, checkoutId)
  }
  // Read one pair; false means nothing was queued.
  function refresh(project, checkout): bool {
    if (!active || captureActive || !project || !checkout || !eligible(project, checkout))
      return false
    wanted = {
      projectId: project,
      checkoutId: checkout
    }
    drain()
    return true
  }
  // Start the waiting read when the slot is free.
  function drain() {
    if (inFlight || !wanted || captureActive || !active)
      return
    var read = Object.assign({
      epoch: epoch
    }, wanted)
    wanted = null
    inFlight = read
    var complete = function (code, text, diagnostics) {
      if (client.inFlight !== read)
        return
      client.inFlight = null
      if (!client.captureActive && read.epoch === client.epoch) {
        var response = null
        try {
          response = JSON.parse(text)
        } catch (e) {}
        var valid = response && response.ok === true && response.data && response.data.projectId === read.projectId && response.data.checkoutId === read.checkoutId
        var previous = client.reviews[read.checkoutId] || {}
        var failure = response && response.ok === false && response.error && typeof response.error.code === 'string' ? response.error : {
          code: 'READ_FAILED',
          message: diagnostics || 'The review could not be read.',
          recovery: 'Retry.'
        }
        client.reviews = Object.assign({}, client.reviews, {
          [read.checkoutId]: {
            data: valid ? response.data : previous.data || null,
            error: valid ? null : failure
          }
        })
      }
      client.drain()
    }
    try {
      runner([backendPath, 'review', '--project', read.projectId, '--checkout', read.checkoutId, '--json'], complete)
    } catch (e) {
      complete(-1, '', String(e))
    }
  }
  // Open the saved terminal on `git diff <mergeBase>...HEAD` of a registered checkout.
  function openDiff(path, mergeBase, terminalId): bool {
    if (captureActive || diffPending || !path || !/^[0-9a-f]{40}$/.test(mergeBase || '') || !terminalId)
      return false
    diffPending = true
    diffError = null
    var runEpoch = epoch
    var done = function (code, text, diagnostics) {
      if (client.epoch !== runEpoch || client.captureActive)
        return
      client.diffPending = false
      var response = null
      try {
        response = JSON.parse(text)
      } catch (e) {}
      client.diffError = code === 0 && response && response.ok ? null : {
        code: response && response.code || 'LAUNCH_FAILED',
        message: response && response.message || diagnostics || 'The terminal could not start.',
        recovery: 'Retry.'
      }
    }
    try {
      launcherRunner([launcherPath], JSON.stringify({
        kind: 'diff',
        cwd: path,
        mergeBase: mergeBase,
        terminalId: terminalId
      }), done)
    } catch (e) {
      done(-1, '', String(e))
    }
    return true
  }
}
