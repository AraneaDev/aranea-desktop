// Logic contract for the menu card layout (MenuLayout.js): running row-list
// heights with the drilldown divider, the space left for rows, and the fold
// that always ends mid-row when the rows do not fit.
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const layout = loadPragma("plugins/araneadev.menu/MenuLayout.js")
const metrics = { baseRowHeight: 40, rowSpacing: 4, rowPeek: 22, dividerHeight: 20 }

/**
 * Round-trips through JSON so arrays from the vm realm compare.
 * @param {*} value - value to copy
 * @returns {*} plain copy
 */
function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

test("menu row totals add spacing and one divider before the drilldown rows", () => {
  const rows = [
    { section: "", height: 40 },
    { section: "", height: 40 },
    { section: "drilldown", height: 58 },
    { section: "drilldown", height: 40 }
  ]
  assert.deepEqual(plain(layout.menuRowTotals(rows, metrics)), [40, 84, 166, 210])
  assert.deepEqual(plain(layout.menuRowTotals([], metrics)), [])
})

test("dmenu row totals only add spacing", () => {
  assert.deepEqual(plain(layout.plainRowTotals([{ height: 40 }, { height: 58 }], 4)), [40, 102])
})

test("the space for rows respects the frozen top, the opening ceiling and the menu ceiling", () => {
  const base = {
    screenHeight: 1080,
    cardTop: -1,
    gapsOut: 10,
    contentMargin: 12,
    headerHeight: 46,
    contentSpacing: 8,
    rootExtrasHeight: 0,
    maxRowsHeight: -1,
    ceiling: 756
  }
  assert.equal(layout.availableRowsHeight(base), 756)
  assert.equal(layout.availableRowsHeight({ ...base, ceiling: 5000 }), 982)
  assert.equal(layout.availableRowsHeight({ ...base, borderInsetY: 4, ceiling: 5000 }), 978)
  assert.equal(layout.availableRowsHeight({ ...base, cardTop: 100, ceiling: 5000 }), 892)
  assert.equal(layout.availableRowsHeight({ ...base, maxRowsHeight: 300 }), 300)
})

test("the fold shows every row that fits, else ends mid-row with a peek", () => {
  assert.equal(layout.foldedListHeight([], 100, metrics), 40)
  assert.equal(layout.foldedListHeight([40, 84], 100, metrics), 84)
  assert.equal(layout.foldedListHeight([40, 84, 128, 172], 130, metrics), 110)
  assert.equal(layout.foldedListHeight([200], 50, metrics), 50)
  assert.equal(layout.foldedListHeight([200], 10, metrics), 40)
})

test("revealing the cursor never scrolls the cursor row itself out of view", () => {
  const base = {
    index: 0,
    count: 5,
    contentY: 0,
    originY: 0,
    contentHeight: 306,
    itemY: 0,
    itemHeight: 58,
    reach: 26
  }
  // The regression: a one-row list (window not sized yet) used to scroll to 44.
  assert.equal(layout.revealContentY({ ...base, viewHeight: 40 }), 0)
  // A tall enough list is left alone at the top.
  assert.equal(layout.revealContentY({ ...base, viewHeight: 208 }), 0)
})

test("revealing the cursor keeps the forward and backward peeks", () => {
  const rows = {
    count: 10,
    originY: 0,
    contentHeight: 436,
    viewHeight: 150,
    itemHeight: 40,
    reach: 26
  }
  // Moving down to row 2 (y 88): 88 + 40 + 26 - 150 = 4 px of scroll.
  assert.equal(layout.revealContentY({ ...rows, index: 2, contentY: 0, itemY: 88 }), 4)
  // Moving up to row 3 (y 132) from contentY 150: keep 26 above it.
  assert.equal(layout.revealContentY({ ...rows, index: 3, contentY: 150, itemY: 132 }), 106)
  // The last row has no forward peek.
  assert.equal(layout.revealContentY({ ...rows, index: 9, contentY: 286, itemY: 396 }), 286)
})

test("the layout's screen size comes from the screen, not the unconfigured window", () => {
  // A freshly mapped layer surface reports 0 (then 500) before it is configured.
  assert.equal(layout.screenExtent(810, 0, 1080), 810)
  assert.equal(layout.screenExtent(810, 500, 1080), 810)
  // Without a screen: the window's size once it has one, else the fallback.
  assert.equal(layout.screenExtent(0, 810, 1080), 810)
  assert.equal(layout.screenExtent(0, 0, 1080), 1080)
})
