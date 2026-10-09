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

/** Format owner receipt time independently from lifecycle or connection freshness.
 * @param {any} receivedAt - task's last report receipt in seconds
 * @param {number} [now] - injected wall clock in milliseconds
 * @returns {TaskData} bounded absolute and relative report labels
 */
function reportTime(receivedAt, now) {
  /** @type {{lastReceivedAt:number|null,lastReportTime:string,lastReportLabel:string}} */
  var missing = {
    lastReceivedAt: null,
    lastReportTime: "Last report time not available",
    lastReportLabel: "Last report time not available"
  }
  if (typeof receivedAt !== "number" || !isFinite(receivedAt) || receivedAt < 0) return missing
  var date = new Date(receivedAt * 1000)
  if (!isFinite(date.getTime())) return missing
  var stamp = date.toISOString().slice(0, 19).replace("T", " ") + " UTC"
  var caption = "Last report " + stamp
  if (typeof now === "number" && isFinite(now)) {
    var age = Math.floor((now - receivedAt * 1000) / 1000)
    if (age < 0) caption += " (clock ahead)"
    else {
      var unit =
        age >= 86400
          ? Math.floor(age / 86400) + "d"
          : age >= 3600
            ? Math.floor(age / 3600) + "h"
            : age >= 60
              ? Math.floor(age / 60) + "m"
              : age + "s"
      caption = "Last report " + unit + " ago"
    }
  }
  return {
    lastReceivedAt: receivedAt,
    lastReportTime: "Received " + stamp,
    lastReportLabel: caption
  }
}

/** Build attention-first rows using exact registered checkout identities.
 * @param {TaskData} snapshot - projected owner state
 * @param {TaskData} [registry] - read-only project snapshot
 * @param {number} [now] - injected wall clock for receipt ages
 * @returns {Array<TaskData>} immutable task rows
 */
function rows(snapshot, registry, now) {
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
      var report = reportTime(task.lastReceivedAt, now)
      var canFocus = assigned && task.source === "native" && freshness === "connected"
      var canReopen = assigned && task.source === "native" && !!task.resumeCommand
      var primary = { kind: "", label: "Session unavailable", local: false }
      var secondary = { kind: "", label: "" }
      if (state === "finished")
        primary = { kind: "inspect-result", label: "View reported result", local: true }
      else if (state === "failed") {
        primary = { kind: "inspect-failure", label: "Inspect failure", local: true }
        if (canReopen) secondary = { kind: "reopen", label: "Reopen session" }
      } else if (state === "ready-for-review") {
        if (assigned) primary = { kind: "open-checkout", label: "Open checkout", local: false }
      } else if (state === "connection-lost") {
        if (canReopen) primary = { kind: "reopen", label: "Reopen session", local: false }
      } else if (state === "working" || state === "needs-input") {
        if (canFocus)
          primary = {
            kind: "focus",
            label: state === "needs-input" ? "Open session" : "Go to session",
            local: false
          }
        else if (canReopen) primary = { kind: "reopen", label: "Reopen session", local: false }
      }
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
        lastReceivedAt: report.lastReceivedAt,
        lastReportTime: report.lastReportTime,
        lastReportLabel: report.lastReportLabel,
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
        secondary: secondary,
        canDismiss: freshness === "connection-lost" || task.reportedState === "finished",
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
  var protectedSubmission = !!(
    op.submissionPending ||
    op.submissionUnconfirmed ||
    op.ownerUnconfirmed
  )
  var label = op.ownerUnconfirmed
    ? "Accepted operation owner unconfirmed"
    : protectedSubmission
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
    message: text((op.ownerLossError || error || op.error || {}).message),
    recovery: text((op.ownerLossError || error || op.error || {}).recovery)
  }
}
if (typeof module !== "undefined")
  module.exports = {
    text,
    reportTime,
    rows,
    reconcileSelection,
    step,
    destination,
    visible,
    operationView
  }
