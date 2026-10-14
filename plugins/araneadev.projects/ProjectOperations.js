/** @typedef {{[key:string]:any}} OperationData */

/**
 * Allocates the lowest positive workspace absent from occupied live workspaces
 * and persisted/reserved associations. Empty live workspaces remain reusable.
 * @param {Array<OperationData>} workspaces - fresh compositor snapshot
 * @param {Array<OperationData>} associations - all projects' persisted reservations
 * @returns {number} unused standard workspace ID
 */
function allocateWorkspace(workspaces, associations) {
  /** @type {{[key:string]:boolean}} */
  var used = {}
  ;(workspaces || []).forEach(function (workspace) {
    var count = Array.isArray(workspace.windows) ? workspace.windows.length : workspace.windows
    if (count > 0 && workspace.id > 0) used[String(workspace.id)] = true
  })
  ;(associations || []).forEach(function (association) {
    if (association.workspaceId > 0) used[String(association.workspaceId)] = true
  })
  var id = 1
  while (used[String(id)]) id++
  return id
}

/**
 * Coalesces legacy pending requests by checkout and environment requests by
 * activation in the current session, including retained completed acceptances.
 * Caller owns queue insertion and assigns monotonically increasing generations.
 * No input objects are mutated; new-window/retry flags do not bypass coalescing.
 * @param {Array<OperationData>} operations - owner queue
 * @param {OperationData} request - resolved IDs, options, generation and sessionId
 * @param {string} id - owner-generated operation ID
 * @returns {{operation:OperationData,reused:boolean}} existing or accepted operation
 */
function begin(operations, request, id) {
  var existing = (operations || []).filter(function (operation) {
    if (operation.environmentId || request.environmentId)
      return (
        !!operation.environmentId &&
        !!request.environmentId &&
        !!request.activationId &&
        operation.activationId === request.activationId &&
        operation.sessionId === request.sessionId
      )
    return (
      operation.state !== "completed" &&
      operation.projectId === request.projectId &&
      operation.checkoutId === request.checkoutId &&
      operation.sessionId === request.sessionId &&
      (operation.workspaceOnly === true) === (request.workspaceOnly === true)
    )
  })[0]
  if (existing) return { operation: existing, reused: true }
  return {
    operation: Object.assign({}, request, {
      id: id,
      state: "accepted",
      outcome: null,
      steps: [],
      error: null
    }),
    reused: false
  }
}

/**
 * Rejects callbacks from a completed operation, earlier generation or old session.
 * @param {OperationData} operation - pending operation
 * @param {number} generation - captured generation
 * @param {string} sessionId - captured compositor/session identity
 * @returns {boolean} whether the response can update the operation
 */
function acceptsGeneration(operation, generation, sessionId) {
  return (
    !!operation &&
    Number.isInteger(generation) &&
    generation >= 0 &&
    typeof sessionId === "string" &&
    !!sessionId &&
    operation.state !== "completed" &&
    operation.generation === generation &&
    operation.sessionId === sessionId
  )
}

/**
 * Combines independent observed/failed/unconfirmed steps into a terminal result.
 * Any accepted-unconfirmed step remains partial even without observed success.
 * Empty or solely failed results fail; dispatch acceptance cannot imply success.
 * @param {OperationData} operation - previous operation
 * @param {Array<OperationData>} steps - independent role/workspace outcomes
 * @returns {OperationData} completed copy preserving step codes and error
 */
function complete(operation, steps) {
  var observed = steps.some(function (step) {
    return step.status === "observed"
  })
  var uncertain = steps.some(function (step) {
    return step.status === "unconfirmed"
  })
  var incomplete = steps.some(function (step) {
    return step.status !== "observed"
  })
  var outcome = uncertain || (observed && incomplete) ? "partial" : observed ? "observed" : "failed"
  return Object.assign({}, operation, {
    state: "completed",
    outcome: outcome,
    steps: steps.slice()
  })
}

/**
 * Checks session-bound ownership against exact current compositor identities.
 * evidence is {mode,processVerified,...}: runtime alone sets processVerified
 * after fresh PID/start-time/ancestry verification; app IDs only corroborate it.
 * This function never converts titles, classes or workspace membership to proof.
 * @param {OperationData} binding - recorded binding with fresh evidence object
 * @param {Array<OperationData>} windows - normalized live address/pid/appId rows
 * @param {string} sessionId - current session identity
 * @returns {boolean} reliable binding still present
 */
