// Logic contract for TrayLogic.js: mnemonic stripping, the app menu's row
// list with stock's hiding quirks, keyed lookup, cursor movement (wrapping
// in the menu, clamping in manage), jump-to-letter, the breadcrumb, pin/hide
// list edits, the manage cursor and the IPC `menu <index>` target. Run with
// `node --test tests/js/` (tools/check runs it with coverage).

const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.tray/TrayLogic.js"))

// --- labelOf (mnemonic stripping) ---------------------------------------------------

test("labelOf: a single marker is removed", () => {
  assert.equal(logic.labelOf("_Open"), "Open")
  assert.equal(logic.labelOf("&Open"), "Open")
  assert.equal(logic.labelOf("Op_en"), "Open")
})

test("labelOf: a doubled marker becomes a literal character", () => {
  assert.equal(logic.labelOf("Save && Quit"), "Save & Quit")
  assert.equal(logic.labelOf("__x"), "_x")
  assert.equal(logic.labelOf("a__b"), "a_b")
})

test("labelOf: a trailing marker is dropped, and a doubled marker before a single one stays literal", () => {
  assert.equal(logic.labelOf("a_"), "a")
  assert.equal(logic.labelOf("&&&x"), "&x")
})

test("labelOf: trims the result", () => {
  assert.equal(logic.labelOf("  _Open  "), "Open")
  assert.equal(logic.labelOf("_ Open"), "Open")
})

test("labelOf: no marker is unchanged (beyond trimming)", () => {
  assert.equal(logic.labelOf("Plain text"), "Plain text")
})

test("labelOf: missing or non-string input reads '', never throwing", () => {
  assert.equal(logic.labelOf(undefined), "")
  assert.equal(logic.labelOf(null), "")
  assert.equal(logic.labelOf(""), "")
})

// --- rowKey --------------------------------------------------------------------------

test("rowKey: id plus the stripped label, joined with '|'", () => {
  assert.equal(logic.rowKey({ id: 3, text: "_Open" }), "3|Open")
  assert.equal(logic.rowKey({ id: "a1", text: "Plain" }), "a1|Plain")
})

test("rowKey: a missing id or text reads as empty, never throwing", () => {
  assert.equal(logic.rowKey({ text: "x" }), "|x")
  assert.equal(logic.rowKey({ id: 1 }), "1|")
  assert.equal(logic.rowKey(null), "|")
  assert.equal(logic.rowKey(undefined), "|")
})

// --- menuRows (stock's quirks) ---------------------------------------------------------
//
// Quirks read from /usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml
// ~652-663 (rootTitleEntry, leadingSeparator, hiddenRow).

/**
 * A MenuEntry fixture with sane defaults, overridden per test.
 * @param {object} overrides - fields to override
 * @returns {object} the entry
 */
function entry(overrides) {
  return Object.assign(
    {
      id: "e",
      text: "Entry",
      enabled: true,
      isSeparator: false,
      hasChildren: false,
      buttonType: "none",
      checkState: "unchecked",
      icon: ""
    },
    overrides
  )
}

test("menuRows: a non-array entries gives []", () => {
  assert.deepEqual(logic.menuRows(null, true, "Courier"), [])
  assert.deepEqual(logic.menuRows(undefined, true, "Courier"), [])
})

test("menuRows: a leading separator at index 0 is dropped at the root", () => {
  const entries = [entry({ isSeparator: true }), entry({ id: "a", text: "A" })]
  const rows = logic.menuRows(entries, true, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [1]
  )
})

test("menuRows: a leading separator at index 1 is also dropped at the root", () => {
  const entries = [
    entry({ id: "a", text: "A" }),
    entry({ isSeparator: true }),
    entry({ id: "b", text: "B" })
  ]
  const rows = logic.menuRows(entries, true, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [0, 2]
  )
})

test("menuRows: a separator at index 2 or later is kept at the root", () => {
  const entries = [
    entry({ id: "a", text: "A" }),
    entry({ id: "b", text: "B" }),
    entry({ isSeparator: true }),
    entry({ id: "c", text: "C" })
  ]
  const rows = logic.menuRows(entries, true, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [0, 1, 2, 3]
  )
  assert.equal(rows[2].separator, true)
})

test("menuRows: a leading separator is NOT dropped away from the root", () => {
  const entries = [entry({ isSeparator: true }), entry({ id: "a", text: "A" })]
  const rows = logic.menuRows(entries, false, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [0, 1]
  )
})

