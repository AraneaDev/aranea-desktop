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
  assert.equal(
    logic.resumeCommand({ ...task, provider: "codex" }),
    "codex resume '12345678-1234-1234-1234-123456789abc' --cd '/repo'"
  )
  assert.equal(
    logic.resumeCommand({ ...task, provider: "codex", providerSessionId: "thr_app" }),
    null
  )
  assert.equal(logic.resumeCommand({ ...task, provider: "codex", association: {} }), null)
  assert.equal(
    logic.resumeCommand({ ...task, provider: "codex", association: { cwd: "/repo's path" } }),
    "codex resume '12345678-1234-1234-1234-123456789abc' --cd '/repo'\\''s path'"
  )
  assert.equal(
    logic.project({ tasks: [task], sessions: [session] }, 2000, { projects: [] }).tasks[0]
      .association.status,
    "unavailable"
  )
})
test("attention transitions use state and blocker identity, consume suppression and bound plain text", () => {
  assert.equal(typeof logic.notificationTransitions, "function")
  const previous = { tasks: [task] }
  const attention = {
    ...task,
    reportedState: "needs-input",
    description: "<b>" + "x".repeat(900),
    blockers: [{ id: "b", summary: "question" }]
  }
  const current = { tasks: [attention] }
  assert.equal(logic.notificationTransitions(previous, current, true).length, 0)
  assert.equal(logic.notificationTransitions(current, current, false).length, 0)
  assert.equal(logic.notificationTransitions(null, current, false).length, 0)
  const result = logic.notificationTransitions(previous, current, false)
  assert.equal(result.length, 1)
  assert.equal(result[0].taskId, "t")
  assert.ok(result[0].body.length <= 512)
  assert.ok(!result[0].body.includes("<"))
  assert.equal(
    logic.notificationTransitions(
      current,
      { tasks: [{ ...attention, description: "changed" }] },
      false
    ).length,
    0
  )
  assert.equal(
    logic.notificationTransitions(
      current,
      { tasks: [{ ...attention, blockers: [{ id: "c" }] }] },
      false
    ).length,
    1
  )
  for (const reportedState of ["working", "finished", "connection-lost"])
    assert.equal(
      logic.notificationTransitions(previous, { tasks: [{ ...task, reportedState }] }, false)
        .length,
      0
    )
})

test("native capability uses exact private session evidence independent of latest report source", () => {
  for (const source of ["native", "report"]) {
    for (const replacement of [
      session,
      { ...session, producerEpoch: "other" },
      { ...session, provenance: null },
      { ...session, nativeMetadata: { observedHooks: [] } }
    ]) {
      const projected = logic.project(
        { tasks: [{ ...task, source, nativeSessionEligible: true }], sessions: [replacement] },
        2000,
        registry
      ).tasks[0]
      assert.equal(projected.nativeSessionEligible, replacement === session)
    }
  }
})

test("IPC task rows keep what the panel shows and stay within a byte bound", () => {
  assert.equal(typeof logic.boundTask, "function", "task bounding exists")
  assert.equal(logic.utf8Length("aé€😀"), 1 + 2 + 3 + 4)
  const long = "é".repeat(4096)
  const full = {
    ...task,
    description: long,
    result: long,
    question: long,
    diagnostics: Array.from({ length: 20 }, (_, i) => ({ summary: i + long, receivedAt: i })),
    blockers: Array.from({ length: 32 }, (_, i) => ({ blockerId: "b" + i, question: long })),
    verification: { status: "reported-pass", summary: long, commands: ["x".repeat(512)] }
  }
  const bounded = logic.boundTask(full)
  assert.equal(full.diagnostics.length, 20, "source row unchanged")
  assert.ok(logic.utf8Length(JSON.stringify(bounded)) <= logic.maxTaskBytes)
  assert.equal(bounded.blockers.length, 32, "blocker count and ids kept")
  assert.equal(bounded.blockers[31].blockerId, "b31")
  const small = { ...task, result: "done", diagnostics: [{ summary: "d", receivedAt: 1 }] }
  assert.deepEqual(logic.boundTask(small), small, "ordinary rows are unchanged")
  const joined = {
    ...task,
    diagnostics: Array.from({ length: 20 }, () => ({ summary: "x".repeat(4096), receivedAt: 1 }))
  }
  const kept = logic.boundTask(joined).diagnostics
  assert.equal(kept.map((d) => d.summary).join("\n").length, 4096, "first 4096 shown chars kept")
})

test("task pages fill up to the byte budget and always make progress", () => {
  assert.equal(typeof logic.taskPage, "function", "task paging exists")
  const rows = Array.from({ length: 10 }, (_, i) => ({ taskId: "t" + i, result: "x".repeat(1000) }))
  assert.equal(logic.taskPage(rows, 0, 3500).length, 3)
  assert.equal(logic.taskPage(rows, 9, 3500).length, 1)
  assert.equal(logic.taskPage(rows, 0, 10).length, 1, "one oversized row still advances")
  assert.equal(logic.taskPage(rows, 10, 3500).length, 0)
})
