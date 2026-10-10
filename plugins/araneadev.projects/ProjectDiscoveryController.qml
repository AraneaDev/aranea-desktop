// Persistent cancellable discovery observer; visibility never owns scan lifetime.
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea

Item {
  id: client
  // Inert fixtures never start processes or cancel real scans.
  property bool captureActive: false
  // Private wrapper owns the CLI and all nested scan process groups.
  property string scanPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-scan'
  // Transient candidates are observations, never registry registrations.
  property var candidates: []
  // Includes cancellation teardown until the owned process has really exited.
  property bool pending: false
  // Discovery completed only a bounded portion of the selected folder.
  property bool partial: false
  // Actionable scan diagnostics and bounded-traversal reasons.
  property var errors: []
  // Explicitly selected registered root, retained for refresh and diagnostics.
  property string rootId: ''
  // Late callbacks cannot publish after cancellation or a replacement scan.
  property int generation: 0
  // The cancellation closure targets only the process created by this client.
  property var stopOwnedScan: null
  // Safe streaming process boundary returns a cancellation closure for its own scan.
  property var runner: function (argv, line, done) {
    var process = processComponent.createObject(client, {
      command: argv,
      lineCallback: line,
      completion: done
    })
    process.startRequested = true
    process.running = true
    return function () {
      process.cancelRequested = true
      if (process.startedSuccessfully)
        process.write('cancel\n')
    }
  }
  // Observe one public JSONL event without persisting candidates.
  function acceptLine(line: string, revision: int): void {
    if (captureActive || revision !== generation)
      return
    var event
    try {
      event = JSON.parse(line)
    } catch (e) {
      errors = errors.concat(['Invalid discovery response. Retry the scan.'])
      return
    }
    var data = event.data || {}
    if (event.event === 'step' && data.event === 'candidate' && data.candidate && typeof data.candidate.path === 'string') {
      var candidate = data.candidate
      if (!candidates.some(function (c) {
        return c.path === candidate.path
      }))
        candidates = candidates.concat([candidate])
    }
    if (event.event === 'completed') {
      partial = data.outcome === 'partial'
      errors = data.errors || []
      if (event.code)
        errors = errors.concat([event.message || event.code, data.recovery || 'Retry after checking the folder.'])
    }
  }
  // Scan only an explicitly selected opaque root ID through fixed helper argv.
  function start(id: string): bool {
    if (captureActive || pending || !/^r-[A-Za-z0-9-]+$/.test(id))
      return false
    generation++
    var revision = generation
    rootId = id
    candidates = []
    errors = []
    partial = false
    pending = true
    try {
      stopOwnedScan = runner([scanPath, id], function (line) {
        client.acceptLine(line, revision)
      }, function (code, diagnostics) {
        pending = false
        stopOwnedScan = null
        if (revision !== generation || captureActive)
          return
        if (code !== 0 && !partial && !errors.length)
          errors = [diagnostics || 'Discovery failed. Check the folder and retry.']
      })
    } catch (e) {
      pending = false
      errors = [String(e)]
      return false
    }
    return true
  }
  // Cancel the actual private group then invalidate any late scan output.
  function cancel(): bool {
    if (captureActive || !pending || !stopOwnedScan)
      return false
    generation++
    stopOwnedScan()
    return true
  }
  // Each tracked process keeps cancellation transport alive until its wrapper exits.
  property Component processComponent: Component {
    Process {
      id: process
      property var lineCallback
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool completed: false
      property bool cancelRequested: false
      stdinEnabled: true
      // Complete once even when the helper fails to spawn.
      function finish(code: int, diagnostics: string): void {
        if (completed)
          return
        completed = true
        completion(code, diagnostics)
        process.destroy()
      }
      onStarted: {
        startedSuccessfully = true
        if (cancelRequested)
          write('cancel\n')
      }
      onRunningChanged: if (startRequested && !running && !startedSuccessfully)
        finish(-1, 'Discovery helper unavailable. Activate Aranea and retry.')
      stdout: SplitParser {
        onRead: function (data) {
          process.lineCallback(data)
        }
      }
      stderr: StdioCollector {
        id: diagnostics
      }
      // Quickshell metadata omits the unused exit-status enum.
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode, diagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }
}
