// Logic contract for the shared cursor-safety rules (CursorLogic.js), moved
// from NetworkLogic.js so araneadev.vpn can reuse them. Run with
// `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.shared/CursorLogic.js"))

// --- reselectIndex -------------------------------------------------------

test("reselectIndex finds the keyed row wherever it moved", () => {
  const rows = [{ key: "a" }, { key: "b" }, { key: "c" }]
  assert.equal(logic.reselectIndex(rows, "c", 0), 2)
  assert.equal(logic.reselectIndex(rows, "a", 2), 0)
  assert.equal(
    logic.reselectIndex(rows, "", 1),
    1,
    "an empty key is a real (hidden) key only when a row has it"
  )
  assert.equal(logic.reselectIndex([{ key: "" }, { key: "x" }], "", 1), 0)
})

test("reselectIndex falls back to the clamped fallback when the key is gone", () => {
  const rows = [{ key: "a" }, { key: "b" }]
  assert.equal(logic.reselectIndex(rows, "z", 1), 1)
  assert.equal(logic.reselectIndex(rows, "z", 9), 1)
  assert.equal(logic.reselectIndex(rows, "z", -3), 0)
  assert.equal(logic.reselectIndex(rows, "z", Number.NaN), 0)
  assert.equal(logic.reselectIndex(rows, null, 1), 1)
})

test("reselectIndex returns -1 for no rows and never throws on bad input", () => {
  assert.equal(logic.reselectIndex([], "a", 0), -1)
  assert.equal(logic.reselectIndex(undefined, "a", 0), -1)
  assert.equal(logic.reselectIndex([null, { key: "a" }], "a", 0), 1)
  assert.equal(logic.reselectIndex([null, undefined], "a", 1), 1)
})

// --- followCursor / cursorConfirmed (the 19:04 incident) -----------------

test("followCursor follows the chosen network across a re-sort", () => {
  // The cursor sat on a secured AP at index 1; a scan re-sorts and an open
  // network takes index 1. The cursor must move with the secured AP.
  const before = [{ key: "Home" }, { key: "Daikin" }, { key: "SmartLife" }]
  assert.equal(logic.cursorConfirmed(before, "Daikin", 1), true)
  const after = [{ key: "Home" }, { key: "SmartLife" }, { key: "Daikin" }]
  assert.deepEqual(logic.followCursor(after, "Daikin", 1), {
    index: 2,
    key: "Daikin",
    confirmed: true
  })
  assert.equal(
    logic.cursorConfirmed(after, "Daikin", 1),
    false,
    "the old index now holds the open network"
  )
})

test("followCursor never adopts the row that slides into a vanished network's place", () => {
  // The cursored AP drops out of the scan and an open network slides into
  // its index: the cursor stays there, but nothing is confirmed.
  const after = [{ key: "Home" }, { key: "SmartLife" }]
  const r = logic.followCursor(after, "Daikin", 1)
  assert.deepEqual(r, { index: 1, key: "", confirmed: false })
  assert.equal(logic.cursorConfirmed(after, r.key, r.index), false)
  // And stays refused across the next re-sort, never jumping to a row.
  const later = logic.followCursor([{ key: "SmartLife" }, { key: "Home" }], r.key, r.index)
  assert.deepEqual(later, { index: 1, key: "", confirmed: false })
})

test("followCursor clamps into the list and returns -1 with no rows", () => {
  assert.deepEqual(logic.followCursor([{ key: "a" }], "z", 5), {
    index: 0,
    key: "",
    confirmed: false
  })
  assert.deepEqual(logic.followCursor([], "a", 0), { index: -1, key: "", confirmed: false })
  assert.deepEqual(logic.followCursor(undefined, "a", 0), { index: -1, key: "", confirmed: false })
  assert.deepEqual(logic.followCursor([{ key: "a" }], null, Number.NaN), {
    index: 0,
    key: "",
    confirmed: false
  })
})

test("an empty key (a hidden SSID, or no choice) is never confirmed", () => {
  const rows = [{ key: "" }, { key: "a" }]
  assert.equal(logic.cursorConfirmed(rows, "", 0), false)
  assert.deepEqual(logic.followCursor(rows, "", 1), { index: 1, key: "", confirmed: false })
  assert.equal(logic.cursorConfirmed(rows, "a", 1), true)
  assert.equal(logic.cursorConfirmed(rows, "a", 5), false)
  assert.equal(logic.cursorConfirmed(undefined, "a", 0), false)
  assert.equal(logic.cursorConfirmed([null], "a", 0), false)
})

// --- pressIntent -----------------------------------------------------------

test("pressIntent: Enter and x only reveal a cursor the keyboard isn't showing", () => {
  assert.equal(logic.pressIntent(false, false), "ignore")
  assert.equal(logic.pressIntent(false, true), "ignore")
  assert.equal(logic.pressIntent(true, false), "reveal", "a pointer-placed cursor is invisible")
  assert.equal(logic.pressIntent(true, true), "act")
})

// --- keepRows ------------------------------------------------------------------

test("keepRows hands back the previous array when nothing changed", () => {
  const cache = {}
  const first = [{ key: "a" }]
  assert.equal(logic.keepRows(cache, "wifi", first), first)
  const same = [{ key: "a" }]
  assert.equal(logic.keepRows(cache, "wifi", same), first, "equal content keeps the old array")
  const changed = [{ key: "b" }]
  assert.equal(logic.keepRows(cache, "wifi", changed), changed)
  assert.equal(logic.keepRows(cache, "vpn", same), same, "each name has its own slot")
  assert.equal(logic.keepRows(null, "wifi", same), same)
})

// --- rowKeyMatches -----------------------------------------------------------------

test("rowKeyMatches checks a pointer action's row is still the one it names", () => {
  const rows = [{ key: "a" }, { key: "" }]
  assert.equal(logic.rowKeyMatches(rows, 0, "a"), true)
  assert.equal(logic.rowKeyMatches(rows, 1, ""), true, "a hidden network still works by mouse")
  assert.equal(logic.rowKeyMatches(rows, 0, "b"), false)
  assert.equal(logic.rowKeyMatches(rows, 4, "a"), false)
  assert.equal(logic.rowKeyMatches(rows, 0, undefined), false)
  assert.equal(logic.rowKeyMatches(undefined, 0, "a"), false)
})
