const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const logic = loadPragma("plugins/araneadev.projects/ProjectOverview.js")
const project = { id: "p", name: "Repo", checkouts: [{ id: "c", path: "/repo", branch: "main" }] }
const def = { id: "a", projectId: "p", revision: 3, name: "Tests", kind: "command" }
const run = {
  id: "r",
  projectId: "p",
  checkoutId: "c",
  actionId: "a",
  createdAt: 1,
  processState: "failed",
  definitionSnapshot: def
}
/** Compose fixture observations through the production projector. */
function model(actions = {}, activity = {}, runtime = {}, git = null, checkout = "c") {
  return logic.overview(project, checkout, git, actions, activity, runtime, 100000)
}

test("activity summary links observed actions and reported agent input without counting another checkout", () => {
  const service = { ...def, id: "server", name: "Dev server", kind: "service" }
  const task = {
    taskId: "t",
    provider: "codex",
    description: "Fix layout",
    reportedState: "needs-input",
    freshness: "connected",
    association: { status: "registered", projectId: "p", checkoutId: "c", cwd: "/repo" }
  }
  const result = model(
    {
      runs: [
        run,
        {
          ...run,
          id: "server-run",
          actionId: "server",
          processState: "running",
          invocationId: "inv",
          definitionSnapshot: service
        }
      ]
    },
    {
      tasks: [
        task,
        { ...task, taskId: "other", association: { ...task.association, checkoutId: "other" } }
      ]
    }
  )
  assert.deepEqual(JSON.parse(JSON.stringify(logic.activitySummary(result))), [
    { label: "1 failed run", section: "actions", attention: true },
    { label: "1 agent needs input (reported)", section: "agents", attention: true },
    { label: "1 service running", section: "actions", attention: false }
  ])
})

test("activity summary never presents lost or uncertain task connections as live work", () => {
  const task = {
    taskId: "t",
    provider: "codex",
    reportedState: "working",
    description: "Fix layout",
    association: { status: "registered", projectId: "p", checkoutId: "c", cwd: "/repo" }
  }
  const result = model(
    { runs: [{ ...run, processState: "unconfirmed" }] },
    {
      tasks: [
        { ...task, freshness: "connection-lost", displayState: "connection-lost" },
        { ...task, taskId: "u", freshness: "unconfirmed" }
      ]
    }
  )
  const summary = JSON.parse(JSON.stringify(logic.activitySummary(result)))
  assert.deepEqual(summary, [
    { label: "1 run unconfirmed", section: "actions", attention: true },
    { label: "1 agent disconnected", section: "agents", attention: false },
    { label: "1 agent connection unconfirmed", section: "agents", attention: false }
  ])
  assert.deepEqual(
    JSON.parse(JSON.stringify(logic.activitySummary(model({}, {}, {}, null, "missing")))),
    []
  )
})

test("ready-for-review stays distinct from verification and completed check history", () => {
  const result = model(
    { runs: [{ ...run, processState: "succeeded" }] },
    {
      tasks: [
        {
          taskId: "t",
          provider: "codex",
          reportedState: "ready-for-review",
          freshness: "connected",
          verification: { status: "not-reported" },
          association: { status: "registered", projectId: "p", checkoutId: "c", cwd: "/repo" }
        }
      ]
    }
  )
  assert.deepEqual(JSON.parse(JSON.stringify(logic.activitySummary(result))), [
    { label: "1 agent ready for review (reported)", section: "agents", attention: true },
    { label: "1 check succeeded (latest run)", section: "actions", attention: false }
  ])
})

