const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const file = "plugins/araneadev.activity/ActivityLogic.js"
const logic = fs.existsSync(file) ? require("../../" + file) : {}
const task = {
  taskId: "t",
  provider: "claude",
  providerSessionId: "12345678-1234-1234-1234-123456789abc",
  producerEpoch: "e",
  reportedState: "working",
  association: { status: "registered", projectId: "p", checkoutId: "c", cwd: "/repo" },
  verification: { status: "unknown" }
}
const session = {
  ...task,
  connection: { connected: true, receivedAt: 1, monotonic: 1, bootId: "b" },
  provenance: { commandHash: "a".repeat(64) },
  nativeMetadata: { observedHooks: ["SessionStart"] }
}
const registry = { projects: [{ id: "p", checkouts: [{ id: "c", path: "/repo" }] }] }
test("projection preserves report and verification across heartbeat loss and reconnect", () => {
  assert.equal(typeof logic.project, "function", "activity projection exists")
  const state = { tasks: [task], sessions: [session] }
  const lost = logic.project(state, 61000, registry).tasks[0]
  assert.equal(lost.reportedState, "working")
  assert.equal(lost.displayState, "connection-lost")
  assert.equal(lost.verification.status, "unknown")
  assert.equal(logic.project(state, 2000, registry).tasks[0].displayState, "working")
  assert.equal(task.displayState, undefined)
})
test("boot, monotonic regression and retired turn invalidate freshness; terminal reports stay historical", () => {
  assert.equal(typeof logic.project, "function")
  for (const now of [
    { wall: 2000, monotonic: 2000, bootId: "other" },
    { wall: 2000, monotonic: 0, bootId: "b" },
    0
  ])
    assert.equal(
      logic.project({ tasks: [task], sessions: [session] }, now, registry).tasks[0].freshness,
      "connection-lost"
    )
  const retired = { ...session, nativeMetadata: { inactiveTaskIds: ["t"] } }
  assert.equal(
    logic.project({ tasks: [task], sessions: [retired] }, 2000, registry).tasks[0].freshness,
    "connection-lost"
  )
  for (const reportedState of ["finished", "failed", "ready-for-review"])
    assert.equal(
      logic.project({ tasks: [{ ...task, reportedState }], sessions: [session] }, 61000, registry)
        .tasks[0].displayState,
      reportedState
    )
})
test("missing association and native proof never become focus or arbitrary resume commands", () => {
  assert.equal(typeof logic.resumeCommand, "function")
  assert.equal(logic.resumeCommand(task), "claude --resume '12345678-1234-1234-1234-123456789abc'")
  for (const providerSessionId of [
    "--help",
    "a; touch x",
    "named-session",
    "'",
    "-1234567-1234-1234-1234-123456789abc"
  ])
    assert.equal(logic.resumeCommand({ ...task, providerSessionId }), null)
  assert.equal(logic.resumeCommand({ ...task, provider: "codex" }), null)
  assert.equal(
    logic.project({ tasks: [task], sessions: [session] }, 2000, { projects: [] }).tasks[0]
      .association.status,
    "unavailable"
  )
})
