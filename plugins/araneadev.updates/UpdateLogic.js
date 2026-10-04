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
 * The dropdown header's caption: the check state, never an action. While a
 * check is running this always wins, even over a stale error from the
 * previous one.
 * @param {any} status - update status (parseStatus / mergeRefresh)
 * @param {boolean} [checking] - whether Service is running a check now
 * @returns {string} "checking...", "check failed", "checked HH:MM", or "" before the first check
 */
function statusCaption(status, checking) {
  if (checking) return "checking…"
  var s = status || {}
  if (s.error) return "check failed"
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
  return "checked " + pad(d.getHours()) + ":" + pad(d.getMinutes())
}

/**
 * The status row's content: a node tinted warn or ok, the headline and the
 * update count. Matches the old header/status wording: only a failed check
 * or a pending reboot reads as a warning; updates waiting with neither is
 * still "Up to date" (no feature change from the text-button version).
 * @param {any} status - update status (parseStatus / mergeRefresh)
 * @returns {{tone: string, title: string, subtitle: string}} "warn" or "ok" tone, the headline and the count line
 */
function statusRow(status) {
  var s = status || {}
  var count = Math.max(0, Number(s.count) || 0)
  var warn = !!s.error || !!s.rebootRequired
  return {
    tone: warn ? "warn" : "ok",
    title: s.error ? "Check failed" : s.rebootRequired ? "Reboot required" : "Up to date",
    subtitle: count + (count === 1 ? " update available" : " updates available")
  }
}

/**
 * Moves the keyboard cursor between the two footer pills (0 "Open updater",
 * 1 "Refresh"), wrapping. The first key after opening (or after the pointer
 * placed it) only reveals the cursor at its current index; a later key
 * moves it (CursorLogic.pressIntent is the Enter/Space counterpart).
 * @param {number} index - current cursor index (0 or 1)
 * @param {boolean} keyboardCursor - whether the keyboard is already showing the cursor
 * @param {number} dy - pills to move; 0 does nothing
 * @returns {{index: number, keyboardCursor: boolean}} the new cursor index and mode
 */
function moveCursor(index, keyboardCursor, dy) {
  if (!dy) return { index: index, keyboardCursor: keyboardCursor }
  if (!keyboardCursor) return { index: index, keyboardCursor: true }
  var i = ((Number(index) % 2) + 2) % 2
  return { index: (i + dy + 2) % 2, keyboardCursor: true }
}

/**
 * The key-hint line, naming what Enter does on the cursor's pill: open the
 * updater (pill 0) or refresh (pill 1).
 * @param {number} cursorIndex - the cursor's pill
 * @returns {string} the hint
 */
function keyHint(cursorIndex) {
  if (cursorIndex === 1) return "↑↓ move · enter refresh"
  return "↑↓ move · enter open updater · r refresh"
}

if (typeof module !== "undefined") {
  module.exports = {
    keyHint,
    parseStatus,
    groupUpdates,
    mergeRefresh,
    displayState,
    statusCaption,
    statusRow,
    moveCursor
  }
}