test("unavailable observers replace retained live chips until a fresh read succeeds", () => {
  const result = model(
    { runs: [{ ...run, processState: "running", invocationId: "inv" }] },
    {
      tasks: [
        {
          taskId: "t",
          provider: "codex",
          reportedState: "working",
          freshness: "connected",
          association: { status: "registered", projectId: "p", checkoutId: "c", cwd: "/repo" }
        }
      ]
    }
  )
  assert.deepEqual(
    JSON.parse(JSON.stringify(logic.activitySummary(result, { actions: false, agents: false }))),
    [
      { label: "Action status unavailable", section: "actions", attention: true },
      { label: "Agent status unavailable", section: "agents", attention: true }
    ]
  )
  assert.deepEqual(
    JSON.parse(JSON.stringify(logic.activitySummary(result, { actions: true, agents: true }))),
    [
      { label: "1 check running", section: "actions", attention: false },
      { label: "1 agent working (reported)", section: "agents", attention: false }
    ]
  )
})
test("exact checkout scope prevents stale outcomes and Git crossing selection", () => {
  assert.equal(model({ runs: [run] }, {}, {}, { projectId: "p", checkoutId: "old" }).git, null)
  assert.equal(model({ runs: [run] }, {}, {}, null, "new").checks.length, 0)
  assert.equal(model({ runs: [run] }).checks[0].target.runId, "r")
})
test("newest command result per saved action carries current definition revision", () => {
  const result = model({
    definitions: [def],
    runs: [
      run,
      { ...run, id: "new", createdAt: 2, processState: "succeeded" },
      { ...run, id: "other", checkoutId: "other", createdAt: 3 }
    ]
  })
  assert.equal(result.checks.length, 1)
  assert.equal(result.checks[0].target.runId, "new")
  assert.equal(result.checks[0].target.revision, 3)
  assert.match(result.checks[0].status, /Latest run.*succeeded/)
})
test("active services precede completed history without merging preview and process outcomes", () => {
  const service = { ...def, kind: "service" }
  const result = model({
    definitions: [service],
    runs: [
      { ...run, definitionSnapshot: service },
      {
        ...run,
        id: "live",
        actionId: "b",
        createdAt: 0,
        processState: "running",
        invocationId: "inv",
        definitionSnapshot: { ...service, id: "b", previewUrl: "http://localhost" }
      }
    ]
  })
  assert.equal(result.services[0].target.runId, "live")
  assert.ok(result.services[0].controls.some((c) => c.method === "open-preview"))
  assert.ok(result.services[0].controls.some((c) => c.method === "stop"))
})
test("reported agents preserve connection uncertainty and exact checkout association", () => {
  const task = {
    taskId: "t",
    description: "Fix layout",
    provider: "codex",
    reportedState: "needs-input",
    freshness: "connected",
    nativeSessionEligible: true,
    association: { status: "registered", projectId: "p", checkoutId: "c", cwd: "/repo" },
    verification: { status: "reported-pass" }
  }
  const result = model(
    {},
    {
      tasks: [
        task,
        { ...task, taskId: "wrong", association: { ...task.association, checkoutId: "other" } }
      ]
    }
  )
  assert.equal(result.agents.length, 1)
  assert.match(result.agents[0].status, /reported/i)
  assert.match(result.agents[0].detail, /Verification reported passed/)
  assert.equal(result.agents[0].controls[0].method, "focus")
  assert.equal(result.agents[0].controls[0].label, "Answer")
  const lost = model(
    {},
    { tasks: [{ ...task, freshness: "connection-lost", displayState: "connection-lost" }] }
  )
  assert.match(lost.agents[0].status, /Connection lost/)
  assert.ok(!lost.agents[0].controls.some((c) => c.method === "focus"))
})
test("legacy workspaces scope exact bindings and offer ordinary Open, never Return", () => {
  const result = model(
    {},
    {},
    {
      bindings: [
        { projectId: "p", checkoutId: "c", workspaceId: 4, role: "editor" },
        { projectId: "p", checkoutId: "other", workspaceId: 9, role: "terminal" }
      ]
    }
  )
  assert.equal(result.workspaces.length, 1)
  assert.match(result.workspaces[0].title, /Workspace 4/)
  assert.equal(result.workspaces[0].controls[0].label, "Open workspace")
  assert.equal(result.workspaces[0].target.checkoutId, "c")
})
test("empty summaries are inert and valid Git retains overlapping file counts", () => {
  const git = {
    projectId: "p",
    checkoutId: "c",
    observedAt: 90,
    counts: { staged: 1, unstaged: 1 },
    files: [
      { path: "same", originalPath: null, indexStatus: "M", worktreeStatus: "M", conflict: false }
    ]
  }
  const result = model({}, {}, {}, git)
  assert.equal(result.git, git)
  assert.equal(
    result.services.length + result.checks.length + result.agents.length + result.workspaces.length,
    0
  )
})

test("saved workspace locations remain discoverable without claiming live tools", () => {
  const result = logic.overview(
    { ...project, associations: [{ checkoutId: "c", workspaceId: 7 }] },
    "c",
    null,
    {},
    {},
    {},
    1000
  )
  assert.equal(result.workspaces.length, 1)
  assert.match(result.workspaces[0].status, /unconfirmed/)
})

