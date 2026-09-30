// Pure layout math for the Aranea menu card: running row-list heights, the
// space the card can give its rows, and the fold that ends mid-row when the
// rows do not fit. Menu.qml imports it; tests/js/menu-layout.test.js covers it.

/** @typedef {{baseRowHeight: number, rowSpacing: number, rowPeek: number, dividerHeight: number}} LayoutMetrics */

/**
 * Running totals of a menu row list: spacing between rows and one divider before the first drilldown row.
 * @param {Array<{section: string, height: number}>} rows - display rows in order
 * @param {{rowSpacing: number, dividerHeight: number}} metrics - style metrics
 * @returns {Array<number>} total height after each row
 */
function menuRowTotals(rows, metrics) {
  var totals = []
  var total = 0
  var previousSection = ""
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) total += metrics.rowSpacing
    if (rows[i].section === "drilldown" && previousSection !== "drilldown")
      total += metrics.dividerHeight
    total += rows[i].height
    previousSection = rows[i].section
    totals.push(total)
  }
  return totals
}

/**
 * Running totals of a dmenu row list (spacing only, no sections).
 * @param {Array<{height: number}>} rows - display rows in order
 * @param {number} rowSpacing - gap between rows
 * @returns {Array<number>} total height after each row
 */
function plainRowTotals(rows, rowSpacing) {
  var totals = []
  var total = 0
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) total += rowSpacing
    total += rows[i].height
    totals.push(total)
  }
  return totals
}

/**
 * Height the card can give its rows before running off the screen, or past the
 * frozen top edge once a search has pinned the card; capped by the opening's
 * ceiling (drilling into a longer submenu scrolls instead of growing the card)
 * and by the menu's own ceiling.
 * @param {{screenHeight: number, cardTop: number, gapsOut: number, contentMargin: number, headerHeight: number, contentSpacing: number, rootExtrasHeight: number, maxRowsHeight: number, ceiling: number, borderInsetY: (number|undefined)}} input - screen, card and style numbers; cardTop and maxRowsHeight are -1 when unset; borderInsetY (the card border's top plus bottom) defaults to 0 when omitted
 * @returns {number} available row-list height
 */
function availableRowsHeight(input) {
  var top = input.cardTop >= 0 ? input.cardTop : input.gapsOut
  var available =
    input.screenHeight -
    top -
    input.gapsOut -
    input.contentMargin * 2 -
    (input.borderInsetY || 0) -
    input.headerHeight -
    input.contentSpacing -
    input.rootExtrasHeight
  if (input.maxRowsHeight >= 0) available = Math.min(available, input.maxRowsHeight)
  return Math.min(available, input.ceiling)
}

/**
 * Row-list height: every row when they all fit; otherwise the card ends mid-row,
 * because a clipped row is what tells the eye there is more below the fold.
 * @param {Array<number>} totals - running totals from menuRowTotals or plainRowTotals
 * @param {number} available - height the rows may take
 * @param {LayoutMetrics} metrics - style metrics (baseRowHeight, rowSpacing, rowPeek)
 * @returns {number} the row-list height
 */
function foldedListHeight(totals, available, metrics) {
  var count = totals.length
  if (count === 0) return metrics.baseRowHeight
  if (totals[count - 1] <= available) return totals[count - 1]
  var full = 0
  while (full < count && totals[full] <= available) full++
  while (full > 1 && totals[full - 1] + metrics.rowSpacing + metrics.rowPeek > available) full--
  if (full < 1) return Math.max(available, metrics.baseRowHeight)
  return totals[full - 1] + metrics.rowSpacing + metrics.rowPeek
}

if (typeof module !== "undefined")
  module.exports = {
    menuRowTotals: menuRowTotals,
    plainRowTotals: plainRowTotals,
    availableRowsHeight: availableRowsHeight,
    foldedListHeight: foldedListHeight
  }
