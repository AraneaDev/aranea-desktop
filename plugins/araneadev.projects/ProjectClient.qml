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
  // A sent request may already be accepted; cancellation only applies between rejected retries.
  property bool submissionInFlight: false
  // Only an explicit readiness refusal between sends is safe to cancel.
  readonly property bool canCancelPreparation: !captureActive && preparing && pending && !submissionInFlight && !operationId && !acceptanceUnknown && !!requestError && requestError.code === 'OWNER_NOT_READY'
  // Stop only known-unaccepted local retries; keep the original diagnostic target.
  function cancelPreparation(): bool {
    if (!canCancelPreparation)
      return false
    generation++
    readyRetry.stop()
    submissionJson = ''
    preparing = false
    pending = false
    return true
  }
  // Bound readiness retries; reaching this deadline leaves the request rejected.
  property int readyTimeout: 5000
  // Original serialized request is immutable throughout rejected-only retries.
  property string submissionJson: ''
  // Absolute preparation deadline does not extend on each readiness refusal.
  property real submissionDeadline: 0
  // Operation being observed, without owning launch lifetime.
  property string operationId: ''
  // Submission busy ends at acknowledgement; observing an accepted owner operation does not block a later explicit activation.
  readonly property bool submitting: pending && !operationId
  // Immutable start/recovery activation retained through readiness and transport uncertainty.
  property string activationId: ''
  // Exact environment accepted or requested by the current environment operation.
  property string environmentId: ''
  // Unknown acceptance is recoverable only through the read-only activation lookup.
  property bool acceptanceUnknown: false
  // Explicit new work archives uncertain identities without cancelling or replaying their owner operations.
  property var unresolvedEnvironmentActivations: []
  // Exact target remains detached from later selection/profile edits.
  property var environmentTarget: null
  // Owner session known at submission, when a current snapshot is available.
  property string environmentSession: ''
  // Separate explicit methods preserve legacy request behavior.
  property string submissionMethod: 'request'
  // Kernel UUID boundary creates a new identity only for an explicit user activation.
  property var identityRunner: function (done) {
    var process = processComponent.createObject(client, {
      command: ['cat', '/proc/sys/kernel/random/uuid'],
      completion: function (code, output) {
        done(code === 0 ? String(output).trim() : '')
      }
    })
    process.startRequested = true
    process.running = true
  }
  // Only validated launch acceptance allows the profile UI to dismiss itself.
  signal submissionAccepted(string operationId, string environmentId)
  // Only observed exact Return focus allows the existing-environment UI to dismiss itself.
  signal returnObserved(string environmentId)
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
    submissionInFlight = false
    poll.stop()
    readyRetry.stop()
    submissionJson = ''
    preparing = false
    pending = false
  }
  // Snapshot reads cannot cancel independently submitted or observed work.
  function transportFailed(method: string, message: string): void {
    available = false
    if (method !== 'snapshot')
      submissionInFlight = false
    if (method === 'startEnvironment' || method === 'recoverEnvironment') {
      acceptanceUnknown = true
      requestError = {
        code: 'ACCEPTANCE_UNKNOWN',
        message: 'Launch acceptance is unknown. Check launch status before starting again.'
      }
    }
    if (method === 'snapshot') {
      error = message
      return
    }
    // Pending observers react to both properties; never replay an earlier read error.
    error = ''
    pending = false
    error = message
    poll.stop()
    readyRetry.stop()
    submissionJson = ''
    preparing = false
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
          transportFailed(method, diagnostics || 'Project owner unavailable. Activate Aranea and retry.')
          return
        }
        available = true
        error = ''
        done(response)
      })
    } catch (e) {
      if (captureActive || revision !== generation || method === 'snapshot' && readRevision !== snapshotReadRevision)
        return
      transportFailed(method, String(e))
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
    submissionMethod = 'request'
    environmentTarget = null
    environmentId = ''
    acceptanceUnknown = false
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
    var revision = generation
    submissionInFlight = true
    invoke(submissionMethod, [submissionJson], revision, function (response) {
      submissionInFlight = false
      var environmentSubmission = submissionMethod !== 'request'
      if (environmentSubmission && (response.ok === true && (!validId(response.operationId) || !validId(response.environmentId)) || response.ok !== true && (response.operationId || response.environmentId))) {
        transportFailed(submissionMethod, 'Owner acknowledgement is incomplete. Check launch status.')
        return
      }
      if (!response.ok || !response.operationId) {
        requestError = response.error || null
        error = response.error ? response.error.message : 'Project request refused.'
        if ((submissionMethod === 'request' || submissionMethod === 'startEnvironment') && !response.operationId && response.error && response.error.code === 'OWNER_NOT_READY' && Date.now() < submissionDeadline) {
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
      if (environmentSubmission) {
        if (submissionMethod !== 'startEnvironment' && response.environmentId !== environmentTarget.environmentId) {
          transportFailed(submissionMethod, 'Owner acknowledged another environment.')
          return
        }
        environmentId = response.environmentId
        operationId = response.operationId
        acceptanceUnknown = false
        if (submissionMethod === 'startEnvironment')
          submissionAccepted(operationId, environmentId)
      }
      if (revision === generation)
        observeOperation(response.operationId)
    })
  }
  // Public acknowledgement identities must be nonempty opaque strings.
  function validId(value: var): bool {
    return typeof value === 'string' && !!value && !/[\x00-\x1f\x7f]/.test(value)
  }
  // Begin one explicit environment command without changing its target during readiness retries.
  function beginEnvironment(method: string, payload: var): bool {
    if (captureActive || submitting || acceptanceUnknown || !payload || typeof payload !== 'object')
      return false
    poll.stop()
    readyRetry.stop()
    generation++
    var revision = generation
    submissionMethod = method
    operationId = ''
    environmentId = payload.environmentId || ''
    activationId = payload.activationId || ''
    environmentTarget = JSON.parse(JSON.stringify(payload))
    environmentSession = snapshot.sessionId || ''
    acceptanceUnknown = false
    requestError = null
    error = ''
    preparing = false
    pending = true
    var submit = function () {
      if (captureActive || revision !== generation)
        return
      submissionJson = JSON.stringify(environmentTarget)
      submissionDeadline = Date.now() + readyTimeout
      submitRequest()
    }
    if (method === 'returnEnvironment' || activationId) {
      submit()
      return true
    }
    identityRunner(function (uuid) {
      if (captureActive || revision !== generation)
        return
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(uuid) || unresolvedEnvironmentActivations.some(function (row) {
        return row.activationId === 'a-' + uuid
      })) {
        pending = false
        error = 'Could not create a launch identity.'
        return
      }
      activationId = 'a-' + uuid
      environmentTarget = Object.assign({}, environmentTarget, {
        activationId: activationId
      })
      submit()
    })
    return true
  }
  // Starting a profile creates one immutable activation; owner readiness is the only retryable refusal.
  function startEnvironment(payload: var): bool {
    return beginEnvironment('startEnvironment', payload)
  }
  // Explicit uncertainty escape creates different work; a missing lookup never invokes this automatically.
  function startAnotherEnvironment(payload: var): bool {
    if (captureActive || submitting || !acceptanceUnknown || !activationId || !environmentTarget || !payload || typeof payload !== 'object' || Array.isArray(payload))
      return false
    var target = JSON.parse(JSON.stringify(payload))
    delete target.activationId
    unresolvedEnvironmentActivations = unresolvedEnvironmentActivations.concat([
      {
        activationId: activationId,
        target: JSON.parse(JSON.stringify(environmentTarget)),
        sessionId: environmentSession,
        method: submissionMethod
      }
    ])
    generation++
    poll.stop()
    readyRetry.stop()
    pending = false
    operationId = ''
    submissionJson = ''
    acceptanceUnknown = false
    return beginEnvironment('startEnvironment', target)
  }
  // Exact Return does not emit launch acceptance or run missing roles.
  function returnEnvironment(payload: var): bool {
    return beginEnvironment('returnEnvironment', payload)
  }
  // Explicit role recovery stays open and uses a new coalesced activation identity.
  function recoverEnvironment(payload: var): bool {
    return beginEnvironment('recoverEnvironment', payload)
  }
  // Compare the retained receipt to the exact target originally submitted, ignoring field order.
  function sameTarget(target: var): bool {
    return !!target && !!environmentTarget && Object.keys(target).length === Object.keys(environmentTarget).length && Object.keys(environmentTarget).every(function (key) {
      return target[key] === environmentTarget[key]
    })
  }
  // Unknown acceptance is queried explicitly; even not-found never authorizes replay.
  function checkEnvironmentActivation(): bool {
    if (captureActive || pending || !acceptanceUnknown || !activationId || !environmentTarget)
      return false
    var activation = activationId, revision = generation
    pending = true
    invoke('environmentActivation', [JSON.stringify({
        activationId: activation
      })], generation, function (response) {
      pending = false
      var op = response.operation
      if (!response.ok || !response.found || response.activationId !== activation || !validId(response.sessionId) || environmentSession && response.sessionId !== environmentSession || !op || op.id !== response.operationId || op.environmentId !== response.environmentId || op.activationId !== activation || op.sessionId !== response.sessionId || op.projectId !== environmentTarget.projectId || (submissionMethod === 'startEnvironment' ? op.checkoutId !== environmentTarget.checkoutId : op.environmentId !== environmentTarget.environmentId) || !validId(op.id) || !validId(op.environmentId) || !sameTarget(submissionMethod === 'startEnvironment' ? op.startTarget : op.recoveryTarget)) {
        requestError = {
          code: 'ACCEPTANCE_UNKNOWN',
          message: 'No matching acceptance was confirmed. The earlier launch will not be replayed.'
        }
        error = requestError.message
        return
      }
      environmentSession = response.sessionId
      operationId = response.operationId
      environmentId = response.environmentId
      acceptanceUnknown = false
      requestError = null
      if (submissionMethod === 'startEnvironment')
        submissionAccepted(operationId, environmentId)
      if (revision !== generation)
        return
      if (op.state === 'completed') {
        operationChanged(op)
        refresh()
      } else
        observeOperation(operationId)
    })
    return true
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
      if (!operation.id || operation.id !== id || environmentTarget && (operation.environmentId !== environmentId || operation.projectId !== environmentTarget.projectId)) {
        pending = false
        error = operation.error ? operation.error.message : 'Operation is unavailable.'
        return
      }
      pending = operation.state !== 'completed'
      operationChanged(operation)
      if (!pending && submissionMethod === 'returnEnvironment' && operation.environmentReturn === true && operation.outcome === 'observed' && operation.environmentId === environmentTarget.environmentId && typeof operation.sessionId === 'string' && (!environmentSession || operation.sessionId === environmentSession) && (operation.steps || []).some(function (step) {
        return step.role === 'workspace' && step.status === 'observed' && step.workspaceId === operation.workspaceId && step.workspaceId > 0
      }))
        returnObserved(environmentId)
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
