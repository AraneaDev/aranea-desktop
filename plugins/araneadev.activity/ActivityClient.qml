// Independent IPC observer; accepted owner work never belongs to this item.
import QtQuick
import "../araneadev.projects" as Projects

Item {
  id: client
  // Inert captures refuse I/O and invalidate all pending callbacks.
  property bool captureActive: false
  // Latest owner snapshot is retained across errors.
  property var snapshot: ({
      tasks: [],
      operations: []
    })
  // Transport reachability is separate from operation outcome.
  property bool available: false
  // Structured errors retain actionable domain codes.
  property var error: null
  // True only while submitting or observing accepted work.
  property bool pending: false
  // Accepted ID survives disconnect, closure and explicit reconnection.
  property string operationId: ''
  // Accepted owner's lifetime prevents restart ambiguity.
  property string ownerId: ''
  // Last observed operation can be rendered without polling again.
  property var currentOperation: null
  // Submission and snapshot generations are deliberately independent.
  property int generation: 0
  // Later reads supersede earlier reads without cancelling operation observation.
  property int snapshotGeneration: 0
  // Only an explicit OWNER_NOT_READY refusal may reuse this payload.
  property string submissionJson: ''
  // Bounded initial readiness retries stop before any acceptance.
  property double submissionDeadline: 0
  // Polling is presentation observation only.
  property int pollInterval: 250
  // Fixed transport executable; fixtures replace the runner rather than the owner.
  property string ipcPath: 'omarchy-shell'
  // Reuse the existing short-lived process collector.
  property var runner: function (argv, done) {
    transport.run(['timeout', '2s'].concat(argv), '', done)
  }
  // Accepted operation progress for read-only consumers.
  signal operationChanged(var operation)
  Projects.ProjectRuntime {
    id: transport
    captureActive: client.captureActive
  }
  onCaptureActiveChanged: {
    generation++
    snapshotGeneration++
    poll.stop()
    retry.stop()
    pending = false
    submissionJson = ''
  }
  // IPC decoding rejects stale callbacks and surfaces uncertain transport results.
  function invoke(method: string, args: var, done: var): void {
    if (captureActive)
      return
    var revision = generation, read = snapshotGeneration
    var complete = function (code, output, diagnostics) {
      if (client.captureActive || revision !== client.generation || method === 'snapshot' && read !== client.snapshotGeneration)
        return
      var result = null
      try {
        result = JSON.parse(output)
      } catch (e) {}
      if (code !== 0 || !result || typeof result !== 'object') {
        client.available = false
        client.error = {
          code: 'OWNER_UNAVAILABLE',
          message: diagnostics || 'Activity owner unavailable. Reconnect to the accepted operation.',
          recovery: 'Reconnect without resubmitting accepted work.'
        }
        if (method !== 'snapshot') {
          client.pending = false
          client.submissionJson = ''
          poll.stop()
          retry.stop()
        }
        return
      }
      client.available = true
      client.error = null
      done(result)
    }
    try {
      runner([ipcPath, 'aranea.activity', method].concat(args || []), complete)
    } catch (e) {
      complete(1, '', String(e))
    }
  }
  // Reading activity never changes accepted operation identity.
  function refresh(): bool {
    if (captureActive)
      return false
    snapshotGeneration++
    invoke('snapshot', [], function (response) {
      snapshot = response
    })
    return true
  }
  // A deliberate new user action starts a new submission; transport ambiguity never retries.
  function request(payload: var): bool {
    if (captureActive || pending)
      return false
    generation++
    operationId = ''
    ownerId = ''
    currentOperation = null
    submissionJson = JSON.stringify(payload)
    submissionDeadline = Date.now() + 5000
    pending = true
    submitRequest()
    return true
  }
  // The exact payload is reused only following an explicit preacceptance readiness refusal.
  function submitRequest(): void {
    retry.stop()
    if (captureActive || !submissionJson || !pending)
      return
    if (Date.now() >= submissionDeadline) {
      pending = false
      submissionJson = ''
      return
    }
    invoke('request', [submissionJson], function (response) {
      if (response.ok && response.operationId) {
        submissionJson = ''
        operationId = response.operationId
        ownerId = response.ownerId || ''
        readOperation()
      } else if (!response.operationId && response.error && response.error.code === 'OWNER_NOT_READY') {
        error = response.error
        retry.restart()
      } else {
        pending = false
        submissionJson = ''
        error = response.error || {
          code: 'INVALID_RESPONSE',
          message: 'Activity request refused.'
        }
      }
    })
  }
  // Explicit dismissal uses the owner's serialized store mutation and ordinary observation.
  function dismiss(taskId: string): bool {
    if (captureActive || pending)
      return false
    generation++
    operationId = ''
    ownerId = ''
    currentOperation = null
    pending = true
    invoke('dismiss', [taskId], function (response) {
      if (!response.ok || !response.operationId) {
        pending = false
        error = response.error
        return
      }
      operationId = response.operationId
      ownerId = response.ownerId || ''
      readOperation()
    })
    return true
  }
  // Reconnect is strictly read-only, including after a partial operation.
  function reconnect(id: var): bool {
    if (captureActive || !(id || operationId))
      return false
    if (id && id !== operationId) {
      operationId = id
      ownerId = ''
    }
    generation++
    submissionJson = ''
    retry.stop()
    pending = true
    readOperation()
    return true
  }
  // Explicit observation-only action retains the accepted ID and never requests reopen.
  function reobserve(): bool {
    if (captureActive || pending || !operationId)
      return false
    pending = true
    invoke('reobserve', [operationId], function (response) {
      if (!response.ok || response.operationId !== operationId || ownerId && response.ownerId !== ownerId) {
        pending = false
        error = response.error || {
          code: 'OPERATION_LOST',
          message: 'Accepted owner lifetime changed.'
        }
        return
      }
      readOperation()
    })
    return true
  }
  // Operation IDs and owner lifetimes must match before progress is published.
  function readOperation(): void {
    if (captureActive || !operationId)
      return
    var id = operationId
    invoke('operation', [id], function (op) {
      if (id !== operationId)
        return
      if (op.id !== id || ownerId && op.ownerId !== ownerId) {
        pending = false
        error = op.error || {
          code: 'OPERATION_LOST',
          message: 'Accepted operation is no longer retained by this owner.'
        }
        return
      }
      ownerId = op.ownerId
      currentOperation = op
      pending = op.state !== 'completed'
      operationChanged(op)
      if (pending)
        poll.restart()
    })
  }
  Timer {
    id: poll
    interval: client.pollInterval
    onTriggered: client.readOperation()
  }
  Timer {
    id: retry
    interval: client.pollInterval
    onTriggered: client.submitRequest()
  }
}
