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
  // Structured refusal remains available to consumers while the owner prepares.
  property var requestError: null
  // Preparation retries apply only before any operation has been accepted.
  property bool preparing: false
  // Bound readiness retries; reaching this deadline leaves the request rejected.
  property int readyTimeout: 5000
  // Original serialized request is immutable throughout rejected-only retries.
  property string submissionJson: ''
  // Absolute preparation deadline does not extend on each readiness refusal.
  property real submissionDeadline: 0
  // Operation being observed, without owning launch lifetime.
  property string operationId: ''
  // Fresh reads reject responses from earlier requests or closed captures.
  property int generation: 0
  // Snapshot reads have independent freshness so Refresh cannot invalidate accepted work.
  property int snapshotReadRevision: 0
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
    snapshotReadRevision++
    poll.stop()
    readyRetry.stop()
    submissionJson = ''
    preparing = false
    pending = false
  }
  // Decode one structured IPC response and surface missing owner errors.
  function invoke(method: string, args: var, revision: int, done: var): void {
    if (captureActive)
      return
    var readRevision = snapshotReadRevision
    try {
      runner([ipcPath, 'aranea.projects', method].concat(args || []), function (code, output, diagnostics) {
        if (captureActive || revision !== generation || method === 'snapshot' && readRevision !== snapshotReadRevision)
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
          readyRetry.stop()
          submissionJson = ''
          preparing = false
          return
        }
        available = true
        error = ''
        done(response)
      })
    } catch (e) {
      if (captureActive || revision !== generation || method === 'snapshot' && readRevision !== snapshotReadRevision)
        return
      available = false
      pending = false
      error = String(e)
      poll.stop()
      readyRetry.stop()
      submissionJson = ''
      preparing = false
    }
  }
  // Refresh owner observations without creating or cancelling operations.
  function refresh(): bool {
    if (captureActive)
      return false
    var revision = generation
    snapshotReadRevision++
    invoke('snapshot', [], revision, function (response) {
      snapshot = response
    })
    return true
  }
  // Retry only rejected readiness responses, then observe one accepted ID forever.
  function request(payload: var): bool {
    if (captureActive || pending)
      return false
    poll.stop()
    operationId = ''
    requestError = null
    pending = true
    preparing = false
    generation++
    submissionJson = JSON.stringify(payload)
    submissionDeadline = Date.now() + readyTimeout
    submitRequest()
    return true
  }
  // Reusing a rejected payload is safe; an accepted submission is never repeated.
  function submitRequest(): void {
    if (captureActive || !pending || !submissionJson)
      return
    if (preparing && Date.now() >= submissionDeadline) {
      pending = false
      preparing = false
      submissionJson = ''
      return
    }
    invoke('request', [submissionJson], generation, function (response) {
      if (!response.ok || !response.operationId) {
        requestError = response.error || null
        error = response.error ? response.error.message : 'Project request refused.'
        if (!response.operationId && response.error && response.error.code === 'OWNER_NOT_READY' && Date.now() < submissionDeadline) {
          preparing = true
          readyRetry.restart()
          return
        }
        pending = false
        preparing = false
        submissionJson = ''
        return
      }
      readyRetry.stop()
      submissionJson = ''
      preparing = false
      requestError = null
      observeOperation(response.operationId)
    })
  }
  // Reconnect to a known operation; disconnecting this item never cancels the owner.
  function observeOperation(id: string): bool {
    if (captureActive || !id)
      return false
    readyRetry.stop()
    submissionJson = ''
    preparing = false
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
    id: readyRetry
    interval: client.pollInterval
    onTriggered: client.submitRequest()
  }
  Timer {
    id: poll
    interval: client.pollInterval
    onTriggered: client.readOperation()
  }
}
