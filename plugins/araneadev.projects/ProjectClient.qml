// Submission/observation client for the sole persistent project owner.
import QtQuick
import Quickshell.Io

Item {
  id: client
  // Inert fixtures never invoke IPC or commands.
  property bool captureActive: false
  // Timestamped owner snapshot; it contains registry projects and proven bindings.
  property var snapshot: ({})
  // Owner IPC availability is independent of compositor launch capability.
  property bool available: false
  // One local observer may reconnect without cancelling its owner operation.
  property bool pending: false
  // Latest actionable IPC or owner request error.
  property string error: ''
  // Operation being observed, without owning launch lifetime.
  property string operationId: ''
  // Fresh reads reject responses from earlier requests or closed captures.
  property int generation: 0
  // Poll only while observing a pending owner operation.
  property int pollInterval: 150
  // Same fixed IPC wrapper used by public CLI clients.
  property string ipcPath: 'omarchy-shell'
  // Replaceable short-lived IPC boundary for isolated consumers.
  property var runner: function (argv, done) {
    var process = processComponent.createObject(client, {
      command: argv,
      completion: done
    })
    process.startRequested = true
    process.running = true
  }
  // Consumers receive owner state unchanged, including partial outcomes.
  signal operationChanged(var operation)
  // Ordinary process completion waits for collectors; failed spawn also completes.
  property Component processComponent: Component {
    Process {
      id: process
      property var completion
      property bool startRequested: false
      property bool startedSuccessfully: false
      property bool completed: false
      function finish(code, output, diagnostics) {
        if (completed)
          return
        completed = true
        completion(code, output, diagnostics)
        process.destroy()
      }
      onStarted: startedSuccessfully = true
      onRunningChanged: if (startRequested && !running && !startedSuccessfully)
        finish(-1, '', 'The project owner IPC executable is unavailable.')
      stdout: StdioCollector {
        id: output
      }
      stderr: StdioCollector {
        id: diagnostics
      }
      // Quickshell metadata omits the unused exit-status enum.
      // qmllint disable signal-handler-parameters
      onExited: function (exitCode) {
        process.finish(exitCode, output.text, diagnostics.text)
      }
      // qmllint enable signal-handler-parameters
    }
  }
  onCaptureActiveChanged: {
    generation++
    poll.stop()
    pending = false
  }
  // Decode one structured IPC response and surface missing owner errors.
  function invoke(method: string, args: var, revision: int, done: var): void {
    if (captureActive)
      return
    try {
      runner([ipcPath, 'aranea.projects', method].concat(args || []), function (code, output, diagnostics) {
        if (captureActive || revision !== generation)
          return
        var response = null
        try {
          response = JSON.parse(output)
        } catch (e) {}
        if (code !== 0 || !response || typeof response !== 'object') {
          available = false
          pending = false
          error = diagnostics || 'Project owner unavailable. Activate Aranea and retry.'
          poll.stop()
          return
        }
        available = true
        error = ''
        done(response)
      })
    } catch (e) {
      available = false
      pending = false
      error = String(e)
      poll.stop()
    }
  }
  // Refresh owner observations without creating or cancelling operations.
  function refresh(): bool {
    if (captureActive)
      return false
    var revision = generation
    invoke('snapshot', [], revision, function (response) {
      snapshot = response
    })
    return true
  }
  // Submit once, then observe the returned operation ID.
  function request(payload: var): bool {
    if (captureActive || pending)
      return false
    pending = true
    var revision = ++generation
    invoke('request', [JSON.stringify(payload)], revision, function (response) {
      if (!response.ok || !response.operationId) {
        pending = false
        error = response.error ? response.error.message : 'Project request refused.'
        return
      }
      observeOperation(response.operationId)
    })
    return true
  }
  // Reconnect to a known operation; disconnecting this item never cancels the owner.
  function observeOperation(id: string): bool {
    if (captureActive || !id)
      return false
    operationId = id
    pending = true
    readOperation()
    return true
  }
  // Read current progress and schedule another observation only if still pending.
  function readOperation(): void {
    if (captureActive || !operationId)
      return
    var id = operationId
    invoke('operation', [id], generation, function (operation) {
      if (id !== operationId)
        return
      if (!operation.id) {
        pending = false
        error = operation.error ? operation.error.message : 'Operation is unavailable.'
        return
      }
      pending = operation.state !== 'completed'
      operationChanged(operation)
      if (pending)
        poll.restart()
      else
        refresh()
    })
  }
  Timer {
    id: poll
    interval: client.pollInterval
    onTriggered: client.readOperation()
  }
}
