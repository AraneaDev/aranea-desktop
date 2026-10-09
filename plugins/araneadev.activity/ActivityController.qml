// Persistent activity queue; view closure never owns or cancels accepted work.
pragma ComponentBehavior: Bound
import QtQuick
import "ActivityLogic.js" as Logic
import "ActivityOperations.js" as Operations

Item {
  id: controller
  // Replaceable store, process and compositor boundary.
  property var runtime: null
  // Inert captures refuse all I/O and invalidate callbacks.
  property bool captureActive: false
  // Owner lifetime is never restored from durable state.
  property string ownerId: 'activity-' + Date.now() + '-' + Math.random().toString(16).slice(2)
  // Injected wall clock; tick age additionally bounds stale cached reads.
  property var clock: function () {
    return Date.now()
  }
  // Last validated durable snapshot remains visible on read errors.
  property var storeState: ({
      schemaVersion: 1,
      revision: 0,
      tasks: [],
      sessions: []
    })
  // Independent read generation rejects overlapping stale responses.
  property int readGeneration: 0
  // Successful initial snapshot is required before accepting actions.
  property bool ready: false
  // Durable snapshot errors are visible without clearing tasks.
  property var error: null
  // Accepted records live here, independently of client observers.
  property var operations: []
  // One dispatch or resume observation transaction at a time.
  property var queue: []
  // Prevent recursive drain and overlapping mutation/launch submissions.
  property bool busy: false
  // Guards overlapping native proof polls.
  property bool observing: false
  // Stable operation ID suffix, unique within this owner.
  property int generation: 0
  // Store polling is bounded and independent of any panel visibility.
  property int pollInterval: 5000
  // Accepted resume observation is bounded without terminating applications.
  property int operationTimeout: 10000
  // Accumulated timer time prevents wall-clock rollback extending cached freshness.
  property double elapsedSinceRead: 0
  // Snapshot receipt wall clock anchors monotonically increasing cache age.
  property double readAt: 0
  // Pending attention is owner-local and never restored or replayed after restart.
  property var notificationQueue: []
  // Policy ownership is independent of successful store-read generations.
  property int notificationGeneration: 0
  // Each occurrence has a unique token even if a state/blocker key recurs later.
  property int nextNotificationId: 0
  // Delivery acceptance is separate from an unobservable desktop popup.
  property var notificationStatus: ({
      status: 'unavailable',
      message: 'No notification delivery observed.'
    })
  // Public projection changed without transferring operation ownership.
  signal snapshotChanged
  // Accepted operation progress for read-only consumers.
  signal operationChanged(var operation)
  onCaptureActiveChanged: {
    readGeneration++
    notificationGeneration++
    if (captureActive) {
      notificationQueue = []
      notificationTimer.stop()
      queue = []
      busy = false
      observing = false
    }
  }
  // Structured actionable failures are shared by IPC and panel clients.
  function failure(code: string, message: string): var {
    return {
      code: code,
      message: message,
      recovery: 'Refresh activity; inspect the retained operation before submitting another action.'
    }
  }
  // Public state exposes reported facts and owner uncertainty separately.
  function snapshot(): var {
    var view = Logic.project(storeState, Math.max(clock(), readAt + elapsedSinceRead), null)
    return Object.assign({}, view, {
      ownerId: ownerId,
      availability: {
        ready: ready,
        owner: !captureActive
      },
      error: error,
      notifications: notificationStatus,
      operations: operations
    })
  }
  // New reads supersede old results but do not invalidate operation observers.
  function refresh(): bool {
    if (captureActive || !runtime)
      return false
    var revision = ++readGeneration
    runtime.readStore(function (response) {
      if (captureActive || revision !== readGeneration)
        return
      if (!response || !response.ok || !response.state) {
        error = response && response.error || failure('STORE_UNAVAILABLE', 'Activity store unavailable.')
      } else {
        var previous = ready ? storeState : null
        storeState = response.state
        consumeNotifications(previous, storeState)
        ready = true
        error = null
        readAt = clock()
        elapsedSinceRead = 0
      }
      snapshotChanged()
    })
    return true
  }
  // Successful snapshots preserve outstanding decisions only for the current identity.
  function consumeNotifications(previous: var, current: var): void {
    notificationQueue = notificationQueue.filter(function (notice) {
      return current.tasks.some(function (task) {
        return Logic.notificationKey(task) === notice.key
      })
    }).map(function (notice) {
      var task = current.tasks.filter(function (row) {
        return row.taskId === notice.taskId
      })[0]
      return Object.assign({}, notice, {
        body: Logic.notificationText(task.description || task.summary || 'Agent task needs attention', 512)
      })
    })
    var transitions = Logic.notificationTransitions(previous, current, false)
    if (!transitions.length || !runtime || typeof runtime.readNotificationPolicy !== 'function')
      return
    var tokens = [], lifetime = notificationGeneration
    transitions.forEach(function (notice) {
      var token = ++nextNotificationId
      tokens.push(token)
      notificationQueue = notificationQueue.filter(function (old) {
        return old.taskId !== notice.taskId
      }).concat([Object.assign({}, notice, {
          token: token,
          phase: 'policy'
        })])
    })
    runtime.readNotificationPolicy(function (policy) {
      if (captureActive || lifetime !== notificationGeneration)
        return
      var pending = notificationQueue.filter(function (notice) {
        return tokens.indexOf(notice.token) >= 0 && notice.phase === 'policy'
      })
      if (!pending.length)
        return
      var allowed = policy && policy.available && !policy.suppressed
      notificationQueue = notificationQueue.filter(function (notice) {
        return allowed || tokens.indexOf(notice.token) < 0 || notice.phase !== 'policy'
      }).map(function (notice) {
        return tokens.indexOf(notice.token) >= 0 && notice.phase === 'policy' ? Object.assign({}, notice, {
          phase: 'queued'
        }) : notice
      })
      if (!allowed) {
        notificationStatus = {
          status: policy && policy.available ? 'suppressed' : 'unavailable',
          message: 'Attention consumed; no backlog will be replayed.'
        }
        return
      }
      if (!notificationTimer.running)
        notificationTimer.start()
    })
  }
  // Final policy checks retain their tokens until consumed, preventing late duplicate replies.
  function flushNotifications(): void {
    notificationTimer.stop()
    if (captureActive || !runtime)
      return
    var tokens = notificationQueue.filter(function (notice) {
      return notice.phase === 'queued'
    }).map(function (notice) {
      return notice.token
    })
    if (!tokens.length)
      return
    var lifetime = notificationGeneration
    notificationQueue = notificationQueue.map(function (notice) {
      return tokens.indexOf(notice.token) >= 0 ? Object.assign({}, notice, {
        phase: 'delivery'
      }) : notice
    })
    runtime.readNotificationPolicy(function (policy) {
      if (captureActive || lifetime !== notificationGeneration)
        return
      var pending = notificationQueue.filter(function (notice) {
        return tokens.indexOf(notice.token) >= 0 && notice.phase === 'delivery' && storeState.tasks.some(function (task) {
          return Logic.notificationKey(task) === notice.key
        })
      })
      notificationQueue = notificationQueue.filter(function (notice) {
        return tokens.indexOf(notice.token) < 0
      })
      if (!pending.length)
        return
      if (!policy || !policy.available || policy.suppressed) {
        notificationStatus = {
          status: policy && policy.available ? 'suppressed' : 'unavailable',
          message: 'Attention consumed; no backlog will be replayed.'
        }
        return
      }
      pending.forEach(function (notice) {
        runtime.notifyAttention(notice, function (result) {
          if (captureActive || lifetime !== notificationGeneration)
            return
          notificationStatus = {
            status: result && result.accepted ? 'accepted' : 'unavailable',
            message: 'Desktop display is not observed. Open Agents Tasks to inspect activity.'
          }
          if (result && result.activated)
            activateNotification(notice.taskId)
        })
      })
    })
  }
  // Notification activation is inspection only; fresh lookup never resumes or answers.
  function activateNotification(taskId: string): void {
    if (captureActive || !runtime || !Logic.validId(taskId))
      return
    var revision = ++readGeneration
    runtime.readStore(function (response) {
      if (captureActive || revision !== readGeneration)
        return
      if (!response || !response.ok || !response.state || !response.state.tasks.some(function (task) {
        return task.taskId === taskId
      })) {
        notificationStatus = {
          status: 'unavailable',
          message: 'Task is no longer available. Open Agents Tasks to inspect current activity.'
        }
        return
      }
      var previous = ready ? storeState : null
      storeState = response.state
      ready = true
      error = null
      readAt = clock()
      elapsedSinceRead = 0
      consumeNotifications(previous, storeState)
      snapshotChanged()
      runtime.showTask(taskId, function (result) {
        if (!captureActive)
          notificationStatus = result && result.ok ? {
            status: 'requested',
            message: 'Task inspection requested; desktop opening is unconfirmed.'
          } : {
            status: 'unavailable',
            message: 'Agents widget is unavailable. Add Agents to the bar or run aranea agents list.'
          }
      })
    })
  }
  Timer {
    id: notificationTimer
    interval: 2000
    onTriggered: controller.flushNotifications()
  }
  // Parse a single strict request; strings never become executable input.
  function requestJSON(json: string): var {
    var payload = null
    try {
      payload = JSON.parse(json)
    } catch (e) {}
    return request(payload)
  }
  // Accepted IDs are retained before asynchronous work starts.
  function request(payload: var): var {
    if (payload && payload.action === 'dismiss')
      return {
        ok: false,
        operationId: null,
        error: failure('INVALID_REQUEST', 'Use the explicit dismissal endpoint.')
      }
    return enqueue(payload)
  }
  // UI dismissal uses the same owner queue, with store-authoritative liveness refusal.
  function dismiss(taskId: string): var {
    return enqueue({
      action: 'dismiss',
      taskId: taskId
    })
  }
  // Internal actions share acceptance, retention and exactly one mutation transaction.
  function enqueue(payload: var): var {
    if (captureActive)
      return {
        ok: false,
        operationId: null,
        error: failure('INERT_MODE', 'Inert activity fixture.')
      }
    if (!ready) {
      refresh()
      return {
        ok: false,
        operationId: null,
        error: failure('OWNER_NOT_READY', 'Activity owner is reading its initial snapshot.')
      }
    }
    if (!runtime || !runtime.sessionId)
      return {
        ok: false,
        operationId: null,
        error: failure('DEPENDENCY_MISSING', 'Activity runtime unavailable. Activate the activity plugin.')
      }
    invalidateSubmissions()
    var task = payload && storeState.tasks.filter(function (row) {
      return row.taskId === payload.taskId
    })[0]
    var result = Operations.request(operations, payload, ownerId + '-' + (++generation), ownerId, task ? (payload.action === 'dismiss' ? task.taskId : task.provider + ':' + task.providerSessionId) : '')
    if (!result.ok)
      return result
    if (!task)
      return {
        ok: false,
        operationId: null,
        error: failure('TASK_NOT_FOUND', 'The task is no longer retained.')
      }
    if (!result.reused) {
      var op = Object.assign({}, result.operation, {
        task: task,
        priorEpoch: task.producerEpoch,
        desktopId: runtime.sessionId,
        acceptedAt: clock(),
        attempt: 1
      })
      operations = operations.concat([op])
      queue = queue.concat([op.id])
      operationChanged(op)
      Qt.callLater(drain)
    }
    return {
      ok: true,
      operationId: result.operationId,
      ownerId: ownerId,
      error: null
    }
  }
  // Read-only lookup never restarts an observer or repeats dispatch.
  function operation(id: string): var {
    return operations.filter(function (op) {
      return op.id === id
    })[0] || {
      error: failure('OPERATION_LOST', 'This owner does not retain that operation. Accepted work may still be running.')
    }
  }
  // Publish a copied operation so consumers receive progress reliably.
  function publish(op: var): void {
    operations = operations.map(function (old) {
      return old.id === op.id ? op : old
    })
    operationChanged(op)
    snapshotChanged()
  }
  // Only current owner/desktop callbacks can publish action evidence.
  function current(id: string, attempt: var): bool {
    var op = operation(id)
    return !captureActive && op.id && op.state !== 'completed' && op.ownerId === ownerId && (attempt === undefined || op.attempt === attempt) && runtime && op.desktopId === runtime.sessionId
  }
  // Submission ownership outlives an observation deadline but never its desktop/attempt.
  function submissionCurrent(id: string, attempt: int): bool {
    var op = operation(id)
    return !captureActive && op.id && op.submissionPending === true && op.ownerId === ownerId && op.attempt === attempt && runtime && op.desktopId === runtime.sessionId
  }
  // Desktop loss invalidates evidence but cannot prove that a submitted provider never started.
  function invalidateSubmissions(): void {
    if (!runtime || captureActive)
      return
    operations.filter(function (op) {
      return (op.submissionPending || op.submissionUnconfirmed) && op.desktopId !== runtime.sessionId && (!op.error || op.error.code !== 'OPERATION_LOST')
    }).forEach(function (op) {
      var problem = failure('OPERATION_LOST', 'The desktop lifetime changed while launch acceptance was unresolved. Inspect running terminals; this retained session will not be submitted again.')
      publish(Object.assign({}, op, {
        submissionPending: true,
        submissionUnconfirmed: true,
        error: problem
      }))
      if (op.state !== 'completed')
        finish(op.id, 'partial', problem, null)
    })
  }
  // Complete a navigation request without changing the reported task lifecycle.
  function finish(id: string, outcome: string, problem: var, steps: var): void {
    var op = operation(id)
    if (!op.id || op.state === 'completed')
      return
    publish(Object.assign({}, op, {
      state: 'completed',
      outcome: outcome,
      error: problem || null,
      steps: steps || op.steps
    }))
    if (queue[0] === id) {
      queue = queue.slice(1)
      busy = false
      observing = false
      Qt.callLater(drain)
    }
    var completed = operations.filter(function (row) {
      return row.state === 'completed' && !row.submissionPending && !row.submissionUnconfirmed
    })
    var remove = completed.slice(0, Math.max(0, completed.length - 100)).map(function (row) {
      return row.id
    })
    operations = operations.filter(function (row) {
      return remove.indexOf(row.id) < 0
    })
  }
  // Serialize preparation and launch; observing may outlive every client.
  function drain(): void {
    if (captureActive || busy || !queue.length)
      return
    var id = queue[0], op = operation(id), attempt = op.attempt
    busy = true
    if (!current(id, attempt)) {
      finish(id, 'partial', failure('OPERATION_LOST', 'The desktop lifetime changed.'), null)
      return
    }
    publish(Object.assign({}, op, {
      state: 'observing',
      deadline: clock() + operationTimeout,
      remaining: operationTimeout
    }))
    if (op.action === 'dismiss') {
      readGeneration++
      runtime.dismiss(op.taskId, function (response) {
        if (!current(id, attempt))
          return
        readGeneration++
        if (response && response.ok && response.state && !response.state.tasks.some(function (task) {
          return task.taskId === op.taskId
        })) {
          storeState = response.state
          readAt = clock()
          elapsedSinceRead = 0
          finish(id, 'observed', null, [
            {
              role: 'dismiss',
              status: 'observed'
            }
          ])
        } else
          finish(id, 'failed', response && response.error || failure('DISMISS_UNCONFIRMED', 'Store removal could not be confirmed.'), null)
      })
      return
    }
    if (op.reobserving) {
      pollResume()
      return
    }
    if (op.action === 'focus') {
      runtime.focusSession(op.task, Logic.sessionFor(storeState, op.task), function (response) {
        if (!current(id, attempt))
          return
        finish(id, response && response.status === 'observed' ? 'observed' : 'failed', response && response.ok ? null : failure(response && response.code || 'OWNERSHIP_UNCONFIRMED', response && response.message || 'Session ownership is unconfirmed. Open its checkout or explicitly reopen the session.'), [
          {
            role: 'hosting-terminal',
            status: response && response.status || 'failed'
          }
        ])
      })
      return
    }
    if (op.task.association.status !== 'registered') {
      finish(id, 'failed', failure('PROJECT_UNASSIGNED', 'Explicitly register or restore the exact checkout before navigation.'), null)
      return
    }
    var nativeSession = Logic.sessionFor(storeState, op.task)
    if (op.action === 'reopen' && (!Logic.resumeCommand(op.task) || !nativeSession || !nativeSession.provenance || !nativeSession.provenance.commandHash || !(nativeSession.nativeMetadata && (nativeSession.nativeMetadata.observedHooks || []).indexOf('SessionStart') >= 0))) {
      finish(id, 'failed', failure('RESUME_UNAVAILABLE', 'This provider/session identity does not support fixed CLI resume.'), null)
      return
    }
    runtime.prepare(op.task, op.action === 'reopen', function (preparation) {
      if (!current(id, attempt))
        return
      if (!preparation || !preparation.ok) {
        finish(id, preparation && preparation.outcome || 'failed', preparation && preparation.error || failure('PROJECT_UNAVAILABLE', 'Checkout workspace preparation failed.'), preparation && preparation.steps)
        return
      }
      if (op.action === 'open-checkout') {
        finish(id, preparation.outcome || 'observed', null, preparation.steps)
        return
      }
      publish(Object.assign({}, operation(id), {
        submissionPending: true,
        submissionUnconfirmed: false
      }))
      runtime.launch(op.task, preparation, function (response) {
        if (!submissionCurrent(id, attempt))
          return
        var retained = operation(id), observationEnded = retained.state === 'completed'
        if (!response || !response.ok) {
          var uncertain = !response || response.submissionUnconfirmed === true
          var problem = failure(uncertain ? 'LAUNCH_UNCONFIRMED' : response.code || 'LAUNCH_FAILED', uncertain ? 'Launch submission may have started an agent, but acceptance could not be read. Inspect the retained operation and running terminals; this session will not be submitted again.' : response.message || 'Resume launch failed.')
          publish(Object.assign({}, retained, {
            submissionPending: uncertain,
            submissionUnconfirmed: uncertain,
            error: problem
          }))
          if (observationEnded)
            publish(Object.assign({}, operation(id), {
              outcome: uncertain ? 'partial' : 'failed'
            }))
          else
            finish(id, uncertain ? 'partial' : 'failed', problem, null)
          return
        }
        publish(Object.assign({}, retained, {
          submissionPending: false,
          submissionUnconfirmed: false,
          launchIdentity: response.identity,
          spec: response.spec,
          baseline: response.baseline,
          preparation: preparation
        }))
        // A late acceptance is inspectable and explicitly reobservable, never automatic placement.
        if (observationEnded)
          return
        runtime.observeTerminal(operation(id), function (terminal) {
          if (!current(id, attempt))
            return
          publish(Object.assign({}, operation(id), {
            terminal: terminal
          }))
          pollResume()
        })
      })
    })
  }
  // Fresh read-only native evidence is the only route to a resumed claim.
  function pollResume(): void {
    if (captureActive || observing || !busy || !queue.length)
      return
    var id = queue[0], op = operation(id), attempt = op.attempt
    if (op.action !== 'reopen' || !op.launchIdentity || !current(id, attempt))
      return
    observing = true
    runtime.observeResume(op, function (response) {
      if (!current(id, attempt))
        return
      observing = false
      var next = Operations.observe(operation(id), response && Object.prototype.hasOwnProperty.call(response, 'terminal') ? response.terminal : op.terminal, response && response.native, false)
      if (next.state === 'completed')
        finish(id, next.outcome, null, next.steps)
      else
        publish(next)
    })
  }
  // Explicit reobservation reuses identity and ID; no preparation, move or launch.
  function reobserve(id: string): var {
    var op = operation(id)
    if (captureActive)
      return {
        ok: false,
        operationId: id,
        error: failure('INERT_MODE', 'Inert activity fixture.')
      }
    if (op.id && op.ownerId === ownerId && runtime && op.desktopId === runtime.sessionId && (op.submissionPending || op.submissionUnconfirmed))
      return {
        ok: false,
        operationId: id,
        error: failure('SUBMISSION_PENDING', 'Launch acceptance is unresolved. Inspect this operation and running terminals; another launch will not be submitted.')
      }
    if (!op.id || op.ownerId !== ownerId || !runtime || op.desktopId !== runtime.sessionId || !op.launchIdentity || op.action !== 'reopen')
      return {
        ok: false,
        operationId: id,
        error: failure('OPERATION_LOST', 'Accepted launch identity is unavailable in this desktop lifetime.')
      }
    if (op.state !== 'completed')
      return {
        ok: true,
        operationId: id,
        ownerId: ownerId,
        error: null
      }
    if (op.outcome !== 'partial')
      return {
        ok: false,
        operationId: id,
        error: failure('INVALID_REQUEST', 'Only partial accepted resumes need reobservation.')
      }
    var attempt = op.attempt + 1
    publish(Object.assign({}, op, {
      attempt: attempt,
      state: 'accepted',
      outcome: null,
      error: null,
      reobserving: true,
      validating: true,
      remaining: operationTimeout
    }))
    runtime.validateReobserve(op, function (valid) {
      if (!current(id, attempt))
        return
      if (!valid) {
        finish(id, 'partial', failure('OPERATION_LOST', 'The retained launch process can no longer be proven.'), null)
        return
      }
      publish(Object.assign({}, operation(id), {
        validating: false
      }))
      queue = queue.concat([id])
      Qt.callLater(drain)
    })
    return {
      ok: true,
      operationId: id,
      ownerId: ownerId,
      error: null
    }
  }
  Timer {
    interval: controller.pollInterval
    repeat: true
    running: !controller.captureActive
    onTriggered: controller.refresh()
  }
  Timer {
    interval: 100
    repeat: true
    running: !controller.captureActive
    onTriggered: {
      controller.elapsedSinceRead += interval
      controller.invalidateSubmissions()
      controller.operations.filter(function (op) {
        return op.validating && op.state !== 'completed'
      }).forEach(function (op) {
        if (op.remaining <= interval || op.desktopId !== controller.runtime.sessionId)
          controller.finish(op.id, 'partial', controller.failure('OPERATION_LOST', 'Retained launch proof is unavailable.'), null)
        else
          controller.publish(Object.assign({}, op, {
            remaining: op.remaining - interval
          }))
      })
      if (controller.busy && controller.queue.length) {
        var id = controller.queue[0], op = controller.operation(id)
        if (!controller.current(id))
          controller.finish(id, 'partial', controller.failure('OPERATION_LOST', 'Desktop lifetime changed; accepted work remains unconfirmed.'), null)
        else if (op.remaining <= interval || controller.clock() >= op.deadline) {
          if (op.action === 'reopen' && op.launchIdentity) {
            var next = Operations.observe(op, op.terminal, null, true)
            controller.finish(id, 'partial', next.error, next.steps)
          } else
            controller.finish(id, 'partial', controller.failure('OBSERVATION_TIMEOUT', 'The accepted action remains unconfirmed.'), null)
        } else {
          controller.publish(Object.assign({}, op, {
            remaining: op.remaining - interval
          }))
          controller.pollResume()
        }
      }
      controller.snapshotChanged()
    }
  }
}
