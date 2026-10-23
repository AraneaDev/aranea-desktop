/** @typedef {{[key:string]:any}} EnvironmentData */

/**
 * Exact ownership/history key; environment identity never aliases legacy Open.
 * @param {EnvironmentData} operation - operation or binding identity
 * @param {string} role - supported tool role
 * @returns {string} scope key
 */
function roleKey(operation, role) {
  return operation.environmentId
    ? operation.environmentId + "\n" + role
    : operation.projectId + "\n" + operation.checkoutId + "\n" + role
}

/**
 * Allocate from a fresh, known occupancy snapshot. Null means no safe decision.
 * Saved records never reserve space; only windows and in-flight work do.
 * @param {?Array<EnvironmentData>} workspaces - fresh compositor workspace rows
 * @param {Array<EnvironmentData>} reservations - in-flight leases and operations
 * @returns {?number} lowest empty positive workspace, or unknown occupancy
 */
function chooseEmptyWorkspace(workspaces, reservations) {
  if (!Array.isArray(workspaces)) return null
  /** @type {{[key:string]:boolean}} */
  var used = {}
  for (var i = 0; i < workspaces.length; i++) {
    var row = workspaces[i]
    if (!row || !Number.isInteger(row.id)) return null
    var count = Array.isArray(row.windows) ? row.windows.length : row.windows
    if (!Number.isInteger(count) || count < 0) return null
    if (row.id > 0 && count > 0) used[String(row.id)] = true
  }
  ;(reservations || []).forEach(function (row) {
    if (Number.isInteger(row.workspaceId) && row.workspaceId > 0)
      used[String(row.workspaceId)] = true
  })
  var id = 1
  while (used[String(id)]) id++
  return id
}

/**
 * The newest placement on a workspace owns it. Environments are placed when
 * created or relocated; dedicated associations when allocated. Current-mode
 * records share a workspace and never claim one; associations saved before
 * placement stamps existed count as the oldest.
 * @param {Array<EnvironmentData>} projects - registry projects
 * @param {number} workspaceId - workspace in question
 * @param {number} since - the caller's own placement time
 * @param {(row: EnvironmentData, project: EnvironmentData) => boolean} isSelf - identifies the caller's record
 * @returns {boolean} whether another record was placed there later
 */
function newerClaim(projects, workspaceId, since, isSelf) {
  return (projects || []).some(function (project) {
    var environments = /** @type {Array<EnvironmentData>} */ (project.environments || []).filter(
      function (row) {
        return (
          row.mode !== "current" &&
          row.workspaceId === workspaceId &&
          placedAt(row) > since &&
          !isSelf(row, project)
        )
      }
    )
    var associations = /** @type {Array<EnvironmentData>} */ (project.associations || []).filter(
      function (row) {
        return (
          row.mode === "dedicated" &&
          row.workspaceId === workspaceId &&
          (row.placedAt || 0) > since &&
          !isSelf(row, project)
        )
      }
    )
    return environments.length > 0 || associations.length > 0
  })
}

/**
 * When an environment record took its workspace.
 * @param {EnvironmentData} row - environment record
 * @returns {number} placement time, falling back to creation
 */
function placedAt(row) {
  return Number.isInteger(row.placedAt) ? row.placedAt : row.createdAt || 0
}

/**
 * Find accepted activation identity, including retained completed operations.
 * The owner retains this mapping separately from bounded operation history.
 * @param {Array<EnvironmentData>} operations - accepted identities
 * @param {string} sessionId - current owner session
 * @param {string} activationId - immutable user activation
 * @returns {?EnvironmentData} accepted operation or null
 */
function coalesced(operations, sessionId, activationId) {
  if (!sessionId || !activationId) return null
  return (
    (operations || []).filter(function (operation) {
      return (
        !!operation.environmentId &&
        operation.sessionId === sessionId &&
        operation.activationId === activationId
      )
    })[0] || null
  )
}

/**
 * Project saved environments separately from legacy associations. Bindings must
 * already have been freshly verified by the runtime in this publication cycle.
 * The immutable creation session is historical; recovery proof belongs to the
 * current binding session. Metadata alone never establishes liveness or closure;
 * `windowOpen` only says a recorded launch window (same compositor instance,
 * exact address and pid) still sits on the environment's workspace, a naming
 * hint that survives owner restarts but never proves ownership.
 * @param {Array<EnvironmentData>} environments - immutable saved records
 * @param {Array<EnvironmentData>} bindings - freshly verified native bindings
 * @param {string} sessionId - current owner session
 * @param {EnvironmentData} [live] - compositor snapshot with windows
 * @param {string} [instance] - current compositor instance key
 * @returns {Array<EnvironmentData>} detached records with honest status/role summaries
 */
function projectRows(environments, bindings, sessionId, live, instance) {
  var liveWindows =
    live && live.available === true && Array.isArray(live.windows) ? live.windows : []
  return (environments || []).map(function (environment) {
    var recorded = environment.windows
    var windowOpen =
      !!instance &&
      !!recorded &&
      recorded.instance === instance &&
      (recorded.rows || []).some(function (/** @type {EnvironmentData} */ row) {
        return liveWindows.some(function (window) {
          return (
            window.address === row.address &&
            window.pid === row.pid &&
            window.workspaceId === environment.workspaceId
          )
        })
      })
    var observedRoles = ["editor", "terminal", "agent"].filter(function (role) {
      return (bindings || []).some(function (binding) {
        return (
          !!sessionId &&
          binding.sessionId === sessionId &&
          binding.environmentId === environment.id &&
          binding.projectId === environment.projectId &&
          binding.checkoutId === environment.checkoutId &&
          binding.role === role &&
          binding.pid > 0 &&
          typeof binding.address === "string" &&
          /^0x[0-9a-fA-F]+$/.test(binding.address) &&
          !/^0x0+$/.test(binding.address) &&
          binding.evidence &&
          binding.evidence.processVerified === true &&
          ["process-only", "process-app-id"].indexOf(binding.evidence.mode) >= 0
        )
      })
    })
    return Object.assign(JSON.parse(JSON.stringify(environment)), {
      status: observedRoles.length ? "observed" : "unconfirmed",
      observedRoles: observedRoles,
      windowOpen: windowOpen
    })
  })
}

if (typeof module !== "undefined")
  module.exports = { roleKey, chooseEmptyWorkspace, newerClaim, placedAt, coalesced, projectRows }
