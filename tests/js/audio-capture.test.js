const assert = require("node:assert/strict")
const { test } = require("node:test")
const model = require("../../plugins/araneadev.audio/Model.js")

// A source can run because our own level meter opened it. Only actual
// recorder streams may turn on the microphone activity signal.
test("microphone activity follows recorder streams rather than source running", () => {
  assert.equal(typeof model.captureActive, "function", "capture activity is available")
  assert.equal(model.captureActive([{ isStream: false, isSink: false, running: true }]), false)
  assert.equal(
    model.captureActive([{ isStream: true, isSink: true, audio: { muted: false } }]),
    false
  )
  assert.equal(
    model.captureActive([{ isStream: true, isSink: false, audio: { muted: false } }]),
    true
  )
  assert.equal(model.captureActive([]), false)
})

test("muted recorder streams and disappearing nodes do not report activity", () => {
  assert.equal(typeof model.captureActive, "function", "capture activity is available")
  assert.equal(
    model.captureActive([null, { isStream: true, isSink: false, audio: { muted: true } }]),
    false
  )
  assert.equal(model.captureActive(null), false)
  assert.equal(model.captureActive([{ isStream: true }]), false)
  // Native Microphone accepts an unbound capture stream too; never read
  // node.properties (unsafe before the PipeWire node is bound).
  const recorder = { isStream: true, isSink: false }
  Object.defineProperty(recorder, "properties", {
    get() {
      throw new Error("unbound properties read")
    }
  })
  assert.equal(model.captureActive([recorder]), true)
})