function bindingMatches(binding, windows, sessionId) {
  if (
    !binding ||
    binding.sessionId !== sessionId ||
    !sessionId ||
    !binding.evidence ||
    binding.evidence.processVerified !== true ||
    !(binding.pid > 0) ||
    typeof binding.address !== "string" ||
    !/^0x[0-9a-fA-F]+$/.test(binding.address) ||
    /^0x0+$/.test(binding.address)
  )
    return false
  var mode = binding.evidence.mode
  if (mode !== "process-only" && mode !== "process-app-id") return false
  return (windows || []).some(function (window) {
    return (
      window.address === binding.address &&
      window.pid === binding.pid &&
      (mode === "process-only" || (!!binding.appId && window.appId === binding.appId))
    )
  })
}

/**
 * Selects a role action; caller skips unconfigured roles before invoking this.
 * Explicit new-window bypasses uncertain ownership. Retry launches only a known
 * failed role. Uncertain lost bindings and accepted-unconfirmed launches require
 * explicit new-window. Ordinary Resume can launch a positively confirmed missing
 * prior observed role using the optional disposition. The owner must freshly
 * verify the exact PID/startTime/address has closed or exited, including every
 * remaining owned window/process descendant. Absence of a title/class is not
 * proof. The disposition is {state:"confirmed-missing",verified:true,projectId,
 * checkoutId,environmentId?,role,sessionId,generation,identity:{pid,startTime,address}} and must
 * belong to this request generation/session and retained prior observed binding.
 * lastStep.binding archives that identity when the live binding is removed.
 * @param {string} role - editor or terminal
 * @param {OperationData} request - resolved IDs and optional role action
 * @param {?OperationData} binding - recorded role binding, possibly stale
 * @param {?OperationData} lastStep - latest role outcome in this session
 * @param {Array<OperationData>} windows - fresh normalized window snapshot
 * @param {string} sessionId - current session
 * @param {?OperationData} [disposition] - fresh positive role closure evidence
 * @returns {{action:string,code:?string}} focus, launch, hold or skip
 */
function roleDecision(role, request, binding, lastStep, windows, sessionId, disposition) {
  if (request.retryRole && request.retryRole !== role) return { action: "skip", code: null }
  if (request.newWindowRole === role) return { action: "launch", code: null }
  var related =
    binding &&
    binding.projectId === request.projectId &&
    binding.checkoutId === request.checkoutId &&
    (binding.environmentId || null) === (request.environmentId || null) &&
    binding.role === role
  var own = related && binding.sessionId === sessionId
  if (own && bindingMatches(binding, windows, sessionId)) return { action: "focus", code: null }
  var prior = lastStep && lastStep.status === "observed" && (own ? binding : lastStep.binding)
  var identity = disposition && disposition.identity
  if (
    !request.retryRole &&
    prior &&
    disposition &&
    disposition.state === "confirmed-missing" &&
    disposition.verified === true &&
    request.sessionId === sessionId &&
    acceptsGeneration(request, disposition.generation, sessionId) &&
    disposition.sessionId === sessionId &&
    disposition.projectId === request.projectId &&
    disposition.checkoutId === request.checkoutId &&
    (disposition.environmentId || null) === (request.environmentId || null) &&
    disposition.role === role &&
    prior.sessionId === sessionId &&
    prior.projectId === request.projectId &&
    prior.checkoutId === request.checkoutId &&
    (prior.environmentId || null) === (request.environmentId || null) &&
    prior.role === role &&
    prior.evidence &&
    ["process-only", "process-app-id"].indexOf(prior.evidence.mode) >= 0 &&
    identity &&
    Number.isInteger(identity.pid) &&
    identity.pid > 0 &&
    typeof identity.startTime === "string" &&
    /^[0-9]+$/.test(identity.startTime) &&
    typeof identity.address === "string" &&
    /^0x[0-9a-fA-F]+$/.test(identity.address) &&
    !/^0x0+$/.test(identity.address) &&
    identity.pid === prior.pid &&
    identity.startTime === prior.evidence.startTime &&
    identity.address === prior.address
  )
    return { action: "launch", code: null }
  if (
    related ||
    (lastStep && (lastStep.status === "unconfirmed" || lastStep.status === "observed"))
  )
    return { action: "hold", code: "OWNERSHIP_UNCONFIRMED" }
  if (request.retryRole === role && (!lastStep || lastStep.status !== "failed"))
    return { action: "hold", code: "RETRY_NOT_FAILED" }
  return { action: "launch", code: null }
}

/**
 * Resolves a normal or separately-opened checkout association without mutation.
 * Freshly validated bindings in another checkout protect the normal workspace.
 * Caller rechecks allocations immediately before dispatch and persists the result.
 * Explicit current workspace overrides project mode; a missing current ID returns
 * null. All associations include reservations belonging to other projects.
 * @param {OperationData} project - registry project and its associations
 * @param {OperationData} request - resolved checkout and workspace options
 * @param {Array<OperationData>} workspaces - fresh compositor workspaces
 * @param {Array<OperationData>} associations - all persisted/reserved associations
 * @param {Array<OperationData>} bindings - only freshly verified live bindings
 * @param {number} currentWorkspaceId - current positive standard workspace
 * @returns {?OperationData} association to persist, or null when unavailable
 */
