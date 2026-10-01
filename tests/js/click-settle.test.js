// Logic contract for the shared click-settling rule (ClickSettle.js). Run
// with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.shared/ClickSettle.js"))

// --- clickSettled ----------------------------------------------------------------

test("clickSettled ignores a click on a fresh delegate unless the pointer moved onto it", () => {
  const base = { createdAt: 1000, movedAt: 0, layoutChangedAt: 0, settleMs: 300 }
  assert.equal(logic.clickSettled({ ...base, now: 1100 }), false, "100 ms after creation")
  assert.equal(logic.clickSettled({ ...base, now: 1300 }), true, "settled after 300 ms")
  assert.equal(
    logic.clickSettled({ ...base, now: 1100, movedAt: 1050 }),
    true,
    "a real move since creation"
  )
  assert.equal(
    logic.clickSettled({ ...base, now: 1100, movedAt: 1000 }),
    false,
    "a move in the same ms is no proof"
  )
})

test("clickSettled ignores a click soon after the layout shifted under a still pointer", () => {
  const base = { createdAt: 0, movedAt: 500, layoutChangedAt: 2000, settleMs: 300 }
  assert.equal(
    logic.clickSettled({ ...base, now: 2100 }),
    false,
    "a move before the shift doesn't count"
  )
  assert.equal(logic.clickSettled({ ...base, now: 2300 }), true, "settled 300 ms after the shift")
  assert.equal(
    logic.clickSettled({ ...base, now: 2100, movedAt: 2050 }),
    true,
    "a real move after the shift"
  )
  assert.equal(
    logic.clickSettled({ ...base, now: 2100, movedAt: 2000 }),
    false,
    "a move in the same ms is no proof"
  )
  assert.equal(
    logic.clickSettled({ ...base, now: 2100, createdAt: 2050, movedAt: 0 }),
    false,
    "both guards hold"
  )
})

test("clickSettled reads missing or odd times as no shift and an old delegate", () => {
  assert.equal(logic.clickSettled({ now: 5000 }), true, "no times at all")
  assert.equal(logic.clickSettled({ now: 5000, layoutChangedAt: undefined, createdAt: null }), true)
  assert.equal(
    logic.clickSettled({ now: 5000, layoutChangedAt: 4900 }),
    false,
    "settleMs defaults to 300"
  )
  assert.equal(logic.clickSettled(null), false, "no input is refused")
  assert.equal(logic.clickSettled({}), false, "nor is a click with no time")
})

test("settledSince weighs one event", () => {
  assert.equal(logic.settledSince(0, 100, 0, 300), true, "never happened")
  assert.equal(logic.settledSince(50, 100, 0, 300), false, "too recent")
  assert.equal(logic.settledSince(50, 100, 60, 300), true, "moved onto since")
  assert.equal(logic.settledSince(50, 350, 0, 300), true, "long enough ago")
})
