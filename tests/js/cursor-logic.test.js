// Logic contract for the shared cursor-safety rules (CursorLogic.js), moved
// from NetworkLogic.js so araneadev.vpn can reuse them. Run with
// `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

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

// --- afterRemoval ----------------------------------------------------------

test("afterRemoval lands on the stop that slid into the removed middle row's place", () => {
  // "b" sat at index 1; after it leaves, "c" slides up into that index.
  const after = [{ key: "a" }, { key: "c" }, { key: "d" }]
  assert.deepEqual(logic.afterRemoval(after, "b", 1), { index: 1, key: "c" })
})

test("afterRemoval clamps to the previous stop when the removed row was last", () => {
  const after = [{ key: "a" }, { key: "b" }]
  assert.deepEqual(logic.afterRemoval(after, "c", 2), { index: 1, key: "b" })
})

test("afterRemoval returns no stop when the only row is gone", () => {
  assert.deepEqual(logic.afterRemoval([], "a", 0), { index: -1, key: "" })
})

test("afterRemoval returns the row itself when its key survived the removal", () => {
  // The read of `stops` hasn't caught up with the removal yet: "b" is still
  // there, so it is its own neighbour, whatever lastIndex says.
  const stops = [{ key: "a" }, { key: "b" }, { key: "c" }]
  assert.deepEqual(logic.afterRemoval(stops, "b", 5), { index: 1, key: "b" })
  assert.deepEqual(logic.afterRemoval(stops, "b", -1), { index: 1, key: "b" })
})

test("afterRemoval tolerates empty or invalid input", () => {
  assert.deepEqual(logic.afterRemoval(undefined, "a", 0), { index: -1, key: "" })
  assert.deepEqual(logic.afterRemoval(null, "a", 0), { index: -1, key: "" })
  const rows = [{ key: "a" }, { key: "b" }]
  assert.deepEqual(
    logic.afterRemoval(rows, "", 0),
    { index: 0, key: "a" },
    "an empty removed key is never matched"
  )
  assert.deepEqual(logic.afterRemoval(rows, null, 0), { index: 0, key: "a" })
  assert.deepEqual(logic.afterRemoval(rows, undefined, 9), { index: 1, key: "b" })
  assert.deepEqual(logic.afterRemoval(rows, "z", Number.NaN), { index: 0, key: "a" })
  assert.deepEqual(logic.afterRemoval([null, { key: "a" }], "z", 0), { index: 0, key: "" })
})

// --- NetworkLogic.js's generated copy (tools/js-facade-generator.mjs) ----

test("NetworkLogic.js's generated copy of CursorLogic answers like the source", () => {
  // Panel.qml (Network) imports CursorLogic.js directly; this generated
  // copy only exists because NetworkLogic.js's own keyTargetConfirmed and
  // pressOutcome call cursorConfirmed/pressIntent internally, with no
  // cross-.js-file import usable from both QML and Node (NetworkLogic.js's
  // own header comment). The rest of CursorLogic rides along unused by
  // Network's logic; loadPragma runs the copy for real (not just this
  // file's CursorLogic.js) so NetworkLogic.js's own function-coverage floor
  // stays honest as CursorLogic grows (afterRemoval).
  // A vm context is its own JS realm, so its plain objects fail
  // reference-equal deepEqual against this file's; round-trip through JSON.
  const plain = (value) => JSON.parse(JSON.stringify(value))
  const copy = loadPragma("plugins/araneadev.network/NetworkLogic.js")
  const rows = [{ key: "a" }, { key: "b" }, { key: "c" }]
  assert.deepEqual(
    plain(copy.reselectIndex(rows, "c", 0)),
    plain(logic.reselectIndex(rows, "c", 0))
  )
  assert.deepEqual(plain(copy.followCursor(rows, "b", 0)), plain(logic.followCursor(rows, "b", 0)))
  assert.equal(copy.cursorConfirmed(rows, "b", 1), logic.cursorConfirmed(rows, "b", 1))
  assert.equal(copy.pressIntent(true, false), logic.pressIntent(true, false))
  assert.deepEqual(plain(copy.keepRows({}, "x", rows)), plain(logic.keepRows({}, "x", rows)))
  assert.equal(copy.rowKeyMatches(rows, 1, "b"), logic.rowKeyMatches(rows, 1, "b"))
  assert.deepEqual(plain(copy.afterRemoval(rows, "b", 1)), plain(logic.afterRemoval(rows, "b", 1)))
  assert.deepEqual(
    plain(copy.afterRemoval([{ key: "c" }], "a", 5)),
    plain(logic.afterRemoval([{ key: "c" }], "a", 5))
  )
  assert.deepEqual(plain(copy.afterRemoval([], "a", 0)), plain(logic.afterRemoval([], "a", 0)))
})
