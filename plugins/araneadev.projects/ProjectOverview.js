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
  var priority = function (/** @type {OverviewData} */ a, /** @type {OverviewData} */ b) {
    return Number(b.active) - Number(a.active) || Number(b.attention) - Number(a.attention)
  }
  var actionsProjection = actionRows(project.id, checkoutId, actions, nowMs, priority)
  result.services = actionsProjection.services
  result.checks = actionsProjection.checks
  var agentsProjection = agentRows(project, checkoutId, checkout.path, activity, nowMs)
  result.agents = agentsProjection.agents
  result.attention = actionsProjection.attention.concat(agentsProjection.attention)
  result.workspaces = savedWorkspaceRows(project, checkoutId, runtime)
  result.workspaces = environmentRows(project.id, runtime, priority).concat(result.workspaces)
  return result
}

/** Project saved actions and retained runs, collecting attention before row sorting.
 * @param {string} projectId - exact registered project
 * @param {string} checkoutId - exact selected checkout
 * @param {OverviewData} actions - shared action snapshot
 * @param {number} nowMs - presentation clock
 * @param {(a: OverviewData, b: OverviewData) => number} priority - presentation ordering
 * @returns {OverviewData} service, check and insertion-ordered attention rows
 */
function actionRows(projectId, checkoutId, actions, nowMs, priority) {
  /** @type {OverviewData} */
  var result = { services: [], checks: [], attention: [] }
  var definitions = Records.definitions(actions, projectId)
  var runs = Records.runs(actions, projectId, checkoutId)
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
        ? "Checked " +
          ageLabel((run.updatedAt || run.createdAt) * 1000, nowMs) +
          (service ? "" : " · Result applies to that run")
        : "Saved command",
      tooltip: run
        ? "Checked " +
          new Date((run.updatedAt || run.createdAt) * 1000).toLocaleString() +
          " · Run started " +
          new Date(run.createdAt * 1000).toLocaleString()
        : "",
      target: {
        projectId: projectId,
        checkoutId: checkoutId,
        actionId: id,
        revision: definition ? definition.revision : null,
        runId: run ? run.id : null
      },
      controls: controls,
      active: !!active,
      observationState: run ? run.submissionUnconfirmed ? "unconfirmed" : run.processState : "",
      attention:
        !!run &&
        (run.processState === "failed" ||
          run.processState === "unconfirmed" ||
          run.submissionUnconfirmed === true)
    }
    result[service ? "services" : "checks"].push(row)
    if (row.attention) result.attention.push(row)
  })
  result.services.sort(priority)
  result.checks.sort(priority)
  return result
}

/** Project reported agents with exact checkout and path associations.
 * @param {OverviewData} project - selected registration
 * @param {string} checkoutId - exact selected checkout
 * @param {string} checkoutPath - exact registered checkout path
 * @param {OverviewData} activity - shared task snapshot
 * @param {number} nowMs - presentation clock
 * @returns {OverviewData} agent and attention rows in task presentation order
 */
function agentRows(project, checkoutId, checkoutPath, activity, nowMs) {
  /** @type {OverviewData} */
  var result = { agents: [], attention: [] }
  var tasks = (activity.tasks || []).filter(function (/** @type {OverviewData} */ t) {
    var a = t.association || {}
    return (
      a.status === "registered" &&
      a.projectId === project.id &&
      a.checkoutId === checkoutId &&
      a.cwd === checkoutPath
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
      attention: task.attention,
      reportedState: task.reportedState,
      connected: task.freshnessLabel === "Connected",
      connectionLost: task.freshnessLabel === "Connection lost"
    }
    if (row.attention) result.attention.push(row)
    return row
  })
  return result
}

/** Project legacy workspace bindings followed by distinct saved associations.
 * @param {OverviewData} project - selected registration and associations
 * @param {string} checkoutId - exact selected checkout
 * @param {OverviewData} runtime - current owner snapshot
 * @returns {Array<OverviewData>} saved workspace destinations in discovery order
 */