test("menuRows: a root title entry (hasChildren, label matches appTitle ci) is dropped at index 0", () => {
  const entries = [
    entry({ id: "root", text: "Courier", hasChildren: true }),
    entry({ id: "a", text: "Open" })
  ]
  const rows = logic.menuRows(entries, true, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [1]
  )
})

test("menuRows: the root title match is case-insensitive and mnemonic-insensitive", () => {
  const entries = [
    entry({ id: "root", text: "_COURIER", hasChildren: true }),
    entry({ id: "a", text: "Open" })
  ]
  const rows = logic.menuRows(entries, true, "courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [1]
  )
})

test("menuRows: a title entry WITHOUT children is kept (not a root-title quirk hit)", () => {
  const entries = [
    entry({ id: "root", text: "Courier", hasChildren: false }),
    entry({ id: "a", text: "Open" })
  ]
  const rows = logic.menuRows(entries, true, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [0, 1]
  )
})

test("menuRows: a mismatched label at index 0 is kept even with children", () => {
  const entries = [
    entry({ id: "root", text: "Something else", hasChildren: true }),
    entry({ id: "a", text: "Open" })
  ]
  const rows = logic.menuRows(entries, true, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [0, 1]
  )
})

test("menuRows: a matching title entry at index 0 is kept when NOT at the root", () => {
  const entries = [
    entry({ id: "root", text: "Courier", hasChildren: true }),
    entry({ id: "a", text: "Open" })
  ]
  const rows = logic.menuRows(entries, false, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [0, 1]
  )
})

test("menuRows: a matching title entry past index 0 is kept (quirk is index-0 only)", () => {
  const entries = [
    entry({ id: "a", text: "Open" }),
    entry({ id: "root", text: "Courier", hasChildren: true })
  ]
  const rows = logic.menuRows(entries, true, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [0, 1]
  )
})

test("menuRows: row shape - label stripped, separator/enabled/selectable, mark and markOn, hasChildren, icon, index", () => {
  const entries = [
    entry({ id: "chk", text: "_Enable", buttonType: "check", checkState: "checked" }),
    entry({ id: "radio", text: "Radio", buttonType: "radio", checkState: "unchecked" }),
    entry({ id: "sub", text: "Submenu", hasChildren: true, icon: "img://x" }),
    entry({ id: "dis", text: "Disabled", enabled: false })
  ]
  const rows = logic.menuRows(entries, false, "Courier")
  assert.deepEqual(rows[0], {
    key: "chk|Enable",
    label: "Enable",
    separator: false,
    enabled: true,
    selectable: true,
    mark: "check",
    markOn: true,
    hasChildren: false,
    icon: "",
    index: 0
  })
  assert.deepEqual(rows[1], {
    key: "radio|Radio",
    label: "Radio",
    separator: false,
    enabled: true,
    selectable: true,
    mark: "radio",
    markOn: false,
    hasChildren: false,
    icon: "",
    index: 1
  })
  assert.deepEqual(rows[2], {
    key: "sub|Submenu",
    label: "Submenu",
    separator: false,
    enabled: true,
    selectable: true,
    mark: "",
    markOn: false,
    hasChildren: true,
    icon: "img://x",
    index: 2
  })
  assert.deepEqual(rows[3], {
    key: "dis|Disabled",
    label: "Disabled",
    separator: false,
    enabled: false,
    selectable: false,
    mark: "",
    markOn: false,
    hasChildren: false,
    icon: "",
    index: 3
  })
})

test("menuRows: a separator row is never selectable, marked or carrying children, regardless of its raw fields", () => {
  const entries = [
    entry({
      id: "s",
      text: "ignored",
      isSeparator: true,
      enabled: true,
      hasChildren: true,
      buttonType: "check",
      checkState: "checked"
    })
  ]
  const rows = logic.menuRows(entries, false, "Courier")
  assert.deepEqual(rows[0], {
    key: "s|ignored",
    label: "ignored",
    separator: true,
    enabled: false,
    selectable: false,
    mark: "",
    markOn: false,
    hasChildren: false,
    icon: "",
    index: 0
  })
})

test("menuRows: a partial checkState never reads markOn (matching stock, which only lights Qt.Checked)", () => {
  const entries = [entry({ id: "p", text: "Partial", buttonType: "check", checkState: "partial" })]
  const rows = logic.menuRows(entries, false, "Courier")
  assert.equal(rows[0].markOn, false)
})

