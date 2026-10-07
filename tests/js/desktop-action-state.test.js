const assert = require("node:assert/strict")
const { test } = require("node:test")
const actions = require("../../plugins/araneadev.menu/DesktopActionState.js")

test("pending requests block their family while other families remain usable", () => {
  const initial = actions.idle()
  const first = actions.begin(initial, "audio", "action:audio:a", 10)
  assert.ok(first.accepted)
  assert.equal(first.state.feedback["action:audio:a"].status, "pending")
  assert.deepEqual(initial, { sequence: 0, pending: {}, feedback: {} })
  const blocked = actions.begin(first.state, "audio", "action:audio:b", 11)
  assert.equal(blocked.accepted, false)
  assert.deepEqual(blocked.state, first.state)
  assert.ok(actions.begin(first.state, "dnd", "action:dnd", 12).accepted)
})

test("only the current request settles and a failed action can retry", () => {
  const first = actions.begin(actions.idle(), "audio", "action:audio:a", 0)
  assert.deepEqual(actions.complete(first.state, "audio", "stale", true, ""), first.state)
  const failed = actions.complete(first.state, "audio", first.requestId, false, "Unavailable")
  assert.deepEqual(failed.feedback["action:audio:a"], { status: "failed", message: "Unavailable" })
  assert.equal(failed.pending.audio, undefined)
  const retry = actions.begin(failed, "audio", "action:audio:a", 20)
  assert.ok(retry.accepted)
  assert.notEqual(retry.requestId, first.requestId)
  assert.deepEqual(actions.complete(retry.state, "audio", first.requestId, true, ""), retry.state)
  const confirmed = actions.complete(retry.state, "audio", retry.requestId, true, "Current")
  assert.deepEqual(confirmed.feedback["action:audio:a"], {
    status: "confirmed",
    message: "Current"
  })
  assert.equal(confirmed.pending.audio, undefined)
})