function savedWorkspaceRows(project, checkoutId, runtime) {
  /** @type {Array<OverviewData>} */
  var bindings = (runtime.bindings || []).filter(function (/** @type {OverviewData} */ b) {
    return (
      !b.environmentId &&
      b.projectId === project.id &&
      b.checkoutId === checkoutId &&
      b.workspaceId > 0
    )
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
  return workspaces.map(function (id) {
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
        ? "Tools found · " +
          rows
            .map(function (/** @type {OverviewData} */ b) {
              return b.role
            })
            .join(", ")
        : "Saved location · tools not checked",
      detail: "Uses saved tools; Open may launch missing tools",
      target: { projectId: project.id, checkoutId: checkoutId },
      controls: [{ method: "open", label: "Open workspace" }]
    }
  })
}

/** Project launched environments across the project's checkouts with role recovery.
 * @param {string} projectId - exact registered project
 * @param {OverviewData} runtime - current owner snapshot
 * @param {(a: OverviewData, b: OverviewData) => number} priority - presentation ordering
 * @returns {Array<OverviewData>} environment rows ordered by state then launch time
 */
function environmentRows(projectId, runtime, priority) {
  var environments = (runtime.environments || []).filter(function (/** @type {OverviewData} */ e) {
    return e.projectId === projectId
  })
  var rows = environments.map(function (/** @type {OverviewData} */ e) {
    var operations = (runtime.operations || [])
      .filter(function (/** @type {OverviewData} */ op) {
        return op.environmentId === e.id && !op.environmentReturn
      })
      .sort(function (/** @type {OverviewData} */ a, /** @type {OverviewData} */ b) {
        return (b.generation || 0) - (a.generation || 0)
      })
    var observed = e.observedRoles || [],
      controls = [{ method: "return", label: "Return" }],
      details = []
    var labels = {
      code: "VS Code",
      nvim: "Neovim",
      kitty: "Kitty",
      alacritty: "Alacritty",
      foot: "Foot",
      ghostty: "Ghostty",
      codex: "Codex",
      claude: "Claude Code"
    }
    var raws = []
    var statuses = (e.profileSnapshot.roles || []).map(function (/** @type {string} */ role) {
      var operation = operations.find(function (/** @type {OverviewData} */ op) {
        return (op.steps || []).some(function (/** @type {OverviewData} */ step) { return step.role === role })
      })
      var step = operation && (operation.steps || []).find(function (/** @type {OverviewData} */ item) { return item.role === role })
      var status =
        observed.indexOf(role) >= 0
          ? "observed"
          : step && step.status === "failed"
            ? "failed"
            : "unconfirmed"
      if (status !== "observed") {
        controls.push({
          method: (status === "failed" ? "retry:" : "reobserve:") + role,
          label: (status === "failed" ? "Retry " : "Check ") + role
        })
        if (status === "unconfirmed")
          controls.push({ method: "newWindow:" + role, label: "New " + role + " window" })
      }
      var tool = (e.resolvedTools || {})[role + "Id"]
      var label = labels[tool] || tool || "Saved tool"
      details.push(
        role +
          " · " +
          label +
          " · " +
          stepLabel(status) +
          (step && (step.error || step.code)
            ? " · " + ((step.error && step.error.message) || step.code)
            : "")
      )
      raws.push(status)
      return role + " " + stepLabel(status)
    })
    return {
      title: e.profileSnapshot.name + " · Workspace " + e.workspaceId,
      status: statuses.join(" · "),
      detail: (e.checkoutSnapshot.branch || "detached") + " at launch · " + e.checkoutSnapshot.path,
      fullDetail: details.join("\n"),
      target: { projectId: projectId, environmentId: e.id },
      controls: controls,
      active: observed.length > 0,
      attention: raws.some(function (/** @type {string} */ value) {
        return value !== "observed"
      }),
      createdAt: e.createdAt || 0
    }
  })
  rows.sort(function (/** @type {OverviewData} */ a, /** @type {OverviewData} */ b) {
    return priority(a, b) || b.createdAt - a.createdAt
  })
  return rows
}

/** Plain word for one role step status; the raw value stays in the data.
 * @param {string} [status] - raw step status
 * @returns {string} display word
 */
function stepLabel(status) {
  /** @type {{[key:string]:string}} */
  var words = {
    observed: "open",
    unconfirmed: "not confirmed",
    uncertain: "not confirmed",
    failed: "failed",
    missing: "missing",
    skipped: "skipped"
  }
  return (status && words[status]) || "not available"
}

/** Plain phrase for an operation outcome (or state when there is no outcome yet).
 * @param {?string} [value] - raw outcome or state
 * @returns {string} display phrase
 */
function outcomeLabel(value) {
  /** @type {{[key:string]:string}} */
  var words = {
    observed: "opened",
    partial: "partly opened",
    failed: "failed",
    accepted: "starting",
    completed: "done",
    running: "running"
  }
  return (value && words[value]) || "not available"
}

if (typeof module !== "undefined") module.exports = { overview, stepLabel, outcomeLabel, activitySummary, ageLabel, gitFiles }

/** Summarize exact-checkout observations with navigation-only destinations.
 * @param {OverviewData} model - scoped Overview projection
 * @param {{actions?:boolean,agents?:boolean}} [availability] - current observer connections
 * @returns {Array<OverviewData>} separate action and reported-agent status chips
 */
function activitySummary(model, availability) {
  availability = availability || {}
  var services = availability.actions === false ? [] : model.services || []
  var checks = availability.actions === false ? [] : model.checks || []
  var actions = services.concat(checks)
  var agents = availability.agents === false ? [] : model.agents || []
  /** @type {Array<OverviewData>} */
  var summary = []
  if (availability.actions === false && (model.services || []).length + (model.checks || []).length)
    summary.push({ label: "Action status not available", section: "actions", attention: true })
  if (availability.agents === false && (model.agents || []).length)
    summary.push({ label: "Agent status not available", section: "agents", attention: true })
  var add = function (/** @type {Array<OverviewData>} */ rows, /** @type {string} */ singular, /** @type {string} */ plural, /** @type {string} */ section, /** @type {boolean} */ attention) {
    if (rows.length) summary.push({ label: rows.length + " " + (rows.length === 1 ? singular : plural), section: section, attention: attention })
  }
  add(actions.filter(function (r) { return r.observationState === "failed" }), "failed run", "failed runs", "actions", true)
  add(actions.filter(function (r) { return r.observationState === "unconfirmed" }), "run not confirmed", "runs not confirmed", "actions", true)
  var live = agents.filter(function (r) { return r.connected })
  add(live.filter(function (r) { return r.reportedState === "needs-input" }), "agent needs input (reported)", "agents need input (reported)", "agents", true)
  add(live.filter(function (r) { return r.reportedState === "ready-for-review" }), "agent ready for review (reported)", "agents ready for review (reported)", "agents", true)
  add(live.filter(function (r) { return r.reportedState === "failed" }), "agent failed (reported)", "agents failed (reported)", "agents", true)
  add(services.filter(function (r) { return r.observationState === "running" }), "service running", "services running", "actions", false)
  add(checks.filter(function (r) { return r.observationState === "running" }), "check running", "checks running", "actions", false)
  add(live.filter(function (r) { return r.reportedState === "working" }), "agent working (reported)", "agents working (reported)", "agents", false)
  add(checks.filter(function (r) { return r.observationState === "succeeded" }), "check succeeded (latest run)", "checks succeeded (latest runs)", "actions", false)
  add(agents.filter(function (r) { return r.connectionLost }), "agent disconnected", "agents disconnected", "agents", false)
  add(agents.filter(function (r) { return !r.connected && !r.connectionLost }), "agent connection not confirmed", "agent connections not confirmed", "agents", false)
  return summary
}

/** Compact freshness label without confusing receipt time with current correctness.
 * @param {?number} observedAt - observation wall milliseconds
 * @param {number} nowMs - injected wall clock
 * @returns {string} relative age or honest clock uncertainty
 */
function ageLabel(observedAt, nowMs) {
  if (typeof observedAt !== "number" || !isFinite(observedAt)) return "time not available"
  var age = Math.floor((nowMs - observedAt) / 1000)
  if (age < 0) return "clock ahead"
  if (age < 60) return "just now"
  if (age < 3600) return Math.floor(age / 60) + "m ago"
  if (age < 86400) return Math.floor(age / 3600) + "h ago"
  return Math.floor(age / 86400) + "d ago"
}

/** Select overlapping path groups from the collector's porcelain status fields.
 * @param {Array<OverviewData>} files - raw collector path records
 * @param {string} state - displayed file-count category
 * @returns {Array<OverviewData>} unchanged records, preserving exact paths
 */
function gitFiles(files, state) {
  return files.filter(function (file) {
    if (state === "conflict") return file.conflict === true
    var untracked = file.indexStatus === "?" && file.worktreeStatus === "?"
    if (state === "untracked") return untracked
    if (untracked) return false
    if (state === "staged") return !!file.indexStatus && file.indexStatus !== "."
    if (state === "unstaged") return !!file.worktreeStatus && file.worktreeStatus !== "."
    return false
  })
}
