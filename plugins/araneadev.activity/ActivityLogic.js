/** @typedef {{[key:string]:any}} ActivityData */

/** Validate public IDs without allowing option-shaped executable arguments.
 * @param {any} value - candidate ID
 * @returns {boolean} bounded printable non-option identifier
 */
function validId(value) {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 256 &&
    !/^[\s-]/.test(value) &&
    !value.split("").some(function (character) {
      return character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127
    })
  )
}

/** Fixed provider CLI resume identity; named sessions are deliberately unsupported.
 * @param {ActivityData} task - retained task
 * @returns {?string} display-only shell-quoted command
 */
function resumeCommand(task) {
  if (!task || !/^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/.test(task.providerSessionId))
    return null
  if (task.provider === "claude") return "claude --resume '" + task.providerSessionId + "'"
  var cwd = task.association && task.association.cwd
  if (
    task.provider !== "codex" ||
    typeof cwd !== "string" ||
    cwd[0] !== "/" ||
    cwd.split("").some(function (character) {
      return character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127
    })
  )
    return null
  return "codex resume '" + task.providerSessionId + "' --cd '" + cwd.replace(/'/g, "'\\''") + "'"
}

/** Locate the exact native epoch, never another session sharing a checkout.
 * @param {ActivityData} state - durable snapshot
 * @param {ActivityData} task - task identity
 * @returns {?ActivityData} retained epoch
 */
function sessionFor(state, task) {
  /** @type {Array<ActivityData>} */
  var sessions = state.sessions || []
  return (
    sessions.filter(function (s) {
      return (
        s.provider === task.provider &&
        s.providerSessionId === task.providerSessionId &&
        s.producerEpoch === task.producerEpoch
      )
    })[0] || null
  )
}

/** Project reported lifecycle independently from connection and verification.
 * Numeric now is wall milliseconds; clock objects additionally provide monotonic
 * milliseconds and bootId. Store projections remain authoritative for boot loss.
 * @param {ActivityData} state - last validated store snapshot
 * @param {number|ActivityData} now - injected current clock
 * @param {?ActivityData} registry - current registered checkouts, or null
 * @returns {ActivityData} immutable public view
 */
function project(state, now, registry) {
  var clock = typeof now === "number" ? { wall: now } : now
  /** @type {Array<ActivityData>} */
  var tasks = state.tasks || []
  /** @type {Array<ActivityData>} */
  var projects = (registry && registry.projects) || []
  return Object.assign({}, state, {
    tasks: tasks.map(function (task) {
      var s = sessionFor(state, task),
        c = s && s.connection
      var age = c ? clock.wall - c.receivedAt * 1000 : Infinity
      var lost =
        !c || !c.connected || age < 0 || age >= 60000 || task.freshness === "connection-lost"
      if (c && clock.bootId !== undefined) lost = lost || clock.bootId !== c.bootId
      if (c && clock.monotonic !== undefined)
        lost =
          lost ||
          clock.monotonic < c.monotonic * 1000 ||
          clock.monotonic - c.monotonic * 1000 >= 60000
      if (s && ((s.nativeMetadata || {}).inactiveTaskIds || []).indexOf(task.taskId) >= 0)
        lost = true
      var freshness = lost
        ? "connection-lost"
        : s.provenance && s.provenance.commandHash
          ? "connected"
          : "unconfirmed"
      var association = Object.assign({}, task.association)
      if (
        registry &&
        association.status === "registered" &&
        !projects.some(function (p) {
          return (
            p.id === association.projectId &&
            p.checkouts.some(function (/** @type {ActivityData} */ co) {
              return co.id === association.checkoutId && co.path === association.cwd
            })
          )
        })
      )
        association.status = "unavailable"
      var historical = ["finished", "failed", "ready-for-review"].indexOf(task.reportedState) >= 0
      return Object.assign({}, task, {
        // Presentation eligibility follows private exact-epoch evidence, not the
        // latest producer label. Runtime still independently proves every action.
        nativeSessionEligible: !!(
          s &&
          s.provenance &&
          s.provenance.commandHash &&
          s.nativeMetadata &&
          (s.nativeMetadata.observedHooks || []).indexOf("SessionStart") >= 0
        ),
        association: association,
        freshness: freshness,
        displayState: !historical && lost ? "connection-lost" : task.reportedState,
        verification: task.verification || { status: "unknown", summary: "", commands: [] },
        resumeCommand: resumeCommand(task),
        focusScope: "hosting-terminal",
        ownership: "unconfirmed"
      })
    })
  })
}
/** Stable attention identity excludes diagnostic/heartbeat/text updates.
 * @param {ActivityData} task - current task
 * @returns {string} identity
 */
function notificationKey(task) {
  return JSON.stringify([
    task.taskId,
    task.producerEpoch,
    task.reportedState,
    (task.blockers || [])
      .map(function (/** @type {ActivityData} */ b) {
        return b.id || b.blockerId || ""
      })
      .sort()
  ])
}

/** Bounded native notification text, without markup or control characters.
 * @param {any} value - display data
 * @param {number} limit - maximum length
 * @returns {string} plain text
 */
function notificationText(value, limit) {
  return String(value || "")
    .replace(/[<>]/g, "")
    .split("")
    .filter(function (c) {
      return c.charCodeAt(0) >= 32 && c.charCodeAt(0) !== 127
    })
    .join("")
    .slice(0, limit)
}

/** Initial snapshots are historical; suppressed transitions are consumed by the owner.
 * @param {?ActivityData} previous - last successfully read snapshot
 * @param {ActivityData} current - new successfully read snapshot
 * @param {boolean} suppressed - policy blocks emission
 * @returns {Array<ActivityData>} attention transitions only
 */
function notificationTransitions(previous, current, suppressed) {
  if (!previous || suppressed) return []
  return (current.tasks || [])
    .filter(function (/** @type {ActivityData} */ task) {
      if (["needs-input", "ready-for-review", "failed"].indexOf(task.reportedState) < 0)
        return false
      var before = (previous.tasks || []).filter(function (/** @type {ActivityData} */ old) {
        return old.taskId === task.taskId
      })[0]
      return !before || notificationKey(before) !== notificationKey(task)
    })
    .map(function (/** @type {ActivityData} */ task) {
      /** @type {{[key:string]:string}} */
      var labels = {
        "needs-input": "Needs input",
        "ready-for-review": "Ready for review",
        failed: "Failed"
      }
      return {
        taskId: task.taskId,
        key: notificationKey(task),
        title: "Aranea · " + labels[task.reportedState],
        body: notificationText(
          task.description || task.summary || "Agent task needs attention",
          512
        )
      }
    })
}
if (typeof module !== "undefined")
  module.exports = {
    validId,
    resumeCommand,
    sessionFor,
    project,
    notificationKey,
    notificationTransitions,
    notificationText
  }