function chooseAssociation(
  project,
  request,
  workspaces,
  associations,
  bindings,
  currentWorkspaceId
) {
  var separate = request.separate === true
  var mode = request.useCurrentWorkspace === true ? "current" : project.workspaceMode || "dedicated"
  /** @type {Array<OperationData>} */
  var projectAssociations = project.associations || []
  var existing = projectAssociations.filter(function (association) {
    return (
      association.separate === separate &&
      (!separate || association.checkoutId === request.checkoutId)
    )
  })[0]
  var workspaceId = mode === "current" ? currentWorkspaceId : existing && existing.workspaceId
  if (mode === "current" && (!Number.isInteger(workspaceId) || workspaceId < 1)) return null
  var conflict = (bindings || []).some(function (binding) {
    return (
      binding.projectId === project.id &&
      binding.checkoutId !== request.checkoutId &&
      binding.workspaceId === workspaceId
    )
  })
  if (conflict || !(workspaceId > 0)) {
    workspaceId = allocateWorkspace(workspaces, associations)
    mode = "dedicated"
  }
  return {
    checkoutId: request.checkoutId,
    mode: mode,
    workspaceId: workspaceId,
    separate: separate
  }
}

/**
 * Canonical roles for one request, including explicit recovery targets.
 * Retries open only their target. A new agent window without a one-off role set
 * opens only the agent; other requests retain saved or legacy defaults.
 * @param {OperationData} project - registry project with optional openRoles
 * @param {OperationData} request - one-off roles and optional targeted role
 * @returns {Array<string>} distinct supported roles in canonical order
 */
function requestedRoles(project, request) {
  if (["editor", "terminal", "agent"].indexOf(request.retryRole) >= 0) return [request.retryRole]
  var source = Array.isArray(request.roles)
    ? request.roles
    : request.newWindowRole === "agent"
      ? ["agent"]
      : project && Array.isArray(project.openRoles)
        ? project.openRoles
        : ["editor", "terminal"]
  var wanted = source.concat([request.retryRole, request.newWindowRole, request.reobserveRole])
  return ["editor", "terminal", "agent"].filter(function (role) {
    return wanted.indexOf(role) >= 0
  })
}

/**
 * First missing tool for the requested roles. Agents and Neovim require a
 * selected supported terminal that the installed-tool probe confirms available.
 * @param {Array<string>} roles - requested roles
 * @param {OperationData} selected - resolved editor, terminal and agent IDs
 * @param {OperationData} tools - installed-tool probe with terminals and agents
 * @returns {?{code:string,message:string}} problem or null when launchable
 */
function toolProblem(roles, selected, tools) {
  /**
   * Checks whether this request includes the role.
   * @param {string} role - role to check
   * @returns {boolean} whether the role is requested
   */
  var has = function (role) {
    return roles.indexOf(role) >= 0
  }
  if (has("editor") && !selected.editor)
    return { code: "TOOL_CHOICE_REQUIRED", message: "Choose an editor in Preferences." }
  var hostRequired = has("agent") || (has("editor") && selected.editor === "nvim")
  /** @type {Array<OperationData>} */
  var terminals = (tools && tools.terminals) || []
  var hostAvailable =
    ["alacritty", "kitty", "foot", "ghostty"].indexOf(selected.terminal) >= 0 &&
    terminals.some(function (row) {
      return row.id === selected.terminal && row.available === true && row.supported === true
    })
  if (((has("terminal") || hostRequired) && !selected.terminal) || (hostRequired && !hostAvailable))
    return {
      code: "TOOL_CHOICE_REQUIRED",
      message: has("agent")
        ? "Agents run in a terminal. Choose one in Preferences."
        : "Choose a terminal in Preferences."
    }
  if (!has("agent")) return null
  if (!selected.agent)
    return { code: "AGENT_MISSING", message: "Install Claude Code or Codex to start agents here." }
  /** @type {Array<OperationData>} */
  var agents = (tools && tools.agents) || []
  var installed =
    ["claude", "codex"].indexOf(selected.agent) >= 0 &&
    agents.some(function (row) {
      return row.id === selected.agent && row.available === true && row.supported !== false
    })
  return installed
    ? null
    : {
        code: "AGENT_MISSING",
        message: (selected.agent === "codex" ? "Codex" : "Claude Code") + " isn't installed."
      }
}

if (typeof module !== "undefined")
  module.exports = {
    allocateWorkspace,
    begin,
    acceptsGeneration,
    complete,
    bindingMatches,
    roleDecision,
    chooseAssociation,
    requestedRoles,
    toolProblem
  }
