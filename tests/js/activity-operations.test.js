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
