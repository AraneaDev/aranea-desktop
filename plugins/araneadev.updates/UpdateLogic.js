// Pure update status parsing for the bar widget and its QML service.

/**
 * Create an empty update status object.
 * @returns {any} Empty update status.
 */
function emptyStatus() {
  return {
    available: false,
    count: 0,
    groups: [],
    rebootRequired: false,
    error: "",
    stale: false,
    checkedAt: 0
  }
}

/**
 * Group update rows by source.
 * @param {Array<any>} rows - Raw update rows.
 * @returns {Array<any>} Grouped update rows.
 */
function groupUpdates(rows) {
  /** @type {{[key: string]: any}} */
  var groups = {}
  /** @param {*} row */
  rows.forEach(function (row) {
    var source = String(row.source || "other")
    var name = String(row.name || row.package || row.id || "unknown")
    if (!groups[source]) groups[source] = { source: source, count: 0, items: [] }
    groups[source].count += 1
    groups[source].items.push(name)
  })
  return Object.keys(groups).map(function (source) {
    return groups[source]
  })
}

/**
 * Parse raw updater status into the stable status shape.
 * @param {*} raw - Raw status object.
 * @returns {any} Parsed update status.
 */
function parseStatus(raw) {
  var status = emptyStatus()
  if (!raw || typeof raw !== "object") {
    status.error = "invalid status"
    return status
  }
  if (!Array.isArray(raw.updates)) {
    status.error = "invalid updates"
    return status
  }
  status.groups = groupUpdates(raw.updates)
  status.count = status.groups.reduce(function (
    /** @type {number} */ total,
    /** @type {any} */ group
  ) {
    return total + group.count
  }, 0)
  status.available = status.count > 0
  status.rebootRequired =
    raw.rebootRequired === true ||
    raw.rebootRequired === "yes" ||
    raw.rebootRequired === "true" ||
    raw.rebootRequired === 1
  status.checkedAt = Number.isFinite(Number(raw.checkedAt)) ? Number(raw.checkedAt) : Date.now()
  return status
}

/**
 * Merge a refresh result with the previous valid status.
 * @param {*} previous - Previous status.
 * @param {*} next - New status.
 * @param {number} now - Refresh timestamp.
 * @returns {any} Merged status.
 */
function mergeRefresh(previous, next, now) {
  if (next && !next.error) return Object.assign({}, next, { stale: false, checkedAt: now })
  var old = previous && typeof previous === "object" ? previous : emptyStatus()
  return Object.assign({}, old, {
    error: String(next && next.error ? next.error : "status unavailable"),
    stale: true,
    checkedAt: now
  })
}

/**
 * Derive compact bar display state from update status.
 * @param {*} status - Update status.
 * @returns {any} Display state.
 */
function displayState(status) {
  var value = status && typeof status === "object" ? status : emptyStatus()
  var count = Math.max(0, Number(value.count) || 0)
  var error = !!value.error
  var warning = !!value.rebootRequired
  return {
    visible: count > 0 || warning || error,
    countText: count > 0 ? String(count) : "",
    severity: error ? "error" : warning ? "warning" : count > 0 ? "info" : "muted"
  }
}

/**
 * The update center's header hint: the check state, never an action.
 * @param {any} status - update status (parseStatus / mergeRefresh)
 * @returns {string} "CHECK FAILED", "CHECKED HH:MM", or "" before the first check
 */
function headerHint(status) {
  var s = status || {}
  if (s.error) return "CHECK FAILED"
  var at = Number(s.checkedAt) || 0
  if (at <= 0) return ""
  var d = new Date(at)
  /**
   * Zero-pads a two-digit time component.
   * @param {number} n - Hours or minutes.
   * @returns {string} Two-digit, zero-padded value.
   */
  var pad = function (n) {
    return (n < 10 ? "0" : "") + n
  }
  return "CHECKED " + pad(d.getHours()) + ":" + pad(d.getMinutes())
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus,
    groupUpdates,
    mergeRefresh,
    displayState,
    headerHint
  }
}