test("menuRows: null/non-object entries in the array are skipped without breaking indices", () => {
  const entries = [null, entry({ id: "a", text: "A" }), undefined, entry({ id: "b", text: "B" })]
  const rows = logic.menuRows(entries, false, "Courier")
  assert.deepEqual(
    rows.map((r) => r.index),
    [1, 3]
  )
})

// --- indexOfKey ------------------------------------------------------------------------

test("indexOfKey: the row index for a matching key, or -1", () => {
  const rows = [{ key: "a|A" }, { key: "b|B" }]
  assert.equal(logic.indexOfKey(rows, "b|B"), 1)
  assert.equal(logic.indexOfKey(rows, "z|Z"), -1)
})

test("indexOfKey: a non-array rows, or null/undefined entries, never throws", () => {
  assert.equal(logic.indexOfKey(null, "a|A"), -1)
  assert.equal(logic.indexOfKey(undefined, "a|A"), -1)
  assert.equal(logic.indexOfKey([null, { key: "a|A" }], "a|A"), 1)
})

// --- nextCursor (wrapping) ---------------------------------------------------------------

/**
 * Builds rows from a list of booleans, true meaning selectable (enabled,
 * not a separator).
 * @param {Array<boolean>} spec - which rows are selectable
 * @returns {Array<{separator: boolean, enabled: boolean}>} the rows
 */
function rows(spec) {
  return spec.map((sel) => ({ separator: !sel, enabled: sel }))
}

test("nextCursor: from -1, +1 picks the first selectable row", () => {
  assert.equal(logic.nextCursor(rows([true, true, true]), -1, 1), 0)
})

test("nextCursor: from -1, -1 picks the last selectable row", () => {
  assert.equal(logic.nextCursor(rows([true, true, true]), -1, -1), 2)
})

test("nextCursor: skips separators and disabled rows", () => {
  const r = rows([true, false, false, true])
  assert.equal(logic.nextCursor(r, 0, 1), 3)
  assert.equal(logic.nextCursor(r, 3, -1), 0)
})

test("nextCursor: wraps past either end", () => {
  const r = rows([true, true])
  assert.equal(logic.nextCursor(r, 1, 1), 0)
  assert.equal(logic.nextCursor(r, 0, -1), 1)
})

test("nextCursor: no row selectable gives -1", () => {
  const r = rows([false, false])
  assert.equal(logic.nextCursor(r, -1, 1), -1)
  assert.equal(logic.nextCursor(r, 0, -1), -1)
})

test("nextCursor: a single selectable row stays on itself, wrapping fully around", () => {
  const r = rows([false, true, false])
  assert.equal(logic.nextCursor(r, 1, 1), 1)
  assert.equal(logic.nextCursor(r, 1, -1), 1)
})

test("nextCursor: an empty or non-array rows gives -1, never throwing", () => {
  assert.equal(logic.nextCursor([], -1, 1), -1)
  assert.equal(logic.nextCursor(null, -1, 1), -1)
  assert.equal(logic.nextCursor(undefined, 0, 1), -1)
})

test("nextCursor: an out-of-range from is treated like -1", () => {
  const r = rows([true, true, true])
  assert.equal(logic.nextCursor(r, 99, 1), 0)
  assert.equal(logic.nextCursor(r, -5, -1), 2)
})

// --- jumpTo (type-to-jump, cycling) -------------------------------------------------------

/**
 * Builds selectable rows carrying the given labels, optionally with some
 * disabled per `selectableOverride`.
 * @param {Array<string>} labels - each row's label
 * @param {Array<boolean>} [selectableOverride] - per-row enabled flags, all enabled when omitted
 * @returns {Array<{label: string, separator: boolean, enabled: boolean}>} the rows
 */
function labeled(labels, selectableOverride) {
  return labels.map((label, i) => ({
    label,
    separator: false,
    enabled: selectableOverride ? selectableOverride[i] : true
  }))
}

test("jumpTo: the next selectable row whose label starts with the letter, case-insensitive", () => {
  const r = labeled(["Apple", "Banana", "Avocado"])
  assert.equal(logic.jumpTo(r, -1, "a"), 0)
  assert.equal(logic.jumpTo(r, 0, "A"), 2)
})

test("jumpTo: wraps past the end", () => {
  const r = labeled(["Apple", "Banana", "Avocado"])
  assert.equal(logic.jumpTo(r, 2, "a"), 0)
})

