// Sole live project operation owner; consumers submit and observe this shared queue.
pragma ComponentBehavior: Bound

import QtQuick
import "../araneadev.shared" as Aranea
import "ProjectOperations.js" as Operations
import "ProjectTools.js" as Tools

Item {
  id: controller
  // Replaceable desktop boundary; clients never create another operation queue.
  property var runtime: null
  // Every external boundary refuses inert display captures.
  property bool captureActive: false
  // Validated registry state is retained on read/write failure.
  property var registry: ({
      schemaVersion: 1,
      revision: 0,
      roots: [],
      ignored: [],
      projects: []
    })
  // Accepted and retained completed owner operations, newest completion retention is bounded.
  property var operations: []
  // Retained identity evidence is distinct from freshly proven publication.
  property var bindings: []
  // Only recently verified bindings may be published as ownership.
  property var freshBindings: []
  // Latest role history survives completed-operation eviction to prevent duplicates.
  property var roleHistory: ({})
  // Global allocation/focus/launch submission queue, independent of role observation.
  property var queue: []
  // One global submission transaction runs at a time.
  property bool queueActive: false
  // Monotonic operation generation prevents stale completions from mutating state.
  property int generation: 0
  // Current desktop identity invalidates all old runtime ownership.
  property string sessionId: ''
  // Latest registry/process observation error is explicit in snapshots.
  property var error: null
  // Snapshot actual read time; no cached observation is presented as a new read.
  property var observedAt: null
  // Background refresh cannot overlap a queue's revision-sensitive writes.
  property bool refreshing: false
  // Registry helper follows the shared theme path.
  property string storePath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-store'
  // Read-only Git metadata helper validates the exact registered checkout afresh.
  property string metadataPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-discover'
  // Installed adapter/default probe never executes project applications.
  property string toolsPath: Aranea.RuntimePaths.themeRoot + '/scripts/aranea-project-tools'
  // Store injection retains (argv,done), with an optional third JSON stdin parameter.
  property var storeRunner: function (argv, done, input) {
    controller.runJson(argv, input || '', done)
  }
  // Metadata and tool probe boundaries are independently replaceable in isolated fixtures.
  property var metadataRunner: function (argv, done) {
    controller.runJson(argv, '', done)
  }
  // Probe only supported adapters and inert desktop defaults.
  property var toolsRunner: function (argv, done) {
    controller.runJson(argv, '', done)
  }
  // Per-role launch/observation deadline also covers helpers that never complete.
  property int roleTimeout: 10000
  // Active role timers are parented to this persistent owner.
  property var deadlines: ({})
  // Consumers receive state publications without taking ownership of launch processes.
  signal snapshotChanged
  // Consumers observe progress and terminal outcomes by stable operation ID.
  signal operationChanged(var operation)
  onCaptureActiveChanged: if (captureActive)
    abortPending('INERT_MODE', 'Inert project fixture.')
  // Decode JSON through the runtime's safe argv/stdin/collector transport.
  function runJson(argv: var, input: string, done: var): void {
    if (captureActive) {
      done({
        ok: false,
        error: failure('INERT_MODE', 'Inert project fixture.')
      })
      return
    }
    if (!runtime || typeof runtime.processRunner !== 'function') {
      done({
        ok: false,
        error: failure('DEPENDENCY_MISSING', 'The project process adapter is unavailable.')
      })
      return
    }
    try {
      runtime.processRunner(argv, input, function (code, output, diagnostics) {
        var response = null
        try {
          response = JSON.parse(output)
        } catch (e) {}
        done(response && (code === 0 || response.ok === false) ? response : {
          ok: false,
          error: failure('DEPENDENCY_MISSING', diagnostics || 'Project helper unavailable. Reinstall the theme and required dependencies.')
        })
      })
    } catch (e) {
      done({
        ok: false,
        error: failure('DEPENDENCY_MISSING', String(e))
      })
    }
  }
  // Stable errors include an actionable recovery hint for every refusal.
  function failure(code: string, message: string): var {
    return {
      code: code,
      message: message,
      recovery: 'Review project details and retry.'
    }
  }
  // Find a retained operation without treating missing results as successful work.
  function operation(id: string): var {
    return operations.filter(function (candidate) {
      return candidate.id === id
    })[0] || {
      ok: false,
      error: failure('OPERATION_NOT_FOUND', 'Operation unavailable; it may belong to an earlier shell session.')
    }
  }
  // Replace an operation atomically so clients observe state transitions.
  function publish(op: var): void {
    operations = operations.map(function (candidate) {
      return candidate.id === op.id ? op : candidate
    })
    if (op.state === 'completed')
      retainCompleted()
    operationChanged(op)
    snapshotChanged()
  }
  // Validate callback generation against the live session immediately before mutation.
  function current(id: string, revision: int, session: string): bool {
    syncSession()
    return !captureActive && session === sessionId && Operations.acceptsGeneration(operation(id), revision, session)
  }
  // Retain role history by exact project/checkout/role in this session.
  function roleKey(op: var, role: string): string {
    return op.projectId + '\n' + op.checkoutId + '\n' + role
  }
  // Invalidate pending work while retaining completed results and accepted launch history.
  function abortPending(code: string, message: string): void {
    queue = []
    queueActive = false
    Object.keys(deadlines).forEach(function (key) {
      deadlines[key].destroy()
    })
    deadlines = ({})
    operations.filter(function (op) {
      return op.state !== 'completed'
    }).forEach(function (op) {
      publish(Object.assign(Operations.complete(op, op.steps.concat([
        {
          role: 'operation',
          status: 'failed',
          code: code,
          message: message
        }
      ])), {
        error: failure(code, message),
        completedAt: Date.now()
      }))
    })
    retainCompleted()
  }
  // A shell or compositor session change never reuses old bindings or callbacks.
  function syncSession(): void {
    var next = runtime && runtime.sessionId || ''
    if (next === sessionId)
      return
    if (sessionId)
      abortPending('SESSION_CHANGED', 'The desktop session changed. Open the project again.')
    sessionId = next
    bindings = []
    freshBindings = []
    roleHistory = ({})
    snapshotChanged()
  }
  // Snapshot registry objects plus explicitly timestamped fresh runtime observations.
  function snapshot(): var {
    if (!captureActive)
      syncSession()
    var live = !captureActive && runtime ? runtime.snapshot() : {
      available: false
    }
    var fresh = freshBindings.filter(function (binding) {
      return binding.sessionId === sessionId && Date.now() - binding.evidence.verifiedAt < 2000
    })
    return {
      sessionId: sessionId,
      observedAt: observedAt,
      availability: {
        compositor: live.available === true,
        owner: !captureActive,
        registry: !error,
        error: error
      },
      projects: registry.projects,
      bindings: fresh,
      operations: operations
    }
  }
  // Refresh the authoritative compositor or a synchronous isolated fixture.
  function readDesktop(done: var): void {
    if (captureActive)
      return
    if (!runtime) {
      done({
        available: false,
        windows: [],
        workspaces: []
      })
      return
    }
    if (typeof runtime.refreshSnapshot === 'function')
      runtime.refreshSnapshot(done)
    else
      done(runtime.snapshot())
  }
  // Revalidate all retained ownership before role decisions or consumer publication.
  function validate(done: var): void {
    if (captureActive)
      return
    if (!runtime || typeof runtime.validateBindings !== 'function') {
      freshBindings = []
      done({
        bindings: [],
        missing: []
      })
      return
    }
    runtime.validateBindings(bindings, function (proof) {
      if (captureActive)
        return
      syncSession()
      if (!proof)
        proof = {
          bindings: [],
          missing: []
        }
      freshBindings = (proof.bindings || []).map(function (binding) {
        return Object.assign({}, binding, {
          evidence: Object.assign({}, binding.evidence, {
            verifiedAt: Date.now()
          })
        })
      })
      bindings = bindings.map(function (binding) {
        return freshBindings.filter(function (fresh) {
          return fresh.projectId === binding.projectId && fresh.checkoutId === binding.checkoutId && fresh.role === binding.role && fresh.address === binding.address && fresh.pid === binding.pid && fresh.evidence.startTime === binding.evidence.startTime
        })[0] || binding
      })
      done({
        bindings: freshBindings,
        missing: proof.missing || []
      })
    })
  }
  // Refresh inspections only when no revision-sensitive global transaction is running.
  function refresh(): bool {
    if (captureActive || refreshing || queueActive)
      return false
    syncSession()
    refreshing = true
    var session = sessionId
    invoke(storeRunner, [storePath, 'snapshot'], function (response) {
      if (captureActive || session !== sessionId) {
        refreshing = false
        return
      }
      if (response && response.ok && response.state) {
        registry = response.state
        error = null
      } else
        error = response && response.error || failure('REGISTRY_UNAVAILABLE', 'Project registry unavailable.')
      readDesktop(function (data) {
        validate(function (proof) {
          refreshing = false
          observedAt = data.observedAt || null
          snapshotChanged()
          drain()
        })
      })
    }, '')
    return true
  }
  // Call an injected helper safely; capture guard precedes every store/process boundary.
  function invoke(runner: var, argv: var, done: var, input: string): void {
    if (captureActive)
      return
    try {
      runner(argv, done, input)
    } catch (e) {
      done({
        ok: false,
        error: failure('DEPENDENCY_MISSING', String(e))
      })
    }
  }
  // Validate public payloads before submission, including contradictory role actions.
  function validPayload(payload: var): bool {
    if (!payload || typeof payload !== 'object' || Array.isArray(payload))
      return false
    var fields = ['projectId', 'checkoutId', 'separate', 'useCurrentWorkspace', 'newWindowRole', 'retryRole']
    if (Object.keys(payload).some(function (key) {
      return fields.indexOf(key) < 0
    }))
      return false
    if (typeof payload.projectId !== 'string' || !payload.projectId || /[\x00-\x1f\x7f]/.test(payload.projectId))
      return false
    if (payload.checkoutId !== undefined && (typeof payload.checkoutId !== 'string' || !payload.checkoutId || /[\x00-\x1f\x7f]/.test(payload.checkoutId)))
      return false
    if (payload.separate !== undefined && typeof payload.separate !== 'boolean')
      return false
    if (payload.useCurrentWorkspace !== undefined && typeof payload.useCurrentWorkspace !== 'boolean')
      return false
    if (payload.newWindowRole !== undefined && ['editor', 'terminal'].indexOf(payload.newWindowRole) < 0)
      return false
    if (payload.retryRole !== undefined && ['editor', 'terminal'].indexOf(payload.retryRole) < 0)
      return false
    return !(payload.retryRole && payload.newWindowRole)
  }
  // Accept/coalesce immediately, before any asynchronous registry or desktop work.
  function request(payload: var): var {
    if (captureActive)
      return {
        ok: false,
        operationId: null,
        error: failure('INERT_MODE', 'Inert project fixture.')
      }
    if (!validPayload(payload))
      return {
        ok: false,
        operationId: null,
        error: failure('INVALID_REQUEST', 'Choose valid project IDs and one role action.')
      }
    if (!runtime || !runtime.sessionId)
      return {
        ok: false,
        operationId: null,
        error: failure('DEPENDENCY_MISSING', 'The project runtime is unavailable. Reinstall the project plugin and retry.')
      }
    syncSession()
    var project = registry.projects.filter(function (row) {
      return row.id === payload.projectId
    })[0]
    var checkoutId = payload.checkoutId || (project && project.lastCheckoutId) || null
    var pending = operations.filter(function (op) {
      return op.state !== 'completed' && op.sessionId === sessionId && op.projectId === payload.projectId && (op.checkoutId === checkoutId || (!payload.checkoutId && !op.requestedCheckoutId))
    })[0]
    if (pending)
      return {
        ok: true,
        operationId: pending.id,
        error: null
      }
    var request = Object.assign({}, payload, {
      checkoutId: checkoutId,
      requestedCheckoutId: payload.checkoutId || null,
      generation: ++generation,
      sessionId: sessionId
    })
    var id = 'op-' + Date.now() + '-' + generation
    var op = Operations.begin(operations, request, id).operation
    operations = operations.concat([op])
    queue = queue.concat([id])
    operationChanged(op)
    snapshotChanged()
    Qt.callLater(drain)
    return {
      ok: true,
      operationId: id,
      error: null
    }
  }
  // Keep the latest 100 completions without ever evicting accepted/pending work.
  function retainCompleted(): void {
    var completed = operations.filter(function (op) {
      return op.state === 'completed'
    }).sort(function (a, b) {
      return (a.completedAt || 0) - (b.completedAt || 0)
    })
    var evicted = completed.slice(0, Math.max(0, completed.length - 100)).map(function (op) {
      return op.id
    })
    operations = operations.filter(function (op) {
      return evicted.indexOf(op.id) < 0
    })
  }
  // Fail a transaction before launches; preserve the last valid registry and release the queue.
  function failOperation(id: string, code: string, message: string): void {
    var op = operation(id)
    if (!op.id || op.state === 'completed')
      return
    publish(Object.assign(Operations.complete(op, op.steps.concat([
      {
        role: 'operation',
        status: 'failed',
        code: code,
        message: message
      }
    ])), {
      error: failure(code, message),
      completedAt: Date.now()
    }))
    retainCompleted()
    releaseQueue(id)
  }
  // Release only the matching head, allowing independent observers to remain pending.
  function releaseQueue(id: string): void {
    if (queue[0] !== id)
      return
    queue = queue.slice(1)
    queueActive = false
    Qt.callLater(drain)
  }
  // Start the next global transaction against a fresh registry, never a cached target.
  function drain(): void {
    if (captureActive || refreshing || queueActive || !queue.length)
      return
    syncSession()
    if (!queue.length)
      return
    var id = queue[0]
    var op = operation(id)
    if (!op.id || op.state === 'completed') {
      releaseQueue(id)
      return
    }
    queueActive = true
    var revision = op.generation
    var session = op.sessionId
    invoke(storeRunner, [storePath, 'snapshot'], function (response) {
      if (!current(id, revision, session))
        return
      if (!response || !response.ok || !response.state) {
        var problem = response && response.error
        error = problem || failure('REGISTRY_UNAVAILABLE', 'Project registry unavailable.')
        failOperation(id, problem && problem.code || 'REGISTRY_UNAVAILABLE', problem && problem.message || 'Project registry unavailable.')
        return
      }
      registry = response.state
      error = null
      var project = registry.projects.filter(function (row) {
        return row.id === op.projectId
      })[0]
      var checkoutId = op.requestedCheckoutId || project && project.lastCheckoutId
      var checkout = project && project.checkouts.filter(function (row) {
        return row.id === checkoutId
      })[0]
      if (!project || !checkout) {
        failOperation(id, project ? 'CHECKOUT_NOT_FOUND' : 'PROJECT_NOT_FOUND', 'The selected project or checkout is unavailable. Locate its folder in project details.')
        return
      }
      op = Object.assign({}, operation(id), {
        checkoutId: checkout.id
      })
      publish(op)
      invoke(metadataRunner, [metadataPath, '--metadata', checkout.path, '--json'], function (metadata) {
        if (!current(id, revision, session))
          return
        if (!metadata || !metadata.ok || !metadata.metadata || metadata.metadata.path !== checkout.path || metadata.metadata.commonDir !== project.commonDir) {
          failOperation(id, 'CHECKOUT_INVALID', 'The registered checkout moved or its Git identity changed. Locate its folder in project details.')
          return
        }
        invoke(toolsRunner, [toolsPath, '--json'], function (tools) {
          if (!current(id, revision, session))
            return
          if (!tools || !Array.isArray(tools.editors) || !Array.isArray(tools.terminals)) {
            failOperation(id, 'DEPENDENCY_MISSING', tools && tools.error && tools.error.message || 'Project tool probe unavailable. Install required dependencies.')
            return
          }
          var defaults = tools.defaults || ({})
          var editorId = project.tools.editorId || defaults.editorId
          var terminalId = project.tools.terminalId || defaults.terminalId
          if (!editorId || !terminalId) {
            failOperation(id, 'TOOL_CHOICE_REQUIRED', 'Choose installed supported editor and terminal applications in project details.')
            return
          }
          var selected = {
            editor: editorId,
            terminal: terminalId
          }
          var available = {
            editor: tools.editors || [],
            terminal: tools.terminals || []
          }
          readDesktop(function (data) {
            if (!current(id, revision, session))
              return
            if (!data.available) {
              failOperation(id, 'COMPOSITOR_UNAVAILABLE', 'Connect to Hyprland to open project workspaces.')
              return
            }
            observedAt = data.observedAt || null
            validate(function (proof) {
              if (!current(id, revision, session))
                return
              prepareWorkspace(id, project, checkout, selected, available, proof)
            })
          })
        }, '')
      }, '')
    }, '')
  }
  // Persist a revision-checked mutation; failures never claim an association was saved.
  function mutate(id: string, action: string, args: var, done: var): void {
    var op = operation(id), revision = op.generation, session = op.sessionId
    invoke(storeRunner, [storePath, 'mutate'], function (response) {
      if (!current(id, revision, session))
        return
      if (!response || !response.ok || !response.state) {
        var problem = response && response.error
        failOperation(id, problem && problem.code || 'REGISTRY_WRITE_FAILED', problem && problem.message || 'Project registry write failed.')
        return
      }
      registry = response.state
      done()
    }, JSON.stringify({
      action: action,
      args: args,
      expectedRevision: registry.revision
    }))
  }
  // Decide a reserved association from fresh occupancy and proven alternate-checkout bindings.
  function prepareWorkspace(id: string, project: var, checkout: var, selected: var, available: var, proof: var): void {
    var op = operation(id), revision = op.generation, session = op.sessionId
    readDesktop(function (data) {
      if (!current(id, revision, session))
        return
      if (!data.available) {
        failOperation(id, 'COMPOSITOR_UNAVAILABLE', 'Connect to Hyprland to open project workspaces.')
        return
      }
      var associations = []
      registry.projects.forEach(function (row) {
        associations = associations.concat(row.associations || [])
      })
      var association = Operations.chooseAssociation(project, op, data.workspaces, associations, proof.bindings, data.currentWorkspaceId)
      if (!association) {
        failOperation(id, 'INVALID_WORKSPACE', 'The current workspace is unavailable. Choose dedicated workspace mode.')
        return
      }
      var existing = project.associations.some(function (row) {
        return row.workspaceId === association.workspaceId && row.checkoutId === association.checkoutId
      })
      persistAndFocus(id, project, checkout, selected, available, proof, association, !existing, 0)
    })
  }
  // Serialize association, selected checkout, focus and occupancy readback before launch.
  function persistAndFocus(id: string, project: var, checkout: var, selected: var, available: var, proof: var, association: var, allocated: bool, attempts: int): void {
    var op = operation(id), revision = op.generation, session = op.sessionId
    mutate(id, 'associate', Object.assign({
      projectId: project.id
    }, association), function () {
      var focus = function () {
        publish(Object.assign({}, operation(id), {
          state: 'focusing',
          workspaceId: association.workspaceId
        }))
        runtime.focusWorkspace(association.workspaceId, function (response) {
          if (!current(id, revision, session))
            return
          if (!response || response.status !== 'observed') {
            failOperation(id, response && response.code || 'FOCUS_UNCONFIRMED', response && response.message || 'Project workspace focus could not be confirmed.')
            return
          }
          readDesktop(function (data) {
            if (!current(id, revision, session))
              return
            if (!data.available) {
              failOperation(id, 'COMPOSITOR_UNAVAILABLE', 'The compositor became unavailable.')
              return
            }
            var occupied = allocated && association.mode === 'dedicated' && data.workspaces.some(function (row) {
              return row.id === association.workspaceId && (Array.isArray(row.windows) ? row.windows.length > 0 : row.windows > 0)
            })
            if (occupied) {
              if (attempts >= 8) {
                failOperation(id, 'WORKSPACE_BUSY', 'Workspace allocation kept changing. Retry after desktop activity settles.')
                return
              }
              var reservations = []
              registry.projects.forEach(function (row) {
                reservations = reservations.concat(row.associations || [])
              })
              var next = Object.assign({}, association, {
                workspaceId: Operations.allocateWorkspace(data.workspaces, reservations)
              })
              persistAndFocus(id, project, checkout, selected, available, proof, next, true, attempts + 1)
              return
            }
            publish(Object.assign({}, operation(id), {
              steps: operation(id).steps.concat([
                {
                  role: 'workspace',
                  status: 'observed',
                  code: null,
                  workspaceId: association.workspaceId
                }
              ])
            }))
            submitRoles(id, checkout, selected, available, proof, association, data)
          })
        })
      }
      if (project.lastCheckoutId !== checkout.id)
        mutate(id, 'select-checkout', {
          projectId: project.id,
          checkoutId: checkout.id
        }, focus)
      else
        focus()
    })
  }
  // Start independent configured roles with exact safe adapter specs and guarded callbacks.
  function submitRoles(id: string, checkout: var, selected: var, available: var, proof: var, association: var, baseline: var): void {
    var op = operation(id), revision = op.generation, session = op.sessionId
    publish(Object.assign({}, op, {
      state: 'launching',
      rolesPending: ['editor', 'terminal']
    }))
    var acceptedPending = 2
    var accepted = function () {
      acceptedPending--
      if (!acceptedPending)
        releaseQueue(id)
    }
    var roles = ['editor', 'terminal']
    roles.forEach(function (role) {
      if (!current(id, revision, session))
        return
      var prior = roleHistory[roleKey(op, role)] || null
      var ownedRoles = bindings.filter(function (row) {
        return row.projectId === op.projectId && row.checkoutId === op.checkoutId && row.role === role && row.sessionId === session
      })
      var fresh = proof.bindings.filter(function (row) {
        return row.projectId === op.projectId && row.checkoutId === op.checkoutId && row.role === role
      })[0] || null
      var binding = fresh || ownedRoles.filter(function (row) {
        return prior && prior.binding && row.address === prior.binding.address && row.pid === prior.binding.pid
      })[0] || ownedRoles[0] || null
      var allClosed = ownedRoles.length > 0 && ownedRoles.every(function (owned) {
        return proof.missing.some(function (closed) {
          return closed.binding && closed.binding.address === owned.address && closed.binding.pid === owned.pid && closed.identity.startTime === owned.evidence.startTime
        })
      })
      var closure = allClosed ? proof.missing.filter(function (row) {
        return row.binding && binding && row.binding.address === binding.address && row.binding.pid === binding.pid
      })[0] : null
      var disposition = closure ? {
        state: 'confirmed-missing',
        verified: true,
        projectId: op.projectId,
        checkoutId: op.checkoutId,
        role: role,
        sessionId: session,
        generation: revision,
        identity: closure.identity
      } : null
      var decision = Operations.roleDecision(role, op, fresh || (binding ? Object.assign({}, binding, {
          evidence: Object.assign({}, binding.evidence, {
            processVerified: false
          })
        }) : null), prior, baseline.windows, session, disposition)
      if (decision.action === 'focus' && typeof runtime.focusBinding === 'function') {
        runtime.focusBinding(fresh, function (focused) {
          accepted()
          if (!current(id, revision, session))
            return
          finishRole(id, role, {
            status: focused && focused.status === 'observed' ? 'observed' : 'unconfirmed',
            code: focused && focused.code || null,
            message: focused && focused.message || null,
            binding: focused && focused.status === 'observed' ? focused.binding || fresh : null,
            preserveHistory: !focused || focused.status !== 'observed'
          })
        })
        return
      }
      if (decision.action !== 'launch') {
        finishRole(id, role, {
          status: decision.action === 'focus' ? 'observed' : decision.action === 'skip' ? 'skipped' : 'unconfirmed',
          code: decision.code,
          binding: decision.action === 'focus' ? fresh : null
        })
        accepted()
        return
      }
      if (!available[role].some(function (row) {
        return row.id === selected[role]
      })) {
        finishRole(id, role, {
          status: 'failed',
          code: 'TOOL_MISSING',
          message: 'Select another installed supported application.'
        })
        accepted()
        return
      }
      var token = 'dev.aranea.project_' + session.replace(/[^A-Za-z0-9_]/g, '_') + '_' + revision + '_' + role
      var spec = toolContracts.launchSpec(role, selected[role], checkout.path, token, selected.terminal)
      if (!spec) {
        finishRole(id, role, {
          status: 'failed',
          code: 'UNSUPPORTED_TOOL',
          message: 'Choose a supported application adapter.'
        })
        accepted()
        return
      }
      spec = Object.assign({}, spec, {
        projectId: op.projectId,
        checkoutId: op.checkoutId,
        role: role,
        generation: revision,
        sessionId: session,
        workspaceId: association.workspaceId,
        token: token
      })
      var timer = deadlineComponent.createObject(controller, {
        operationId: id,
        role: role,
        revision: revision,
        session: session
      })
      var nextDeadlines = Object.assign({}, deadlines)
      nextDeadlines[id + ':' + role] = timer
      deadlines = nextDeadlines
      var responded = false
      runtime.launch(spec, function (response) {
        if (responded)
          return
        responded = true
        accepted()
        if (!current(id, revision, session) || operation(id).rolesPending.indexOf(role) < 0)
          return
        if (!response || !response.ok || response.status !== 'accepted') {
          finishRole(id, role, {
            status: 'failed',
            code: response && response.code || 'LAUNCH_FAILED',
            message: response && response.message
          })
          return
        }
        spec.launchIdentity = response.identity
        var history = Object.assign({}, roleHistory)
        history[roleKey(op, role)] = {
          role: role,
          status: 'unconfirmed',
          code: 'LAUNCH_ACCEPTED',
          launchIdentity: response.identity
        }
        roleHistory = history
        publish(Object.assign({}, operation(id), {
          state: 'observing'
        }))
        runtime.observe(spec, baseline, function (observed) {
          if (!current(id, revision, session) || operation(id).rolesPending.indexOf(role) < 0)
            return
          finishRole(id, role, observed || {
            status: 'unconfirmed',
            code: 'OBSERVATION_TIMEOUT'
          })
        })
      })
    })
  }
  // Pure fixed adapter import is exposed only to this live owner.
  property var toolContracts: Tools
  // Complete one role exactly once, retaining evidence/history independently of operation eviction.
  function finishRole(id: string, role: string, response: var): void {
    var op = operation(id)
    if (!op.id || op.state === 'completed' || !op.rolesPending || op.rolesPending.indexOf(role) < 0)
      return
    var timer = deadlines[id + ':' + role]
    if (timer) {
      timer.stop()
      timer.destroy()
      var nextTimers = Object.assign({}, deadlines)
      delete nextTimers[id + ':' + role]
      deadlines = nextTimers
    }
    var step = {
      role: role,
      status: response.status,
      code: response.code || null,
      message: response.message || null
    }
    if (response.binding) {
      step.binding = response.binding
      bindings = bindings.filter(function (row) {
        return !(row.projectId === op.projectId && row.checkoutId === op.checkoutId && row.role === role && row.address === response.binding.address && row.pid === response.binding.pid)
      }).concat([response.binding])
      freshBindings = freshBindings.filter(function (row) {
        return !(row.projectId === op.projectId && row.checkoutId === op.checkoutId && row.role === role && row.address === response.binding.address && row.pid === response.binding.pid)
      }).concat([response.binding])
    }
    if (!response.preserveHistory && step.status !== 'skipped' && step.code !== 'OWNERSHIP_UNCONFIRMED' && step.code !== 'RETRY_NOT_FAILED') {
      var history = Object.assign({}, roleHistory)
      history[roleKey(op, role)] = step
      roleHistory = history
    }
    var pending = op.rolesPending.filter(function (value) {
      return value !== role
    })
    var next = Object.assign({}, op, {
      rolesPending: pending,
      steps: op.steps.concat(step.status === 'skipped' ? [] : [step])
    })
    if (!pending.length) {
      next = Object.assign(Operations.complete(next, next.steps), {
        completedAt: Date.now()
      })
      retainCompleted()
    }
    publish(next)
    retainCompleted()
  }
  // Timer callbacks cannot update stale generations or another desktop session.
  property Component deadlineComponent: Component {
    Timer {
      id: timer
      property string operationId
      property string role
      property int revision
      property string session
      interval: controller.roleTimeout
      running: true
      onTriggered: if (controller.current(timer.operationId, timer.revision, timer.session)) {
        controller.finishRole(timer.operationId, timer.role, {
          status: 'unconfirmed',
          code: 'OBSERVATION_TIMEOUT',
          message: 'Launch could not be confirmed. Use Open new window explicitly.'
        })
        controller.releaseQueue(timer.operationId)
      }
    }
  }
  Timer {
    interval: 1000
    repeat: true
    running: !controller.captureActive
    onTriggered: controller.refresh()
  }
}
