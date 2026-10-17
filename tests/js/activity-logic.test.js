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
test("work superseded by a later prompt or silent for 6 hours has ended without a report", () => {
  const retired = { ...session, nativeMetadata: { inactiveTaskIds: ["t"] } }
  for (const reportedState of ["working", "needs-input"]) {
    const ended = logic.project(
      { tasks: [{ ...task, reportedState, lastReceivedAt: 1 }], sessions: [retired] },
      2000,
      registry
    ).tasks[0]
    assert.equal(ended.displayState, "ended", reportedState + " superseded by a later prompt")
    assert.equal(ended.reportedState, reportedState, "reported state kept")
  }
  const hours = (h) => (1 + h * 3600) * 1000
  // Heartbeats keep the session connected while the task itself stays silent.
  const fresh = (h) => ({
    ...session,
    connection: { ...session.connection, receivedAt: 1 + h * 3600 }
  })
  const silent = (reportedState, h) =>
    logic.project(
      { tasks: [{ ...task, reportedState, lastReceivedAt: 1 }], sessions: [fresh(h)] },
      hours(h),
      registry
    ).tasks[0].displayState
  assert.equal(silent("working", 6), "ended", "working with no report for 6 hours")
  assert.equal(silent("working", 5.9), "working", "recent work still working")
  assert.equal(silent("needs-input", 6), "needs-input", "a question can wait for the user")
  for (const reportedState of ["finished", "failed", "ready-for-review"])
    assert.equal(silent(reportedState, 7), reportedState, "reported outcomes stay")
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
  for (const key of ["description", "result", "question"])
    assert.ok(bounded[key].length < long.length && bounded[key].endsWith("…"), key + " marked cut")
  assert.ok(bounded.verification.summary.endsWith("…"), "verification summary marked cut")
  assert.ok(bounded.blockers[0].question.endsWith("…"), "cut blocker question marked")
  const small = { ...task, result: "done", diagnostics: [{ summary: "d", receivedAt: 1 }] }
  assert.deepEqual(logic.boundTask(small), small, "ordinary rows are unchanged")
  const joined = {
    ...task,
    diagnostics: Array.from({ length: 20 }, () => ({ summary: "x".repeat(4096), receivedAt: 1 }))
  }
  const shown = logic
    .boundTask(joined)
    .diagnostics.map((d) => d.summary)
    .join("\n")
  assert.equal(shown.length, 4096, "first 4096 shown chars kept")
  assert.ok(shown.endsWith("…"), "cut list ends with the marker")
  const exact = { ...task, description: "y".repeat(4096) }
  assert.equal(
    logic.boundTask(exact).description,
    exact.description,
    "text at the limit is not cut"
  )
})

test("task pages fill up to the byte budget and always make progress", () => {
  assert.equal(typeof logic.taskPage, "function", "task paging exists")
  const rows = Array.from({ length: 10 }, (_, i) => ({ taskId: "t" + i, result: "x".repeat(1000) }))
  assert.equal(logic.taskPage(rows, 0, 3500).length, 3)
  assert.equal(logic.taskPage(rows, 9, 3500).length, 1)
  assert.equal(logic.taskPage(rows, 0, 10).length, 1, "one oversized row still advances")
  assert.equal(logic.taskPage(rows, 10, 3500).length, 0)
})

test("IPC operations keep open, protected and each task's latest outcome within a budget", () => {
  assert.equal(typeof logic.ipcOperations, "function", "operation bounding exists")
  const op = (id, taskId, extra = {}) => ({
    id,
    ownerId: "owner",
    taskId,
    action: "reopen",
    state: "completed",
    outcome: "partial",
    attempt: 1,
    steps: [{ role: "terminal", status: "observed", binding: { address: "0x" + "a".repeat(400) } }],
    error: { code: "X", message: "m".repeat(2000), recovery: "r" },
    task: { taskId, result: "x".repeat(4096) },
    spec: { argv: ["x".repeat(500)] },
    ...extra
  })
  const ops = []
  for (let i = 0; i < 100; i++) ops.push(op("old-" + i, "t" + (i % 40)))
  ops.push(op("open", "t1", { state: "observing", outcome: null }))
  ops.push(op("protected", "t2", { submissionUnconfirmed: true }))
  ops.push(op("set", undefined, { action: "dismiss-many", taskIds: ["a", "b"] }))
  const kept = logic.ipcOperations(ops, 16000)
  assert.ok(logic.utf8Length(JSON.stringify(kept)) <= 16000, "within budget")
  const ids = kept.map((o) => o.id)
  assert.ok(ids.includes("open") && ids.includes("protected"), "open and protected kept")
  assert.ok(!ids.includes("set"), "completed set dismissal dropped")
  assert.ok(ids.includes("old-99") && !ids.includes("old-59"), "only each task's latest outcome")
  assert.ok(kept.every((o) => o.task === undefined && o.spec === undefined && !o.taskIds))
  assert.equal(kept[0].steps[0].binding, undefined, "steps keep role and status")
  assert.equal(kept[0].steps[0].status, "observed")
  assert.ok(kept[0].error.message.length <= 513)
  assert.deepEqual(
    ids,
    ops.map((o) => o.id).filter((id) => ids.includes(id)),
    "original order kept"
  )
  assert.equal(logic.ipcOperations(ops, 300).length >= 1, true, "open work is never dropped")
})

test("list rows are short previews that expand to the shape every consumer reads", () => {
  assert.equal(typeof logic.previewTask, "function", "preview rows exist")
  const long = "word ".repeat(1000)
  const full = logic.project(
    {
      tasks: [
        {
          ...task,
          description: long,
          result: long,
          question: "",
          blockers: [{ blockerId: "b", question: long }],
          diagnostics: [{ summary: long, receivedAt: 1 }],
          verification: { status: "reported-pass", summary: long, commands: ["make"] },
          lastReceivedAt: 1,
          source: "native"
        }
      ],
      sessions: [session]
    },
    2000,
    registry
  ).tasks[0]
  const preview = logic.previewTask(full)
  assert.equal(preview.preview, true)
  assert.equal(preview.description.length, 101)
  assert.ok(preview.description.endsWith("…") && preview.result.endsWith("…"), "cut marked")
  assert.ok(logic.utf8Length(JSON.stringify(preview)) < 900, "preview row is small")
  const row = logic.expandPreview(preview)
  assert.equal(row.question, "")
  assert.deepEqual(row.diagnostics, [])
  assert.deepEqual(row.blockers, [{ blockerId: "b", question: "" }])
  assert.deepEqual(row.verification, { status: "reported-pass", summary: "", commands: [] })
  assert.equal(row.resumeCommand, full.resumeCommand, "resume command derived again")
  for (const key of ["taskId", "displayState", "freshness", "association", "lastReceivedAt"])
    assert.deepEqual(row[key], full[key], key + " kept")
  const plain = logic.expandPreview(
    logic.previewTask({ ...full, blockers: [], verification: null })
  )
  assert.deepEqual(plain.blockers, [])
  assert.equal(plain.verification.status, "unknown")
  assert.equal(logic.expandPreview(full), full, "full rows unchanged")
})
