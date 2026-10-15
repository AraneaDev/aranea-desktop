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
 * current binding session. Metadata alone never establishes liveness or closure.
 * @param {Array<EnvironmentData>} environments - immutable saved records
 * @param {Array<EnvironmentData>} bindings - freshly verified native bindings
 * @param {string} sessionId - current owner session
 * @returns {Array<EnvironmentData>} detached records with honest status/role summaries
 */
function projectRows(environments, bindings, sessionId) {
  return (environments || []).map(function (environment) {
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
      observedRoles: observedRoles
    })
  })
}

if (typeof module !== "undefined")
  module.exports = { roleKey, chooseEmptyWorkspace, coalesced, projectRows }
