const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const ops = loadPragma("plugins/araneadev.projects/ProjectOperations.js")
const plain = (value) => JSON.parse(JSON.stringify(value))
const request = { projectId: "p-1", checkoutId: "c-1", generation: 2, sessionId: "s-1" }
const binding = {
  projectId: "p-1",
  checkoutId: "c-1",
  role: "editor",
  workspaceId: 2,
  address: "0xa",
  pid: 42,
  appId: "token",
  sessionId: "s-1",
  evidence: { mode: "process-app-id", processVerified: true }
}
const windows = [{ address: "0xa", pid: 42, appId: "token" }]
test("occupied and reserved workspaces are preserved", () => {
  assert.equal(ops.allocateWorkspace([{ id: 1, windows: 2 }], [{ workspaceId: 2 }]), 3)
  assert.equal(
    ops.allocateWorkspace(
      [
        { id: 1, windows: 0 },
        { id: 3, windows: [{}] },
        { id: -2, windows: 3 }
      ],
      []
    ),
    1
  )
})
test("same checkout pending requests coalesce without mutating input", () => {
  const first = ops.begin([], request, "op-1")
  assert.equal(first.reused, false)
  assert.equal(first.operation.state, "accepted")
  const second = ops.begin([first.operation], { ...request, newWindowRole: "editor" }, "op-2")
  assert.equal(second.reused, true)
  assert.equal(second.operation.id, "op-1")
  assert.equal(
    ops.begin([{ ...first.operation, state: "completed" }], request, "op-3").reused,
    false
  )
  assert.equal(
    ops.begin([first.operation], { ...request, checkoutId: "c-2" }, "op-4").reused,
    false
  )
  assert.equal(request.id, undefined)
})
test("generation and session guards reject late responses", () => {
  const op = ops.begin([], request, "op-1").operation
  assert.equal(ops.acceptsGeneration(op, 2, "s-1"), true)
  assert.equal(ops.acceptsGeneration(op, 3, "s-1"), false)
  assert.equal(ops.acceptsGeneration(op, 2, "s-2"), false)
  assert.equal(ops.acceptsGeneration({ ...op, state: "completed" }, 2, "s-1"), false)
})
test("unconfirmed terminal makes observed editor result partial", () => {
  const result = ops.complete({ id: "op-1", state: "observing" }, [
    { role: "editor", status: "observed" },
    { role: "terminal", status: "unconfirmed", code: "OBSERVATION_TIMEOUT" }
  ])
  assert.equal(result.outcome, "partial")
  assert.equal(result.state, "completed")
  assert.equal(ops.complete({}, [{ status: "failed" }]).outcome, "failed")
  assert.equal(ops.complete({}, [{ status: "unconfirmed" }]).outcome, "partial")
  assert.equal(ops.complete({}, [{ status: "observed" }, { status: "failed" }]).outcome, "partial")
  assert.equal(ops.complete({}, [{ status: "observed" }]).outcome, "observed")
  assert.equal(ops.complete({}, []).outcome, "failed")
})
test("runtime evidence requires fresh process and exact session identity", () => {
  assert.equal(ops.bindingMatches(binding, windows, "s-1"), true)
  for (const changed of [
    { sessionId: "s-old" },
    { pid: 1 },
    { appId: "other" },
    { evidence: { mode: "title", processVerified: true } },
    { evidence: { mode: "process-app-id", processVerified: false } },
    { address: "0x0" }
  ])
    assert.equal(ops.bindingMatches({ ...binding, ...changed }, windows, "s-1"), false)
  assert.equal(ops.bindingMatches(binding, [], "s-1"), false)
  assert.equal(
    ops.bindingMatches(
      { ...binding, evidence: { mode: "process-only", processVerified: true } },
      [{ ...windows[0], appId: "other" }],
      "s-1"
    ),
    true
  )
})
test("resume, lost identities, role retries and explicit new windows stay independent", () => {
  const decision = (role, req, b, last) =>
    ops.roleDecision(role, req, b, last, windows, "s-1").action
  assert.equal(decision("editor", request, binding, null), "focus")
  assert.equal(decision("editor", request, { ...binding, pid: 999 }, null), "hold")
  assert.equal(decision("terminal", request, null, null), "launch")
  assert.equal(decision("editor", request, null, { status: "observed" }), "hold")
  assert.equal(decision("terminal", request, null, { status: "unconfirmed" }), "hold")
  assert.equal(
    decision("terminal", { ...request, retryRole: "terminal" }, null, { status: "failed" }),
    "launch"
  )
  assert.equal(decision("editor", { ...request, retryRole: "terminal" }, binding, null), "skip")
  assert.equal(
    decision("terminal", { ...request, retryRole: "terminal" }, null, { status: "unconfirmed" }),
    "hold"
  )
  assert.equal(decision("editor", { ...request, newWindowRole: "editor" }, binding, null), "launch")
  assert.equal(decision("editor", request, { ...binding, checkoutId: "c-2" }, null), "launch")
})
test("normal and separate associations isolate occupied alternate checkouts", () => {
  const normal = { checkoutId: "c-1", mode: "dedicated", workspaceId: 2, separate: false }
  const project = { id: "p-1", workspaceMode: "dedicated", associations: [normal] }
  const occupied = [
    { id: 1, windows: 2 },
    { id: 2, windows: 1 }
  ]
  const choose = (req, live = []) =>
    plain(ops.chooseAssociation(project, req, occupied, [normal], live, 1))
  assert.equal(choose(request, [binding]).workspaceId, 2)
  assert.equal(choose({ ...request, checkoutId: "c-2" }, [binding]).workspaceId, 3)
  assert.deepEqual(choose({ ...request, separate: true }, [binding]), {
    checkoutId: "c-1",
    mode: "dedicated",
    workspaceId: 3,
    separate: true
  })
  assert.equal(choose({ ...request, useCurrentWorkspace: true }).workspaceId, 1)
  assert.deepEqual(project.associations, [normal])
})
test("old-session evidence cannot block a fresh session or pass a missing guard", () => {
  assert.equal(ops.acceptsGeneration({ state: "accepted" }, undefined, undefined), false)
  assert.equal(
    ops.roleDecision("editor", request, { ...binding, sessionId: "old" }, null, windows, "s-1")
      .action,
    "launch"
  )
  assert.equal(
    ops.begin([ops.begin([], request, "old").operation], { ...request, sessionId: "new" }, "new")
      .reused,
    false
  )
})
test("association allocation reserves other projects and validates current workspace", () => {
  const project = { id: "p-1", workspaceMode: "dedicated", associations: [] }
  assert.equal(
    ops.chooseAssociation(project, request, [{ id: 1, windows: 1 }], [{ workspaceId: 2 }], [], 1)
      .workspaceId,
    3
  )
  assert.equal(
    ops.chooseAssociation(project, { ...request, useCurrentWorkspace: true }, [], [], [], 0),
    null
  )
})
