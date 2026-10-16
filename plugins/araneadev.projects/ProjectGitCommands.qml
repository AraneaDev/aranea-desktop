// Explicit Git operations (fetch, pull, task checkouts) share one command slot.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea

Item {
  id: commands
  // Capture invalidates callbacks as well as refusing new native work.
  property bool captureActive: false
  // Fixed deployed helper path; argument values never pass through a shell.
  property string backendPath: Aranea.RuntimePaths.projectGitPath
  // Inert transactions invalidate every callback from their previous epoch.
  property int epoch: 0
  // Monotonic token ties each completion to the run that started it.
  property int serial: 0
  // Internal slot; the public view below is read-only.
  property var slot: null
  // The one accepted run, or null: {operation, projectId, checkoutId, token}.
  readonly property var pending: slot
  // Latest envelope per [operation, project, checkout]: {ok, data, error}.
  property var results: ({})
  // Emitted once per accepted run with the parsed envelope.
  signal finished(string operation, string projectId, string checkoutId, var response)
  // Tests replace only the external process boundary with held completions.
  property var runner: function (argv, done) {
    if (commands.captureActive)
      return
    var process = processComponent.createObject(commands, {
      command: argv,
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  // Short-lived helpers finish exactly once, including failed starts.
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
        finish(-1, '', 'The Git helper is unavailable.')
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
  onCaptureActiveChanged: {
    epoch++
    slot = null
  }
  // JSON tuples avoid ambiguous separator collisions in exact opaque IDs.
  function resultKey(operation, projectId, checkoutId) {
    return JSON.stringify([operation, projectId, checkoutId])
  }
  // Last result recorded for a checkout and operation, or null.
  function resultFor(operation, projectId, checkoutId) {
    return results[resultKey(operation, projectId, checkoutId)] || null
  }
  // Forget the recorded result for a checkout and operation.
  function clear(operation, projectId, checkoutId) {
    var next = Object.assign({}, results)
    delete next[resultKey(operation, projectId, checkoutId)]
    results = next
  }
  // Start one operation; false means nothing was started.
  function run(operation, projectId, checkoutId, extra): bool {
    if (captureActive || slot || !operation || !projectId || !checkoutId)
      return false
    var run = {
      operation: operation,
      projectId: projectId,
      checkoutId: checkoutId,
      token: ++serial
    }
    var runEpoch = epoch
    slot = run
    var complete = function (code, text, diagnostics) {
      if (commands.slot !== run || commands.epoch !== runEpoch || commands.captureActive)
        return
      commands.slot = null
      var response = null
      try {
        response = JSON.parse(text)
      } catch (e) {}
      var valid = response && typeof response === 'object' && typeof response.ok === 'boolean' && (response.ok ? response.data : response.error && typeof response.error.code === 'string')
      if (!valid)
        response = {
          ok: false,
          data: null,
          error: {
            code: 'READ_FAILED',
            message: diagnostics || 'The Git helper did not answer.',
            recovery: 'Retry.'
          }
        }
      commands.results = Object.assign({}, commands.results, {
        [commands.resultKey(operation, projectId, checkoutId)]: response
      })
      commands.finished(operation, projectId, checkoutId, response)
    }
    var argv = [backendPath, operation, '--project', projectId, '--checkout', checkoutId].concat(extra || [], ['--json'])
    try {
      runner(argv, complete)
    } catch (e) {
      complete(-1, '', String(e))
    }
    return true
  }
}
