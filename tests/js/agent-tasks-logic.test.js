const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = "../../plugins/araneadev.agents/AgentTasksLogic.js"
const logic = fs.existsSync("plugins/araneadev.agents/AgentTasksLogic.js") ? require(path) : {}
const task = (id, state, extra = {}) => ({
  taskId: id,
  provider: "claude",
  description: "Fix <b>bug</b>",
  reportedState: state,
  displayState: state,
  freshness: "connected",
  source: "native",
  association: { status: "registered", projectId: "p", checkoutId: "c", cwd: "/repo" },
  ...extra
})
const registry = {
  projects: [
    {
      id: "p",
      name: "Duplicated project",
      checkouts: [{ id: "c", branch: "feature/long", path: "/repo" }]
    },
    { id: "other", name: "Duplicated project", checkouts: [{ id: "c2", path: "/else" }] }
  ]
}
test("all six states use human labels and attention comes first without verification inference", () => {
  assert.equal(typeof logic.rows, "function", "Tasks projection exists")
  const states = [
    "working",
    "needs-input",
    "ready-for-review",
    "failed",
    "finished",
    "connection-lost"
  ]
  const rows = logic.rows({ tasks: states.map((s) => task(s, s)) }, registry)
  assert.equal(rows[0].stateLabel, "Needs input")
  assert.deepEqual(
    new Set(rows.map((r) => r.stateLabel)),
    new Set(["Working", "Needs input", "Ready for review", "Failed", "Finished", "Connection lost"])
  )
  assert.ok(rows.every((r) => r.verificationLabel === "Verification not reported"))
  assert.equal(rows[0].context, "Duplicated project · feature/long · /repo")
  assert.equal(rows[0].summary, "Fix <b>bug</b>")
})
test("association joins exact IDs and path; provider text is bounded with independent diagnostics and verification", () => {
  assert.equal(typeof logic.rows, "function")
  const snapshot = {
    tasks: [
      task("a", "finished", {
        result: "x".repeat(10000),
        question: "<img src=x>",
        diagnostics: [{ summary: "diagnostic" }],
        verification: { status: "reported-fail", summary: "failed tests", commands: ["make test"] }
      }),
      task("b", "working", {
        provider: "codex",
        association: { status: "unassigned", cwd: "/unassigned" }
      }),
      task("c", "working", {
        association: { status: "registered", projectId: "p", checkoutId: "c", cwd: "/wrong" }
      })
    ]
  }
  const rows = logic.rows(snapshot, registry)
  assert.equal(rows.find((r) => r.key === "a").verificationLabel, "Verification reported failed")
  assert.ok(rows.find((r) => r.key === "a").result.length <= 4097)
  assert.equal(rows.find((r) => r.key === "a").diagnostics, "diagnostic")
  assert.equal(rows.find((r) => r.key === "b").providerLabel, "Codex")
  assert.equal(rows.find((r) => r.key === "b").associationLabel, "Unassigned checkout")
  assert.equal(rows.find((r) => r.key === "c").associationLabel, "Checkout unavailable")
  assert.equal(rows.find((r) => r.key === "c").primary.kind, "")
})
test("cursor identities survive re-sort; removal and action changes require another reveal", () => {
  assert.equal(typeof logic.reconcileSelection, "function")
  const rows = logic.rows({ tasks: [task("one", "working"), task("two", "needs-input")] }, registry)
  assert.equal(logic.reconcileSelection("gone", rows).key, "")
  assert.equal(logic.reconcileSelection("one", rows).key, "one")
  const first = logic.step(["one", "two"], "", false, 0)
  assert.equal(first.activate, false)
  assert.equal(logic.step(["two", "one"], first.key, true, 0).key, "one")
  assert.equal(logic.step(["two"], "one", true, 0).activate, false)
  assert.equal(logic.step(["one", "two"], "two", true, 0).activate, true)
})
test("task-only bar, Usage-only default, attention default and remembered destination", () => {
  assert.equal(typeof logic.destination, "function")
  const quiet = logic.rows({ tasks: [task("w", "working")] }, registry)
  const attention = logic.rows({ tasks: [task("n", "needs-input")] }, registry)
  assert.equal(logic.visible(0, quiet), true)
  assert.equal(logic.destination("", [], 1), "usage")
  assert.equal(logic.destination("", quiet, 0), "tasks")
  assert.equal(logic.destination("", attention, 1), "tasks")
  assert.equal(logic.destination("usage", attention, 1), "usage")
  assert.equal(logic.destination("tasks", [], 1), "tasks")
})
test("retained operation outcomes never advertise a repeated uncertain launch", () => {
  assert.equal(typeof logic.operationView, "function")
  const op = {
    id: "stable",
    taskId: "t",
    action: "reopen",
    state: "completed",
    outcome: "partial",
    steps: [
      { role: "terminal", status: "observed" },
      { role: "session", status: "unconfirmed" }
    ]
  }
  assert.equal(logic.operationView(op, null, false).canReobserve, true)
  assert.equal(
    logic.operationView(op, null, false).steps,
    "Hosting terminal: observed\nNative session: unconfirmed"
  )
  assert.equal(
    logic.operationView({ ...op, submissionPending: true }, null, false).canReobserve,
    false
  )
  assert.equal(
    logic.operationView({ ...op, submissionUnconfirmed: true }, null, false).protected,
    true
  )
  assert.equal(
    logic.operationView(
      op,
      { code: "OPERATION_LOST", message: "Gone", recovery: "Reconnect" },
      false
    ).canReconnect,
    true
  )
  assert.equal(logic.operationView({ ...op, outcome: "observed" }, null, false).label, "Observed")
})
