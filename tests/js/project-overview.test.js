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
    files: [{ path: "same", staged: true, unstaged: true }]
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