test("jumpTo: cycles back onto `from` itself when it is the only match", () => {
  const r = labeled(["Apple", "Banana"])
  assert.equal(logic.jumpTo(r, 0, "a"), 0)
})

test("jumpTo: skips disabled rows", () => {
  const r = labeled(["Apple", "Avocado"], [true, false])
  assert.equal(logic.jumpTo(r, -1, "a"), 0)
  assert.equal(logic.jumpTo(r, 0, "a"), 0)
})

test("jumpTo: no match returns `from` unchanged", () => {
  const r = labeled(["Apple", "Banana"])
  assert.equal(logic.jumpTo(r, 1, "z"), 1)
})

test("jumpTo: an empty/non-array rows, or no letter, gives `from`, never throwing", () => {
  assert.equal(logic.jumpTo([], 3, "a"), 3)
  assert.equal(logic.jumpTo(null, 3, "a"), 3)
  assert.equal(logic.jumpTo(labeled(["Apple"]), 0, ""), 0)
  assert.equal(logic.jumpTo(labeled(["Apple"]), 0, undefined), 0)
})

// --- crumb -----------------------------------------------------------------------------

test("crumb: appTitle then each submenu title, joined with ' › '", () => {
  assert.equal(logic.crumb(["Send a file"], "Courier"), "Courier › Send a file")
  assert.equal(logic.crumb(["A", "B"], "Courier"), "Courier › A › B")
})

test("crumb: just the appTitle with no stack, or just the stack with no title", () => {
  assert.equal(logic.crumb([], "Courier"), "Courier")
  assert.equal(logic.crumb(["Send a file"], ""), "Send a file")
})

test("crumb: falsy entries are skipped, non-array stack gives just the title, never throwing", () => {
  assert.equal(logic.crumb([null, "A", ""], "Courier"), "Courier › A")
  assert.equal(logic.crumb(null, "Courier"), "Courier")
  assert.equal(logic.crumb(undefined, undefined), "")
})

// --- togglePin / toggleHide (stock's exclusivity) ----------------------------------------
//
// /usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml ~189-211.

test("togglePin: pinning adds the id and un-hides it", () => {
  assert.deepEqual(logic.togglePin([], ["x"], "x"), { pinned: ["x"], hidden: [] })
})

test("togglePin: pinning an already-pinned id unpins it, leaving hidden alone", () => {
  assert.deepEqual(logic.togglePin(["x"], ["y"], "x"), { pinned: [], hidden: ["y"] })
})

test("togglePin: never mutates its inputs", () => {
  const pinned = []
  const hidden = ["x"]
  logic.togglePin(pinned, hidden, "x")
  assert.deepEqual(pinned, [])
  assert.deepEqual(hidden, ["x"])
})

test("togglePin: a non-array pinned/hidden reads as [], never throwing", () => {
  assert.deepEqual(logic.togglePin(null, undefined, "x"), { pinned: ["x"], hidden: [] })
})

test("toggleHide: hiding adds the id and unpins it", () => {
  assert.deepEqual(logic.toggleHide(["x"], [], "x"), { pinned: [], hidden: ["x"] })
})

test("toggleHide: hiding an already-hidden id unhides it, leaving pinned alone", () => {
  assert.deepEqual(logic.toggleHide(["y"], ["x"], "x"), { pinned: ["y"], hidden: [] })
})

test("toggleHide: never mutates its inputs", () => {
  const pinned = ["x"]
  const hidden = []
  logic.toggleHide(pinned, hidden, "x")
  assert.deepEqual(pinned, ["x"])
  assert.deepEqual(hidden, [])
})

test("toggleHide: a non-array pinned/hidden reads as [], never throwing", () => {
  assert.deepEqual(logic.toggleHide(undefined, null, "x"), { pinned: [], hidden: ["x"] })
})

// --- manageMove (clamping, {row, pill}) ---------------------------------------------------

test("manageMove: up/down move the row, clamped to [0, rowCount)", () => {
  assert.deepEqual(logic.manageMove({ row: 1, pill: 0 }, 3, "down"), { row: 2, pill: 0 })
  assert.deepEqual(logic.manageMove({ row: 2, pill: 0 }, 3, "down"), { row: 2, pill: 0 })
  assert.deepEqual(logic.manageMove({ row: 1, pill: 0 }, 3, "up"), { row: 0, pill: 0 })
  assert.deepEqual(logic.manageMove({ row: 0, pill: 0 }, 3, "up"), { row: 0, pill: 0 })
})

