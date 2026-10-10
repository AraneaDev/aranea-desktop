/** @typedef {{[key:string]:any}} ActionData */

// Cleanup uncertainty protects even a proven main-process exit.
/**
 * Includes unresolved unit cleanup in the durable protection predicate.
 * @param {ActionData | null} run - retained immutable run and observations
 * @returns {boolean} whether replacement/removal must remain blocked
 */
function protectedRun(run) {
  return (
    !!run &&
    (run.submissionUnconfirmed === true ||
      ["pending", "running", "unconfirmed"].indexOf(run.processState) >= 0)
  )
}

// Local projections retain authoritative IDs/revisions and exact checkout scope.
/**
 * Selects stable saved definitions without changing their identity/revision.
 * @param {ActionData} state - backend state
 * @param {string} projectId - exact registered project
 * @returns {Array<ActionData>} saved definitions
 */
function definitions(state, projectId) {
  /** @type {Array<ActionData>} */
  var rows = (state && state.definitions) || []
  return rows.filter(function (row) {
    return row.projectId === projectId
  })
}
/**
 * Selects retained runs for an exact project and optional checkout.
 * @param {ActionData} state - backend state
 * @param {string} projectId - exact project
 * @param {string} checkoutId - exact checkout, or empty for every checkout
 * @returns {Array<ActionData>} newest-first retained runs
 */
function runs(state, projectId, checkoutId) {
  /** @type {Array<ActionData>} */
  var rows = (state && state.runs) || []
  return rows
    .filter(function (row) {
      return row.projectId === projectId && (!checkoutId || row.checkoutId === checkoutId)
    })
    .sort(function (a, b) {
      return b.createdAt - a.createdAt
    })
}
/**
 * Finds protected immutable intent, including terminal cleanup uncertainty.
 * @param {ActionData} state - backend state
 * @param {string} projectId - exact project
 * @param {string} checkoutId - exact checkout
 * @param {string} actionId - stable definition ID
 * @returns {ActionData | null} protected receipt or null
 */
function activeRun(state, projectId, checkoutId, actionId) {
  return (
    runs(state, projectId, checkoutId).filter(function (row) {
      return row.actionId === actionId && protectedRun(row)
    })[0] || null
  )
}
/**
 * Projects preview eligibility; backend must freshly prove ownership before opening.
 * @param {ActionData | null} run - retained run
 * @returns {boolean} current running service has a pinned configured preview
 */
function canOpenPreview(run) {
  return (
    !!run &&
    run.processState === "running" &&
    !run.submissionUnconfirmed &&
    !!run.invocationId &&
    !!run.definitionSnapshot &&
    run.definitionSnapshot.kind === "service" &&
    !!run.definitionSnapshot.previewUrl
  )
}

// A command exit is its own result only; preview reachability is independent.
/**
 * Labels only this process result with independent preview evidence.
 * @param {ActionData | null} run - retained run
 * @returns {string} plain display text, never task verification
 */
function runLabel(run) {
  if (!run) return "No run"
  /** @type {{[key:string]:string}} */
  var labels = {
    pending: "Pending",
    running: "Running",
    succeeded: "Command succeeded",
    failed: "Command failed",
    stopped: "Stopped",
    unconfirmed: "Unconfirmed"
  }
  var process = labels[run.processState] || "Unavailable"
  if (
    run.submissionUnconfirmed &&
    ["succeeded", "failed", "stopped"].indexOf(run.processState) >= 0
  )
    process += " · Cleanup unconfirmed"
  var preview = "Preview not checked"
  if (run.readiness === "reachable")
    preview =
      run.processState === "running" && !run.submissionUnconfirmed
        ? "Preview reachable"
        : "Previous preview reachability"
  if (run.readiness === "unreachable")
    preview =
      run.processState === "running" && !run.submissionUnconfirmed
        ? "Preview unreachable"
        : "Previous preview unreachable"
  return process + " · " + preview
}

if (typeof module !== "undefined")
  module.exports = { protectedRun, definitions, runs, activeRun, canOpenPreview, runLabel }
