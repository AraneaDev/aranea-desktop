/** @typedef {{[key:string]:any}} TaskData */

/** Bound display text; it never becomes executable input.
 * @param {any} value - provider text
 * @param {number} [limit] - maximum retained characters
 * @returns {string} bounded plaintext
 */
function text(value, limit) {
  var s = typeof value === "string" ? value : ""
  var n = limit || 4096
  return s.length > n ? s.slice(0, n) + "…" : s
}

/** Build attention-first rows using exact registered checkout identities.
 * @param {TaskData} snapshot - projected owner state
 * @param {TaskData} [registry] - read-only project snapshot
 * @returns {Array<TaskData>} immutable task rows
 */
function rows(snapshot, registry) {
  /** @type {{[key:string]:string}} */
  var labels = {
    working: "Working",
    "needs-input": "Needs input",
    "ready-for-review": "Ready for review",
    failed: "Failed",
    finished: "Finished",
    "connection-lost": "Connection lost"
  }
  /** @type {{[key:string]:number}} */
  var priorities = {
    "needs-input": 0,
    "ready-for-review": 1,
    failed: 2,
    working: 3,
    "connection-lost": 4,
    finished: 5
  }
  /** @type {Array<TaskData>} */
  var projects = (registry || {}).projects || []
  /** @type {Array<TaskData>} */
  var tasks = (snapshot || {}).tasks || []
  return tasks
    .map(function (task) {
      var a = task.association || {}
      var p = projects.filter(function (p) {
        return p.id === a.projectId
      })[0]
      var co =
        p &&
        (p.checkouts || []).filter(function (/** @type {TaskData} */ c) {
          return c.id === a.checkoutId && c.path === a.cwd
        })[0]
      var assigned = a.status === "registered" && !!co
      var state = task.displayState || task.reportedState
      var freshness = task.freshness || "unconfirmed"
      var attention =
        ["needs-input", "ready-for-review", "failed"].indexOf(state) >= 0 &&
        freshness !== "connection-lost"
      var verification = task.verification || {}
      var primary = { kind: "", label: "Session unavailable" }
      if (assigned && task.source === "native" && freshness === "connected")
        primary = { kind: "focus", label: "Go to session" }
      else if (assigned && task.resumeCommand) primary = { kind: "reopen", label: "Reopen session" }
      var context = [
        assigned
          ? text(p.name, 256)
          : a.status === "unassigned"
            ? "Unassigned checkout"
            : "Checkout unavailable",
        assigned ? text(co.branch, 512) : "",
        text(a.cwd, 4096)
      ]
        .filter(Boolean)
        .join(" · ")
      return {
        key: task.taskId,
        providerLabel:
          task.provider === "claude"
            ? "Claude Code"
            : task.provider === "codex"
              ? "Codex"
              : text(task.provider, 80),
        summary: text(task.description, 512) || "Agent task",
        stateLabel: labels[state] || "Status not reported",
        reportedLabel: labels[task.reportedState] || "Status not reported",
        priority: priorities[state] === undefined ? 6 : priorities[state],
        attention: attention,
        freshnessLabel:
          freshness === "connected"
            ? "Connected"
            : freshness === "connection-lost"
              ? "Connection lost"
              : "Connection unconfirmed",
        context: context,
        path: text(a.cwd),
        branch: assigned ? text(co.branch, 512) : "",
        projectLabel: assigned ? text(p.name, 256) : "",
        associationLabel: assigned
          ? "Registered checkout"
          : a.status === "unassigned"
            ? "Unassigned checkout"
            : "Checkout unavailable",
        assigned: assigned,
        result: text(task.result),
        question: text(task.question),
        diagnostics: (task.diagnostics || [])
          .map(function (/** @type {TaskData} */ d) {
            return text(d.summary)
          })
          .join("\n")
          .slice(0, 4096),
        blockers: (task.blockers || [])
          .map(function (/** @type {TaskData} */ b) {
            return text(b.summary || b.question)
          })
          .filter(Boolean)
          .join("\n")
          .slice(0, 4096),
        verificationLabel:
          verification.status === "reported-pass"
            ? "Verification reported passed"
            : verification.status === "reported-fail"
              ? "Verification reported failed"
              : "Verification not reported",
        verificationSummary: text(verification.summary),
        verificationCommands: (verification.commands || [])
          .map(function (/** @type {any} */ c) {
            return text(c, 512)
          })
          .join("\n"),
        primary: primary,
        canDismiss:
          freshness === "connection-lost" ||
          ["finished", "failed", "ready-for-review"].indexOf(state) >= 0,
        resumeCommand: text(task.resumeCommand, 512),
        nativeId: text(task.providerSessionId, 256),
        epoch: text(task.producerEpoch, 256)
      }
    })
    .sort(function (a, b) {
      return a.priority - b.priority || String(a.key).localeCompare(String(b.key))
    })
}

