const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const file = "plugins/araneadev.activity/ActivityOperations.js"
const ops = fs.existsSync(file) ? require("../../" + file) : {}
test("strict requests and pending session dedupe retain accepted identity", () => {
  assert.equal(typeof ops.request, "function", "activity operations exist")
  const a = ops.request([], { action: "reopen", taskId: "t" }, "one", "owner", "native")
  assert.equal(a.ok, true)
  assert.equal(
    ops.request([a.operation], { action: "reopen", taskId: "other" }, "two", "owner", "native")
      .operation.id,
    "one"
  )
  assert.equal(
    ops.request([], { action: "reopen", taskId: "t", argv: ["sh"] }, "x", "owner", "native").ok,
    false
  )
  assert.equal(
    ops.request([], { action: "reopen", taskId: "--help" }, "x", "owner", "native").ok,
    false
  )
})
test("terminal observation cannot stand in for fresh native resumed evidence", () => {
  assert.equal(typeof ops.observe, "function")
  const op = {
    id: "one",
    action: "reopen",
    state: "observing",
    ownerId: "o",
    sessionKey: "claude:s",
    priorEpoch: "old",
    acceptedAt: 1000
  }
  const terminal = { status: "observed", binding: { address: "0xa" } }
  assert.equal(ops.observe(op, terminal, null, false).state, "observing")
  assert.equal(ops.observe(op, terminal, null, true).outcome, "partial")
  assert.equal(
    ops.observe(
      op,
      terminal,
      {
        provider: "claude",
        providerSessionId: "s",
        producerEpoch: "old",
        nativeVerified: true,
        observedAt: 2000
      },
      false
    ).state,
    "observing"
  )
  assert.equal(
    ops.observe(
      op,
      terminal,
      {
        provider: "claude",
        providerSessionId: "s",
        producerEpoch: "new",
        nativeVerified: true,
        observedAt: 2000
      },
      false
    ).outcome,
    "observed"
  )
})
test("unresolved launch submission remains authoritative after observation timeout", () => {
  const accepted = ops.request(
    [],
    { action: "reopen", taskId: "t" },
    "one",
    "owner",
    "native"
  ).operation
  const timedOut = { ...accepted, state: "completed", outcome: "partial", submissionPending: true }
  assert.equal(
    ops.request([timedOut], { action: "reopen", taskId: "other-turn" }, "two", "owner", "native")
      .operation.id,
    "one"
  )
  assert.equal(
    ops.request(
      [{ ...timedOut, submissionPending: false, submissionUnconfirmed: true }],
      { action: "reopen", taskId: "t" },
      "two",
      "owner",
      "native"
    ).operation.id,
    "one"
  )
  assert.equal(
    ops.request(
      [{ ...timedOut, submissionPending: false }],
      { action: "reopen", taskId: "t" },
      "two",
      "owner",
      "native"
    ).operation.id,
    "two"
  )
})

test("a set dismissal takes exact unique IDs and is never merged with another set", () => {
  const ok = ops.request([], { action: "dismiss-many", taskIds: ["a", "b"] }, "one", "owner", "one")
  assert.equal(ok.ok, true)
  assert.deepEqual(ok.operation.taskIds, ["a", "b"])
  const other = ops.request(
    [ok.operation],
    { action: "dismiss-many", taskIds: ["c"] },
    "two",
    "owner",
    "two"
  )
  assert.equal(other.operation.id, "two", "another set is its own operation")
  const tooMany = Array.from({ length: 701 }, (_, i) => "t" + i)
  for (const taskIds of [[], ["a", "a"], ["--help"], "a", tooMany])
    assert.equal(
      ops.request([], { action: "dismiss-many", taskIds }, "x", "owner", "x").ok,
      false,
      JSON.stringify(taskIds).slice(0, 40)
    )
  assert.equal(
    ops.request([], { action: "dismiss-many", taskIds: ["a"], taskId: "a" }, "x", "owner", "x").ok,
    false
  )
  assert.equal(
    ops.request([], { action: "dismiss-many", taskId: "a" }, "x", "owner", "x").ok,
    false
  )
})
