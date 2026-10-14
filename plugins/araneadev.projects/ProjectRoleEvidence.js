.pragma library
.import "ProjectEnvironments.js" as Environments
.import "ProjectOperations.js" as Operations
/** @typedef {{[key:string]:any}} RoleContext */

/**
 * Select retained and freshly verified role ownership without changing evidence.
 * Every retained copy must have exact positive closure proof before Resume may
 * reuse a missing observed identity. Selection order preserves owner history.
 * @param {RoleContext} context - operation, role, session and explicit owner evidence
 * @returns {{prior:?RoleContext,fresh:?RoleContext,binding:?RoleContext,disposition:?RoleContext}} selected evidence
 */
function selectRoleEvidence(context) {
  var op = context.operation
  var role = context.role
  var session = context.sessionId
  var key = Environments.roleKey(op, role)
  var prior = context.roleHistory[key] || null
  var ownedRoles = context.bindings.filter(function (row) {
    return (
      row.projectId === op.projectId &&
      row.checkoutId === op.checkoutId &&
      Environments.roleKey(row, row.role) === key &&
      row.sessionId === session
    )
  })
  var fresh =
    context.proof.bindings.filter(function (row) {
      return (
        row.projectId === op.projectId &&
        row.checkoutId === op.checkoutId &&
        Environments.roleKey(row, row.role) === key &&
        row.sessionId === session
      )
    })[0] || null
  var binding =
    fresh ||
    ownedRoles.filter(function (row) {
      return (
        prior &&
        prior.binding &&
        row.address === prior.binding.address &&
        row.pid === prior.binding.pid
      )
    })[0] ||
    ownedRoles[0] ||
    null
  var allClosed =
    ownedRoles.length > 0 &&
    ownedRoles.every(function (owned) {
      return context.proof.missing.some(function (closed) {
        return (
          closed.binding &&
          Environments.roleKey(closed.binding, closed.binding.role) ===
            Environments.roleKey(owned, owned.role) &&
          closed.binding.sessionId === session &&
          closed.binding.address === owned.address &&
          closed.binding.pid === owned.pid &&
          closed.identity.startTime === owned.evidence.startTime
        )
      })
    })
  var closure = allClosed
    ? context.proof.missing.filter(function (row) {
        return (
          row.binding &&
          binding &&
          Environments.roleKey(row.binding, row.binding.role) ===
            Environments.roleKey(binding, binding.role) &&
          row.binding.sessionId === session &&
          row.binding.address === binding.address &&
          row.binding.pid === binding.pid
        )
      })[0]
    : null
  var disposition = closure
    ? {
        state: "confirmed-missing",
        verified: true,
        projectId: op.projectId,
        checkoutId: op.checkoutId,
        environmentId: op.environmentId || null,
        role: role,
        sessionId: session,
        generation: op.generation,
        identity: closure.identity
      }
    : null
  return { prior: prior, fresh: fresh, binding: binding, disposition: disposition }
}

/**
 * Resolve the existing role policy and retained guards from explicit evidence.
 * A stale binding never inherits fresh verification. Unresolved submissions and
 * association holds block duplication unless this role requests a new window.
 * @param {RoleContext} context - operation, role, session, holds, attempts and windows
 * @param {RoleContext} evidence - selectRoleEvidence result
 * @returns {{action:string,code:?string}} existing focus, launch, hold or skip decision
 */
function resolveRoleDecision(context, evidence) {
  var op = context.operation
  var role = context.role
  var binding = evidence.binding
  var key = Environments.roleKey(op, role)
  var decision = Operations.roleDecision(
    role,
    op,
    evidence.fresh ||
      (binding
        ? Object.assign({}, binding, {
            evidence: Object.assign({}, binding.evidence, { processVerified: false })
          })
        : null),
    evidence.prior,
    context.windows,
    context.sessionId,
    evidence.disposition
  )
  if (
    decision.action === "launch" &&
    op.newWindowRole !== role &&
    (context.ownershipHolds[key] ||
      context.launchAttempts.some(function (attempt) {
        return (
          attempt.projectId === op.projectId &&
          attempt.checkoutId === op.checkoutId &&
          Environments.roleKey(attempt, attempt.role) === key &&
          attempt.sessionId === context.sessionId &&
          (attempt.state === "submitted" || attempt.state === "accepted")
        )
      }))
  )
    return { action: "hold", code: "OWNERSHIP_UNCONFIRMED" }
  return decision
}

if (typeof module !== "undefined") module.exports = { selectRoleEvidence, resolveRoleDecision }
