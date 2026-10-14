.import "ProjectActionRecords.js" as Records
.import "../araneadev.agents/AgentTasksLogic.js" as Tasks
/** @typedef {{[key:string]:any}} OverviewData */

/** Compose exact-checkout observations without reading or executing anything.
 * @param {?OverviewData} project - selected registration
 * @param {string} checkoutId - exact selection
 * @param {?OverviewData} git - cached Git observation
 * @param {OverviewData} actions - shared action snapshot
 * @param {OverviewData} activity - shared task snapshot
 * @param {OverviewData} runtime - current owner snapshot
 * @param {number} nowMs - presentation clock
 * @returns {OverviewData} compact rows retaining authoritative targets
 */
function overview(project, checkoutId, git, actions, activity, runtime, nowMs) {
  /** @type {OverviewData} */
  var result = { git: null, services: [], checks: [], agents: [], workspaces: [], attention: [] }
  if (!project || !checkoutId) return result
  var checkout = (project.checkouts || []).filter(function (/** @type {OverviewData} */ c) {
    return c.id === checkoutId
  })[0]
  if (!checkout) return result
  if (git && git.projectId === project.id && git.checkoutId === checkoutId) result.git = git
  var definitions = Records.definitions(actions, project.id)
  var runs = Records.runs(actions, project.id, checkoutId)
  var ids = definitions.map(function (d) {
    return d.id
  })
  runs.forEach(function (run) {
    if (ids.indexOf(run.actionId) < 0) ids.push(run.actionId)
  })
  ids.forEach(function (id) {
    var definition = definitions.filter(function (d) {
      return d.id === id
    })[0]
    var retained = runs.filter(function (r) {
      return r.actionId === id
    })
    var active = retained.filter(Records.protectedRun)[0]
    var run = active || retained[0]
    var display = definition || (run && run.definitionSnapshot) || {}
    var service = display.kind === "service"
    var controls = []
    if (run && Records.canOpenPreview(run))
      controls.push({ method: "open-preview", label: "Open preview" })
    if (active) controls.push({ method: "stop", label: "Stop" })
    else if (definition) controls.push({ method: "start", label: service ? "Start" : "Run" })
    if (run) controls.push({ method: "logs", label: "View output" })
    var row = {
      title: display.name || (service ? "Service" : "Command"),
      status: run
        ? (service || active ? "" : "Latest run · ") +
          Records.runLabel(run).split(" · Preview not checked")[0]
        : "Not run in this checkout",
      detail: run
        ? "Observed " +
          ageLabel((run.updatedAt || run.createdAt) * 1000, nowMs) +
          (service ? "" : " · Result applies to that run")
        : "Saved command",
      tooltip: run
        ? "Observed " +
          new Date((run.updatedAt || run.createdAt) * 1000).toLocaleString() +
          " · Run started " +
          new Date(run.createdAt * 1000).toLocaleString()
        : "",
      target: {
        projectId: project.id,
        checkoutId: checkoutId,
        actionId: id,
        revision: definition ? definition.revision : null,
        runId: run ? run.id : null
      },
      controls: controls,
      active: !!active,
      attention:
        !!run &&
        (run.processState === "failed" ||
          run.processState === "unconfirmed" ||
          run.submissionUnconfirmed === true)
    }
    result[service ? "services" : "checks"].push(row)
    if (row.attention) result.attention.push(row)
  })
  var priority = function (/** @type {OverviewData} */ a, /** @type {OverviewData} */ b) {
    return Number(b.active) - Number(a.active) || Number(b.attention) - Number(a.attention)
  }
  result.services.sort(priority)
  result.checks.sort(priority)
  var tasks = (activity.tasks || []).filter(function (/** @type {OverviewData} */ t) {
    var a = t.association || {}
    return (
      a.status === "registered" &&
      a.projectId === project.id &&
      a.checkoutId === checkoutId &&
      a.cwd === checkout.path
    )
  })
  result.agents = Tasks.rows({ tasks: tasks }, { projects: [project] }, nowMs).map(function (task) {
    var primary = task.primary
    var controls = []
    if (primary.kind && !primary.local && primary.kind !== "reopen")
      controls.push({
        method: primary.kind,
        label:
          primary.kind === "focus"
            ? task.reportedState === "needs-input"
              ? "Answer"
              : "Open session"
            : "Review"
      })
    var row = {
      title: task.summary,
      status: task.reportedLabel + " (reported) · " + task.freshnessLabel,
      detail: task.verificationLabel + " · " + task.lastReportLabel,
      target: { taskId: task.key },
      controls: controls,
      attention: task.attention
    }
    if (row.attention) result.attention.push(row)
    return row
  })
  /** @type {Array<OverviewData>} */
  var bindings = (runtime.bindings || []).filter(function (/** @type {OverviewData} */ b) {
    return b.projectId === project.id && b.checkoutId === checkoutId && b.workspaceId > 0
  })
  /** @type {Array<number>} */
  var workspaces = []
  bindings.forEach(function (/** @type {OverviewData} */ b) {
    if (workspaces.indexOf(b.workspaceId) < 0) workspaces.push(b.workspaceId)
  })
  ;(project.associations || []).forEach(function (/** @type {OverviewData} */ association) {
    if (
      association.checkoutId === checkoutId &&
      association.workspaceId > 0 &&
      workspaces.indexOf(association.workspaceId) < 0
    )
      workspaces.push(association.workspaceId)
  })
  result.workspaces = workspaces.map(function (id) {
    var rows = bindings.filter(function (/** @type {OverviewData} */ b) {
      return b.workspaceId === id
    })
    var confirmed =
      rows.length > 0 &&
      !!runtime.sessionId &&
      rows.every(function (/** @type {OverviewData} */ b) {
        return b.sessionId === runtime.sessionId
      })
    return {
      title: "Workspace " + id,
      status: confirmed
        ? "Observed tools · " +
          rows
            .map(function (/** @type {OverviewData} */ b) {
              return b.role
            })
            .join(", ")
        : "Saved location · tools unconfirmed",
      detail: "Uses saved tools; Open may launch missing tools",
      target: { projectId: project.id, checkoutId: checkoutId },
      controls: [{ method: "open", label: "Open workspace" }]
    }
  })
  return result
}

if (typeof module !== "undefined") module.exports = { overview, ageLabel }

/** Compact freshness label without confusing receipt time with current correctness.
 * @param {?number} observedAt - observation wall milliseconds
 * @param {number} nowMs - injected wall clock
 * @returns {string} relative age or honest clock uncertainty
 */
function ageLabel(observedAt, nowMs) {
  if (typeof observedAt !== "number" || !isFinite(observedAt)) return "time unavailable"
  var age = Math.floor((nowMs - observedAt) / 1000)
  if (age < 0) return "clock ahead"
  if (age < 60) return "just now"
  if (age < 3600) return Math.floor(age / 60) + "m ago"
  if (age < 86400) return Math.floor(age / 3600) + "h ago"
  return Math.floor(age / 86400) + "d ago"
}