/** Preserve an identity only while that task remains present.
 * @param {string} key - retained task key
 * @param {Array<TaskData>} list - current rows
 * @returns {{key:string}} reconciled selection
 */
function reconcileSelection(key, list) {
  return {
    key: list.some(function (r) {
      return r.key === key
    })
      ? key
      : ""
  }
}

/** First keyboard activation reveals; removed targets never activate a replacement.
 * @param {Array<string>} keys - stable current targets
 * @param {string} key - retained target
 * @param {boolean} active - previously confirmed keyboard cursor
 * @param {number} direction - zero activates; otherwise moves
 * @returns {{key:string,activate:boolean}} next cursor
 */
function step(keys, key, active, direction) {
  var index = keys.indexOf(key)
  if (!active || index < 0) return { key: index >= 0 ? key : keys[0] || "", activate: false }
  return {
    key: keys[Math.max(0, Math.min(keys.length - 1, index + direction))] || "",
    activate: direction === 0 && !!key
  }
}

/** Choose a remembered destination or the appropriate initial tab.
 * @param {string} remembered - user choice
 * @param {Array<TaskData>} list - task rows
 * @param {number} usageCount - recorded usage providers
 * @returns {string} Tasks or Usage destination
 */
function destination(remembered, list, usageCount) {
  if (remembered === "tasks" || remembered === "usage") return remembered
  return list.some(function (r) {
    return r.attention
  }) ||
    (list.length > 0 && usageCount === 0)
    ? "tasks"
    : "usage"
}

/** Show task-only sessions without changing Usage discovery.
 * @param {number} usageCount - recorded usage providers
 * @param {Array<TaskData>} list - task rows
 * @returns {boolean} bar visibility
 */
function visible(usageCount, list) {
  return usageCount > 0 || list.length > 0
}

/** Retain independent acceptance and observation status; never prescribe a repeat.
 * @param {?TaskData} operation - retained owner operation
 * @param {?TaskData} error - actionable client error
 * @param {boolean} pending - client observing
 * @returns {TaskData} display and read-only recovery controls
 */
function operationView(operation, error, pending) {
  var op = operation || {}
  var protectedSubmission = !!(op.submissionPending || op.submissionUnconfirmed)
  var label = protectedSubmission
    ? "Launch acceptance unconfirmed"
    : pending || op.state === "accepted" || op.state === "observing"
      ? "Observing accepted operation"
      : op.outcome === "observed"
        ? "Observed"
        : op.outcome === "partial"
          ? "Partially observed"
          : op.outcome === "failed"
            ? "Action failed"
            : ""
  return {
    label: label,
    protected: protectedSubmission,
    steps: (op.steps || [])
      .map(function (/** @type {TaskData} */ step) {
        var role =
          step.role === "session"
            ? "Native session"
            : ["terminal", "hosting-terminal"].indexOf(step.role) >= 0
              ? "Hosting terminal"
              : step.role === "dismiss"
                ? "Dismissal"
                : "Checkout preparation"
        return (
          role +
          ": " +
          (["observed", "unconfirmed", "failed", "pending", "accepted"].indexOf(step.status) >= 0
            ? step.status
            : "unconfirmed")
        )
      })
      .join("\n"),
    canReobserve:
      !!op.id &&
      op.action === "reopen" &&
      op.outcome === "partial" &&
      !pending &&
      !protectedSubmission &&
      !op.reconnectRequired &&
      !(error && error.code === "OPERATION_LOST"),
    canReconnect: !!op.id && !pending,
    message: text(error ? error.message : (op.error || {}).message),
    recovery: text(error ? error.recovery : (op.error || {}).recovery)
  }
}
if (typeof module !== "undefined")
  module.exports = { text, rows, reconcileSelection, step, destination, visible, operationView }
