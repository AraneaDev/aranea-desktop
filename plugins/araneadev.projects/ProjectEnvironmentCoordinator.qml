// Session-bound profile preflight and independent environment transactions for the sole owner.
import QtQuick
import "ProjectOperations.js" as Operations
import "ProjectProfiles.js" as Profiles
import "ProjectEnvironments.js" as Environments

Item {
  id: coordinator
  // The persistent controller owns the shared queue, registry and native safeguards.
  required property var owner
  // Unaccepted preparations have bounded lifetimes and reserve empty workspaces.
  property var leases: ({})
  // Sequential read-only preparations never overlap revision-sensitive queue work.
  property var pending: []
  // In-flight preparation blocks the owner's transaction drain until its read completes.
  property bool preparing: false
  // Session generation rejects late preparation callbacks.
  property int epoch: 0
  // Clone snapshots and receipts before exposing them across a public boundary.
  function copy(value: var): var {
    return JSON.parse(JSON.stringify(value))
  }
  // Refusals never carry an accepted operation identity.
  function refused(code: string, message: string): var {
    return {
      ok: false,
      operationId: null,
      error: owner.failure(code, message)
    }
  }
  // Exact activation identity is supplied once by the client using the kernel UUID source.
  function activationValid(id: var): bool {
    return typeof id === 'string' && /^a-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)
  }
  // Validate the narrow launch contract without accepting legacy flags or arbitrary adapters.
  function valid(payload: var): bool {
    return !!payload && typeof payload === 'object' && !Array.isArray(payload) && Object.keys(payload).length === 5 && Object.keys(payload).every(function (key) {
      return ['projectId', 'checkoutId', 'profileId', 'profileRevision', 'activationId'].indexOf(key) >= 0
    }) && ['projectId', 'checkoutId', 'profileId'].every(function (key) {
      return typeof payload[key] === 'string' && !!payload[key] && !/[\x00-\x1f\x7f]/.test(payload[key])
    }) && Number.isInteger(payload.profileRevision) && payload.profileRevision > 0 && activationValid(payload.activationId)
  }
  // Stable target identity deliberately excludes unrelated registry revision and navigation writes.
  function key(payload: var): string {
    return [payload.projectId, payload.checkoutId, payload.profileId, payload.profileRevision, payload.activationId].join('\n')
  }
  // Expiration releases only unused reservations; accepted operations own their own reservation.
  function prune(): void {
    var next = {}
    Object.keys(leases).forEach(function (id) {
      if (leases[id].expires > Date.now() && leases[id].sessionId === owner.sessionId)
        next[id] = leases[id]
    })
    leases = next
  }
  // Capture/session changes invalidate both reserved leases and in-flight reads.
  function invalidate(): void {
    epoch++
    leases = ({})
    pending = []
    preparing = false
  }
  // Combine unaccepted leases with the owner's old/new reservations in one allocator.
  function reservations(): var {
    prune()
    return Object.keys(leases).map(function (id) {
      return leases[id]
    }).filter(function (lease) {
      return lease.workspaceId > 0
    })
  }
  // Look up current-session accepted receipts without creating any new work.
  function environmentActivation(payload: var): var {
    if (owner.captureActive)
      return refused('INERT_MODE', 'Inert project fixture.')
    owner.syncSession()
    if (!payload || Object.keys(payload).length !== 1 || !activationValid(payload.activationId))
      return refused('INVALID_REQUEST', 'Choose a valid activation identity.')
    var op = Environments.coalesced(owner.environmentActivations, owner.sessionId, payload.activationId)
    var result = {
      ok: true,
      sessionId: owner.sessionId,
      activationId: payload.activationId,
      found: !!op
    }
    if (op)
      Object.assign(result, {
        operationId: op.id,
        environmentId: op.environmentId,
        operation: copy(op)
      })
    return result
  }
  // Idempotent asynchronous preparation never accepts, persists, focuses or launches.
  function prepareEnvironment(payload: var): var {
    if (owner.captureActive)
      return refused('INERT_MODE', 'Inert project fixture.')
    owner.syncSession()
    if (!owner.runtime || !owner.sessionId)
      return refused('DEPENDENCY_MISSING', 'The project runtime is not available.')
    if (!valid(payload))
      return refused('INVALID_REQUEST', 'Choose an exact checkout and profile revision.')
    prune()
    var id = key(payload), lease = leases[id]
    if (lease)
      return lease.error ? refused(lease.error.code, lease.error.message) : {
        ok: true,
        ready: true,
        sessionId: lease.sessionId,
        activationId: payload.activationId
      }
    if (!pending.some(function (row) {
      return key(row) === id
    }))
      pending = pending.concat([copy(payload)])
    Qt.callLater(prepareNext)
    return owner.notReady()
  }
  // A hung helper releases the shared queue and leaves a retryable preflight refusal.
  function preparationExpired(): void {
    if (!preparing || !pending.length)
      return
    var payload = pending[0], next = Object.assign({}, leases)
    epoch++
    next[key(payload)] = {
      sessionId: owner.sessionId,
      expires: Date.now() + 5000,
      error: owner.failure('PREPARATION_TIMEOUT', 'Profile preparation timed out. Try a new activation.')
    }
    leases = next
    pending = pending.slice(1)
    preparing = false
    Qt.callLater(owner.drain)
    Qt.callLater(prepareNext)
  }
  // Resolve the exact selected checkout/profile from a fresh authoritative registry.
  function target(state: var, payload: var): var {
    var project = state && state.projects && state.projects.filter(function (row) {
      return row.id === payload.projectId
    })[0]
    var checkout = project && project.checkouts.filter(function (row) {
      return row.id === payload.checkoutId
    })[0]
    var profile = project && (project.profiles || []).filter(function (row) {
      return row.id === payload.profileId
    })[0]
    if (!project || !checkout || project.lastCheckoutId !== payload.checkoutId)
      return {
        error: owner.failure('CHECKOUT_CHANGED', 'Select the current registered checkout and try again.')
      }
    if (!profile || profile.revision !== payload.profileRevision)
      return {
        error: owner.failure('PROFILE_CHANGED', 'The profile changed. Review it and try again.')
      }
    return {
      project: project,
      checkout: checkout,
      profile: profile
    }
  }
  // Initial preflight may resolve defaults; recovery validates only frozen launch choices.
  function toolSelection(profile: var, tools: var, resolveDefaults: bool): var {
    if (!tools || !Array.isArray(tools.editors) || !Array.isArray(tools.terminals))
      return {
        error: owner.failure('DEPENDENCY_MISSING', 'The installed tool probe is unavailable.')
      }
    var resolved = resolveDefaults ? Profiles.resolve(profile, tools) : null
    if (resolved && !resolved.ok)
      return {
        error: owner.failure('TOOL_MISSING', resolved.error)
      }
    var choices = resolved ? resolved.tools : profile.tools
    var selected = {
      editor: choices.editorId,
      terminal: choices.terminalId,
      agent: choices.agentId
    }
    var available = {
      editor: tools.editors,
      terminal: tools.terminals,
      agent: tools.agents || []
    }
    var problem = Operations.toolProblem(profile.roles, selected, tools)
    if (problem)
      return {
        error: problem
      }
    var required = profile.roles.slice()
    if ((required.indexOf('agent') >= 0 || selected.editor === 'nvim') && required.indexOf('terminal') < 0)
      required.push('terminal')
    if (required.some(function (role) {
      return !available[role].some(function (row) {
        return row.id === selected[role] && row.available === true && row.supported !== false
      })
    }))
      return {
        error: owner.failure('TOOL_MISSING', 'A profile application is unavailable. Review the profile tools.')
      }
    return {
      selected: selected,
      available: available
    }
  }
  // Preparations serialize with legacy/environment mutations, but produce only in-memory leases.
  function prepareNext(): void {
    if (owner.captureActive || preparing || owner.queueActive || owner.refreshing || !pending.length)
      return
    owner.syncSession()
    if (!pending.length)
      return
    var payload = pending[0], id = key(payload), generation = epoch, session = owner.sessionId
    preparing = true
    var current = function () {
      owner.syncSession()
      return !owner.captureActive && generation === epoch && session === owner.sessionId
    }
    var finish = function (lease) {
      if (!current())
        return
      var next = Object.assign({}, leases)
      next[id] = Object.assign(copy(lease), {
        sessionId: session,
        expires: Date.now() + 5000,
        payload: copy(payload)
      })
      leases = next
      pending = pending.slice(1)
      preparing = false
      owner.snapshotChanged()
      Qt.callLater(owner.drain)
      Qt.callLater(prepareNext)
    }
    owner.invoke(owner.storeRunner, [owner.storePath, 'snapshot'], function (response) {
      if (!current())
        return
      if (!response || !response.ok || !response.state) {
        finish({
          error: response && response.error || owner.failure('REGISTRY_UNAVAILABLE', 'Project registry unavailable.')
        })
        return
      }
      var resolved = target(response.state, payload)
      if (resolved.error) {
        finish(resolved)
        return
      }
      owner.registry = response.state
      owner.registryReady = true
      owner.invoke(owner.metadataRunner, [owner.metadataPath, '--metadata', resolved.checkout.path, '--json'], function (metadata) {
        if (!current())
          return
        if (!metadata || !metadata.ok || !metadata.metadata || metadata.metadata.path !== resolved.checkout.path || metadata.metadata.commonDir !== resolved.project.commonDir) {
          finish({
            error: owner.failure('CHECKOUT_INVALID', 'The registered checkout moved or its Git identity changed.')
          })
          return
        }
        var observedCheckout = (metadata.metadata.checkouts || []).filter(function (row) {
          return row.path === resolved.checkout.path
        })[0]
        if (!observedCheckout || !(observedCheckout.branch === null || typeof observedCheckout.branch === 'string' && observedCheckout.branch.length > 0)) {
          finish({
            error: owner.failure('CHECKOUT_INVALID', 'Fresh checkout branch metadata is unavailable.')
          })
          return
        }
        var launchCheckout = Object.assign({}, resolved.checkout, {
          branch: observedCheckout.branch
        })
        owner.invoke(owner.toolsRunner, [owner.toolsPath, '--json'], function (tools) {
          if (!current())
            return
          var choices = toolSelection(resolved.profile, tools, true)
          if (choices.error) {
            finish(choices)
            return
          }
          owner.readDesktop(function (data) {
            if (!current())
              return
            // Current mode shares the focused workspace; dedicated takes the lowest empty one.
            var shared = (resolved.project.workspaceMode || 'dedicated') === 'current'
            if (shared && data && data.available && !(Number.isInteger(data.currentWorkspaceId) && data.currentWorkspaceId > 0)) {
              finish({
                error: owner.failure('INVALID_WORKSPACE', 'The current workspace is unavailable. Choose dedicated workspace mode.')
              })
              return
            }
            var workspace = shared ? data && data.available && data.currentWorkspaceId : owner.chooseEnvironmentWorkspace(data)
            if (!workspace) {
              finish({
                error: owner.failure('WORKSPACE_UNAVAILABLE', shared ? 'The current workspace is unavailable.' : 'Fresh empty workspace occupancy is unavailable.')
              })
              return
            }
            if (typeof owner.runtime.createEnvironmentId !== 'function') {
              finish({
                error: owner.failure('DEPENDENCY_MISSING', 'The environment identity source is unavailable.')
              })
              return
            }
            owner.runtime.createEnvironmentId(function (environmentId) {
              if (!current())
                return
              if (!/^e-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(environmentId || '')) {
                finish({
                  error: owner.failure('DEPENDENCY_MISSING', 'Could not prepare an environment identity.')
                })
                return
              }
              finish({
                workspaceId: workspace,
                registeredCheckout: copy(resolved.checkout),
                selected: choices.selected,
                available: choices.available,
                environment: {
                  id: environmentId,
                  projectId: payload.projectId,
                  checkoutId: payload.checkoutId,
                  activationId: payload.activationId,
                  workspaceId: workspace,
                  mode: shared ? 'current' : 'dedicated',
                  sessionId: session,
                  createdAt: Date.now(),
                  checkoutSnapshot: copy(launchCheckout),
                  profileSnapshot: copy(resolved.profile),
                  resolvedTools: {
                    editorId: choices.selected.editor,
                    terminalId: choices.selected.terminal,
                    agentId: choices.selected.agent
                  }
                }
              })
            })
          })
        }, '')
      }, '')
    }, '')
  }
  // Consumption transfers the reservation atomically before the shared queue can drain.
  function startEnvironment(payload: var): var {
    if (owner.captureActive)
      return refused('INERT_MODE', 'Inert project fixture.')
    owner.syncSession()
    if (!owner.runtime || !owner.sessionId)
      return refused('DEPENDENCY_MISSING', 'The project runtime is not available.')
    if (!valid(payload))
      return refused('INVALID_REQUEST', 'Choose an exact checkout and profile revision.')
    var accepted = Environments.coalesced(owner.environmentActivations, owner.sessionId, payload.activationId)
    if (accepted)
      return key(accepted.startTarget || {}) === key(payload) ? receipt(accepted) : refused('ACTIVATION_CONFLICT', 'This activation already belongs to another target.')
    prune()
    var id = key(payload), lease = leases[id]
    if (!lease) {
      prepareEnvironment(payload)
      return owner.notReady()
    }
    if (lease.error)
      return refused(lease.error.code, lease.error.message)
    var resolved = target(owner.registry, payload)
    if (resolved.error || JSON.stringify(resolved.checkout) !== JSON.stringify(lease.registeredCheckout) || JSON.stringify(resolved.profile) !== JSON.stringify(lease.environment.profileSnapshot))
      return refused('TARGET_CHANGED', 'The checkout or profile changed after preparation.')
    var next = Object.assign({}, leases)
    delete next[id]
    leases = next
    var request = {
      projectId: payload.projectId,
      checkoutId: payload.checkoutId,
      environmentId: lease.environment.id,
      activationId: payload.activationId,
      startTarget: copy(payload),
      environment: copy(lease.environment),
      selected: copy(lease.selected),
      availableTools: copy(lease.available),
      roles: lease.environment.profileSnapshot.roles.slice(),
      agentId: lease.selected.agent,
      workspaceId: lease.workspaceId,
      sessionId: owner.sessionId,
      generation: ++owner.generation
    }
    var op = Operations.begin(owner.operations, request, 'op-' + Date.now() + '-' + owner.generation).operation
    return receipt(owner.enqueueOperation(op))
  }
  // A validated accepted receipt is distinct from later operation success.
  function receipt(op: var): var {
    return {
      ok: true,
      operationId: op.id,
      environmentId: op.environmentId
    }
  }
  // Return is an exact focus transaction; it does not repair or launch any missing role.
  function returnEnvironment(payload: var): var {
    if (owner.captureActive)
      return refused('INERT_MODE', 'Inert project fixture.')
    owner.syncSession()
    if (!payload || Object.keys(payload).length !== 2 || !payload.projectId || !payload.environmentId)
      return refused('INVALID_REQUEST', 'Choose an exact environment.')
    var env = owner.environmentRecords().filter(function (row) {
      return row.projectId === payload.projectId && row.id === payload.environmentId
    })[0]
    if (!env)
      return refused('ENVIRONMENT_NOT_FOUND', 'The environment is not available. Refresh Projects.')
    var op = Operations.begin(owner.operations, {
      projectId: env.projectId,
      checkoutId: env.checkoutId,
      environmentId: env.id,
      environmentReturn: true,
      workspaceId: env.workspaceId,
      sessionId: owner.sessionId,
      generation: ++owner.generation
    }, 'op-' + Date.now() + '-' + owner.generation).operation
    return receipt(owner.enqueueOperation(op))
  }
  // Exact role recovery preserves snapshots and has its own coalesced acceptance identity.
  function recoverEnvironment(payload: var): var {
    if (owner.captureActive)
      return refused('INERT_MODE', 'Inert project fixture.')
    owner.syncSession()
    var actions = ['retryRole', 'newWindowRole', 'reobserveRole']
    var action = payload && actions.filter(function (name) {
      return payload[name] !== undefined
    })
    if (!payload || Object.keys(payload).some(function (name) {
      return ['projectId', 'environmentId', 'activationId'].concat(actions).indexOf(name) < 0
    }) || !action || action.length !== 1 || !activationValid(payload.activationId))
      return refused('INVALID_REQUEST', 'Choose one exact environment role recovery.')
    var env = owner.environmentRecords().filter(function (row) {
      return row.projectId === payload.projectId && row.id === payload.environmentId
    })[0]
    if (!env)
      return refused('ENVIRONMENT_NOT_FOUND', 'The environment is not available. Refresh Projects.')
    if (env.profileSnapshot.roles.indexOf(payload[action[0]]) < 0)
      return refused('INVALID_REQUEST', 'Choose a role from the original environment profile.')
    var accepted = Environments.coalesced(owner.environmentActivations, owner.sessionId, payload.activationId)
    if (accepted)
      return accepted.recoveryTarget && Object.keys(accepted.recoveryTarget).length === Object.keys(payload).length && Object.keys(payload).every(function (name) {
        return accepted.recoveryTarget[name] === payload[name]
      }) ? receipt(accepted) : refused('ACTIVATION_CONFLICT', 'This activation already belongs to another target.')
    var request = Object.assign({}, copy(payload), {
      checkoutId: env.checkoutId,
      environment: copy(env),
      recoveryTarget: copy(payload),
      environmentRecovery: true,
      workspaceId: env.workspaceId,
      roles: [payload[action[0]]],
      sessionId: owner.sessionId,
      generation: ++owner.generation
    })
    var op = Operations.begin(owner.operations, request, 'op-' + Date.now() + '-' + owner.generation).operation
    return receipt(owner.enqueueOperation(op))
  }
  // Recover a saved environment in place, using its launch snapshots instead of current defaults.
  function drainRecovery(id: string): void {
    var op = owner.operation(id), generation = op.generation, session = op.sessionId
    var env = owner.environmentRecords().filter(function (row) {
      return row.id === op.environmentId && row.projectId === op.projectId
    })[0]
    if (!env || env.workspaceId !== op.workspaceId) {
      owner.failOperation(id, 'ENVIRONMENT_CHANGED', 'The saved environment changed. Refresh Projects.')
      return
    }
    if (op.reobserveRole) {
      owner.publish(Object.assign({}, op, {
        rolesPending: [op.reobserveRole]
      }))
      owner.reobserveRole(id, op.reobserveRole)
      owner.releaseQueue(id)
      return
    }
    var project = owner.registry.projects.filter(function (row) {
      return row.id === op.projectId
    })[0]
    var checkout = project && project.checkouts.filter(function (row) {
      return row.id === op.checkoutId && row.path === env.checkoutSnapshot.path
    })[0]
    if (!checkout) {
      owner.failOperation(id, 'CHECKOUT_INVALID', 'The original registered checkout is unavailable.')
      return
    }
    owner.invoke(owner.metadataRunner, [owner.metadataPath, '--metadata', checkout.path, '--json'], function (metadata) {
      if (!owner.current(id, generation, session))
        return
      if (!metadata || !metadata.ok || !metadata.metadata || metadata.metadata.path !== checkout.path || metadata.metadata.commonDir !== project.commonDir) {
        owner.failOperation(id, 'CHECKOUT_INVALID', 'The original checkout identity changed.')
        return
      }
      owner.invoke(owner.toolsRunner, [owner.toolsPath, '--json'], function (tools) {
        if (!owner.current(id, generation, session))
          return
        var choices = toolSelection({
          roles: op.roles,
          tools: env.resolvedTools
        }, tools, false)
        if (choices.error) {
          owner.failOperation(id, choices.error.code, choices.error.message)
          return
        }
        owner.publish(Object.assign({}, owner.operation(id), {
          selected: choices.selected,
          availableTools: choices.available,
          agentId: choices.selected.agent
        }))
        owner.readDesktop(function (data) {
          if (!owner.current(id, generation, session))
            return
          // Shared records recover in place while their workspace exists.
          if (workspaceAvailable(data, op.workspaceId) && (env.mode === 'current' || !claimedElsewhere(env))) {
            focusAndLaunch(id)
            return
          }
          // Released records move: dedicated to the lowest empty workspace, shared to the current one.
          var shared = env.mode === 'current'
          var next = !data.available ? null : shared ? data.currentWorkspaceId : owner.chooseEnvironmentWorkspace(data)
          if (!(Number.isInteger(next) && next > 0)) {
            if (shared && data.available)
              owner.failOperation(id, 'INVALID_WORKSPACE', 'The current workspace is unavailable. Choose dedicated workspace mode.')
            else
              owner.failOperation(id, 'WORKSPACE_UNAVAILABLE', 'The original workspace is unavailable.')
            return
          }
          owner.mutate(id, 'environment-associate', {
            projectId: op.projectId,
            environmentId: op.environmentId,
            previousWorkspaceId: op.workspaceId,
            workspaceId: next,
            placedAt: Date.now()
          }, function () {
            var moved = owner.operation(id)
            owner.publish(Object.assign({}, moved, {
              workspaceId: next,
              environment: Object.assign({}, moved.environment, {
                workspaceId: next
              })
            }))
            focusAndLaunch(id)
          })
        })
      }, '')
    }, '')
  }
  // A record placed on the same workspace after this environment owns it now.
  function claimedElsewhere(env: var): bool {
    return Environments.newerClaim(owner.registry.projects, env.workspaceId, Environments.placedAt(env), function (row) {
      return row.id === env.id
    })
  }
  // A saved ID alone cannot prove that a workspace exists in the current desktop.
  function workspaceAvailable(data: var, workspace: int): bool {
    return !!data && data.available === true && Array.isArray(data.workspaces) && data.workspaces.some(function (row) {
      return row.id === workspace
    })
  }
  // Fresh saved metadata is loaded by the sole queue before any environment transaction.
  function drain(id: string): void {
    var op = owner.operation(id), generation = op.generation, session = op.sessionId
    if (op.environmentRecovery) {
      drainRecovery(id)
      return
    }
    if (op.environmentReturn) {
      var env = owner.environmentRecords().filter(function (row) {
        return row.id === op.environmentId && row.projectId === op.projectId
      })[0]
      if (!env) {
        owner.failOperation(id, 'ENVIRONMENT_NOT_FOUND', 'The environment is not available.')
        return
      }
      if (claimedElsewhere(env)) {
        owner.failOperation(id, 'ENVIRONMENT_CHANGED', 'Another environment now uses this workspace. Start working to open a new one.')
        return
      }
      owner.readDesktop(function (data) {
        if (!owner.current(id, generation, session))
          return
        if (!data.available || !Array.isArray(data.workspaces) || !data.workspaces.some(function (row) {
          return row.id === env.workspaceId
        })) {
          owner.failOperation(id, 'WORKSPACE_UNAVAILABLE', 'The saved workspace is unavailable.')
          return
        }
        owner.runtime.focusWorkspace(env.workspaceId, function (response) {
          if (!owner.current(id, generation, session))
            return
          if (!response || !response.ok || response.status !== 'observed') {
            owner.failOperation(id, 'FOCUS_UNCONFIRMED', 'Workspace focus could not be confirmed.')
            return
          }
          owner.publish(Object.assign(Operations.complete(owner.operation(id), [
            {
              role: 'workspace',
              status: 'observed',
              workspaceId: env.workspaceId
            }
          ]), {
            workspaceId: env.workspaceId,
            completedAt: Date.now()
          }))
          owner.releaseQueue(id)
        })
      })
      return
    }
    ensureEmpty(id, false, function () {
      var current = owner.operation(id)
      owner.mutate(id, 'environment-register', {
        projectId: current.projectId,
        environment: current.environment
      }, function () {
        ensureEmpty(id, true, function () {
          focusAndLaunch(id)
        })
      })
    })
  }
  // Unknown occupancy refuses allocation; no unrelated window is ever moved.
  function empty(data: var, workspaceId: int): bool {
    if (!data || !data.available || Environments.chooseEmptyWorkspace(data.workspaces, []) === null)
      return false
    return !data.workspaces.some(function (row) {
      return row.id === workspaceId && (Array.isArray(row.windows) ? row.windows.length : row.windows) > 0
    })
  }
  // Other leases and in-flight operations can claim an otherwise empty leased workspace.
  function reservedElsewhere(op: var): bool {
    return owner.workspaceReservations().some(function (row) {
      return row.workspaceId === op.workspaceId && row.id !== op.id && row.id !== op.environmentId && row.environmentId !== op.environmentId
    })
  }
  // Before the first native attempt, moving a reservation guards its previous ID and registry revision.
  function ensureEmpty(id: string, persisted: bool, done: var): void {
    var op = owner.operation(id), generation = op.generation, session = op.sessionId
    owner.readDesktop(function (data) {
      if (!owner.current(id, generation, session))
        return
      // Shared environments launch beside existing windows and are never moved.
      if (op.environment && op.environment.mode === 'current') {
        if (workspaceAvailable(data, op.workspaceId))
          done(data)
        else
          owner.failOperation(id, 'WORKSPACE_UNAVAILABLE', 'The current workspace is unavailable.')
        return
      }
      if (empty(data, op.workspaceId) && !reservedElsewhere(op)) {
        done(data)
        return
      }
      if (op.nativeAttempted || (op.reallocations || 0) >= 8) {
        owner.failOperation(id, 'WORKSPACE_BUSY', 'Workspace occupancy changed; review the partial environment.')
        return
      }
      var workspace = owner.chooseEnvironmentWorkspace(data)
      if (!workspace) {
        owner.failOperation(id, 'WORKSPACE_UNAVAILABLE', 'Fresh empty workspace occupancy is unavailable.')
        return
      }
      var changed = Object.assign({}, op, {
        workspaceId: workspace,
        reallocations: (op.reallocations || 0) + 1,
        environment: Object.assign({}, op.environment, {
          workspaceId: workspace
        })
      })
      owner.publish(changed)
      if (persisted)
        owner.mutate(id, 'environment-associate', {
          projectId: op.projectId,
          environmentId: op.environmentId,
          previousWorkspaceId: op.workspaceId,
          workspaceId: workspace,
          placedAt: Date.now()
        }, function () {
          ensureEmpty(id, true, done)
        })
      else
        ensureEmpty(id, false, done)
    })
  }
  // Focus and confirm a prepared workspace before delegating roles to existing ownership safeguards.
  function focusAndLaunch(id: string): void {
    var op = owner.operation(id), generation = op.generation, session = op.sessionId
    owner.runtime.focusWorkspace(op.workspaceId, function (response) {
      if (!owner.current(id, generation, session))
        return
      if (!response || !response.ok || response.status !== 'observed') {
        owner.failOperation(id, 'FOCUS_UNCONFIRMED', 'Workspace focus could not be confirmed.')
        return
      }
      owner.publish(Object.assign({}, owner.operation(id), {
        steps: [
          {
            role: 'workspace',
            status: 'observed',
            workspaceId: op.workspaceId
          }
        ]
      }))
      owner.validate(function (proof) {
        if (!owner.current(id, generation, session))
          return
        owner.submitRoles(id, op.environment.checkoutSnapshot, op.selected, op.availableTools, proof, {
          workspaceId: op.workspaceId
        }, {
          windows: []
        })
      })
    })
  }
  // Final readback precedes native dispatch; external compositor races after readback remain unavoidable.
  function beforeDispatch(id: string, done: var): void {
    var op = owner.operation(id), generation = op.generation, session = op.sessionId
    if (op.environmentRecovery) {
      owner.readDesktop(function (data) {
        if (!owner.current(id, generation, session))
          return
        if (!workspaceAvailable(data, op.workspaceId)) {
          owner.failOperation(id, 'WORKSPACE_UNAVAILABLE', 'The original workspace is unavailable.')
          return
        }
        done(data, op.workspaceId)
      })
      return
    }
    if (!op.nativeAttempted) {
      ensureEmpty(id, true, function (data) {
        var next = owner.operation(id)
        if (next.workspaceId === op.workspaceId) {
          done(data, next.workspaceId)
          return
        }
        owner.runtime.focusWorkspace(next.workspaceId, function (response) {
          if (!owner.current(id, generation, session))
            return
          if (!response || !response.ok || response.status !== 'observed') {
            owner.failOperation(id, 'FOCUS_UNCONFIRMED', 'Workspace focus could not be confirmed.')
            return
          }
          owner.publish(Object.assign({}, owner.operation(id), {
            steps: owner.operation(id).steps.map(function (step) {
              return step.role === 'workspace' ? Object.assign({}, step, {
                workspaceId: next.workspaceId
              }) : step
            })
          }))
          beforeDispatch(id, done)
        })
      })
      return
    }
    owner.readDesktop(function (data) {
      if (!owner.current(id, generation, session))
        return
      owner.validate(function (proof) {
        if (!owner.current(id, generation, session))
          return
        var own = proof.bindings.filter(function (binding) {
          return binding.environmentId === op.environmentId && binding.sessionId === session && binding.workspaceId === op.workspaceId
        })
        var row = data.workspaces && data.workspaces.filter(function (workspace) {
          return workspace.id === op.workspaceId
        })[0]
        var count = row && (Array.isArray(row.windows) ? row.windows.length : row.windows) || 0
        var windows = (data.windows || []).filter(function (window) {
          return window.workspaceId === op.workspaceId
        })
        // A shared workspace holds unrelated windows by design; only dedicated ones must be exclusive.
        var shared = op.environment && op.environment.mode === 'current'
        if (!data.available || Environments.chooseEmptyWorkspace(data.workspaces, []) === null || !shared && (count > own.length || windows.some(function (window) {
            return !own.some(function (binding) {
              return binding.address === window.address && binding.pid === window.pid
            })
          }))) {
          owner.failOperation(id, 'WORKSPACE_BUSY', 'Workspace ownership changed after a native attempt. Review the partial environment.')
          return
        }
        done(data, op.workspaceId)
      })
    })
  }
  Timer {
    interval: 5000
    running: coordinator.preparing
    onTriggered: coordinator.preparationExpired()
  }
  Timer {
    interval: 100
    repeat: true
    running: Object.keys(coordinator.leases).length > 0 || coordinator.pending.length > 0
    onTriggered: {
      coordinator.prune()
      coordinator.prepareNext()
    }
  }
}