test("manageMove: left/right choose the pill, leaving the row alone", () => {
  assert.deepEqual(logic.manageMove({ row: 1, pill: 0 }, 3, "right"), { row: 1, pill: 1 })
  assert.deepEqual(logic.manageMove({ row: 1, pill: 1 }, 3, "left"), { row: 1, pill: 0 })
})

test("manageMove: never wraps (unlike the menu's nextCursor)", () => {
  assert.deepEqual(logic.manageMove({ row: 0, pill: 0 }, 3, "up"), { row: 0, pill: 0 })
  assert.deepEqual(logic.manageMove({ row: 2, pill: 0 }, 3, "down"), { row: 2, pill: 0 })
})

test("manageMove: rowCount of 0 clamps the row to 0", () => {
  assert.deepEqual(logic.manageMove({ row: 5, pill: 1 }, 0, "down"), { row: 0, pill: 1 })
})

test("manageMove: a missing or malformed cursor starts at {row: 0, pill: 0}, never throwing", () => {
  assert.deepEqual(logic.manageMove(null, 3, "down"), { row: 1, pill: 0 })
  assert.deepEqual(logic.manageMove(undefined, 3, "right"), { row: 0, pill: 1 })
  assert.deepEqual(logic.manageMove({}, 3, "up"), { row: 0, pill: 0 })
})

test("manageMove: an unrecognised key leaves the cursor as-is (after clamping)", () => {
  assert.deepEqual(logic.manageMove({ row: 1, pill: 1 }, 3, "esc"), { row: 1, pill: 1 })
})

// --- menuTarget (IPC `menu <index>` bounds) ------------------------------------------------

test("menuTarget: an index within the pinned items targets 'pinned'", () => {
  assert.deepEqual(logic.menuTarget(2, 3, 0), { bucket: "pinned", index: 0 })
  assert.deepEqual(logic.menuTarget(2, 3, 1), { bucket: "pinned", index: 1 })
})

test("menuTarget: an index past the pinned items targets 'drawer', re-based to 0", () => {
  assert.deepEqual(logic.menuTarget(2, 3, 2), { bucket: "drawer", index: 0 })
  assert.deepEqual(logic.menuTarget(2, 3, 4), { bucket: "drawer", index: 2 })
})

test("menuTarget: an index past both buckets, or negative, gives null (a no-op)", () => {
  assert.equal(logic.menuTarget(2, 3, 5), null)
  assert.equal(logic.menuTarget(2, 3, -1), null)
  assert.equal(logic.menuTarget(0, 0, 0), null)
})

test("menuTarget: non-finite or malformed input gives null, never throwing", () => {
  assert.equal(logic.menuTarget(2, 3, NaN), null)
  assert.equal(logic.menuTarget(2, 3, undefined), null)
  assert.equal(logic.menuTarget(NaN, NaN, 0), null)
})

// --- displayName (stock's title -> tooltipTitle -> id-after-slash -> Unknown) -----------
//
// /usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml ~448-456.

test("displayName: title wins when present", () => {
  assert.equal(logic.displayName({ title: "Courier", tooltipTitle: "x", id: "y" }), "Courier")
})

test("displayName: falls back to tooltipTitle when title is empty/blank", () => {
  assert.equal(logic.displayName({ title: "", tooltipTitle: "Courier", id: "y" }), "Courier")
  assert.equal(logic.displayName({ title: "   ", tooltipTitle: "Courier" }), "Courier")
})

test("displayName: falls back to the id after its last slash", () => {
  assert.equal(logic.displayName({ id: "/org/freedesktop/StatusNotifierItem/courier" }), "courier")
  assert.equal(logic.displayName({ id: "courier" }), "courier")
})

test("displayName: 'Unknown' when nothing names the item", () => {
  assert.equal(logic.displayName({}), "Unknown")
  assert.equal(logic.displayName(null), "Unknown")
  assert.equal(logic.displayName(undefined), "Unknown")
  assert.equal(logic.displayName({ title: "", tooltipTitle: "", id: "" }), "Unknown")
})

test("menuKeyHint and manageKeyHint name what Enter does", () => {
  assert.equal(logic.menuKeyHint(), "↑↓ move · → open · ← back · enter select")
  assert.equal(logic.manageKeyHint(), "↑↓ move · ←→ pin / hide · enter toggle")
})
