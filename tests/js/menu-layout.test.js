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