test("observation age stays compact and marks invalid or future clocks", () => {
  assert.equal(logic.ageLabel(60000, 120000), "1m ago")
  assert.equal(logic.ageLabel(0, 7200000), "2h ago")
  assert.equal(logic.ageLabel(10, 0), "clock ahead")
  assert.equal(logic.ageLabel(null, 0), "time unavailable")
})

// Missing or mutually exclusive grouping would hide paths or undercount overlap.
test("porcelain path grouping follows collector counts and retains literal path identities", () => {
  const files = [
    { path: "mixed", originalPath: null, indexStatus: "M", worktreeStatus: "M", conflict: false },
    {
      path: 'new\n<>&"',
      originalPath: null,
      indexStatus: "?",
      worktreeStatus: "?",
      conflict: false
    },
    { path: "conflict", originalPath: null, indexStatus: "U", worktreeStatus: "U", conflict: true },
    {
      path: "renamed",
      originalPath: "original",
      indexStatus: "R",
      worktreeStatus: ".",
      conflict: false
    },
    { path: "deleted", originalPath: null, indexStatus: ".", worktreeStatus: "D", conflict: false }
  ]
  assert.deepEqual(
    Array.from(logic.gitFiles(files, "staged"), (f) => f.path),
    ["mixed", "conflict", "renamed"]
  )
  assert.deepEqual(
    Array.from(logic.gitFiles(files, "unstaged"), (f) => f.path),
    ["mixed", "conflict", "deleted"]
  )
  assert.deepEqual(
    Array.from(logic.gitFiles(files, "untracked"), (f) => f.path),
    ['new\n<>&"']
  )
  assert.deepEqual(
    Array.from(logic.gitFiles(files, "conflict"), (f) => f.path),
    ["conflict"]
  )
  assert.equal(logic.gitFiles(files, "staged")[2], files[3])
  assert.equal(logic.gitFiles(files, "other").length, 0)
  assert.equal(logic.gitFiles([], "staged").length, 0)
})

test("environments retain snapshots across checkout selection and expose exact Return and role recovery", () => {
  const environment = {
    id: "e-one",
    projectId: "p",
    checkoutId: "old",
    workspaceId: 3,
    createdAt: 20,
    profileSnapshot: { name: "Original terminal", roles: ["terminal", "agent"] },
    checkoutSnapshot: { path: "/old", branch: "feature" },
    resolvedTools: { terminalId: "kitty", agentId: "codex" },
    observedRoles: ["terminal"],
    status: "observed"
  }
  const result = model(
    {},
    {},
    {
      environments: [environment],
      operations: [
        {
          environmentId: "e-one",
          state: "completed",
          outcome: "partial",
          steps: [{ role: "agent", status: "failed", error: { message: "Provider unavailable" } }]
        }
      ]
    }
  )
  assert.equal(result.workspaces.length, 1)
  const row = result.workspaces[0]
  assert.equal(row.title, "Original terminal · Workspace 3")
  assert.match(row.detail, /feature.*launch|launch.*feature/)
  assert.match(row.status, /terminal.*observed.*agent.*failed/i)
  assert.deepEqual(JSON.parse(JSON.stringify(row.target)), {
    projectId: "p",
    environmentId: "e-one"
  })
  assert.ok(row.controls.some((c) => c.method === "return" && c.label === "Return"))
  assert.ok(row.controls.some((c) => c.method === "retry:agent"))
  assert.match(row.fullDetail, /Kitty.*Codex.*Provider unavailable/s)
})

test("recovering one environment role retains the latest outcome for its other roles", () => {
  const environment = {
    id: "e",
    projectId: "p",
    checkoutId: "c",
    workspaceId: 3,
    profileSnapshot: { name: "Work", roles: ["editor", "agent"] },
    checkoutSnapshot: { path: "/repo", branch: "main" },
    resolvedTools: { editorId: "code", agentId: "codex" },
    observedRoles: ["editor"]
  }
  const result = model(
    {},
    {},
    {
      environments: [environment],
      operations: [
        { environmentId: "e", generation: 1, steps: [{ role: "agent", status: "failed" }] },
        { environmentId: "e", generation: 2, steps: [{ role: "editor", status: "observed" }] }
      ]
    }
  )
  assert.ok(result.workspaces[0].controls.some((c) => c.method === "retry:agent"))
})
