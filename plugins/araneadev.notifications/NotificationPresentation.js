// Presentation-state helpers shared by notification toast surfaces.

/**
 * Caps a timestamp at the current time.
 * @param {*} ts - Timestamp.
 * @param {number} now - Current timestamp.
 * @returns {number} Capped timestamp.
 */
function clampTimestamp(ts, now) {
  var t = Number(ts) || 0
  return t > now ? now : t
}

/**
 * Adds or releases one screen's pause hold for a toast.
 * @param {{[key: string]: number}} holds - Existing hold counts.
 * @param {string} key - Toast key.
 * @param {boolean} on - Whether to add a hold.
 * @returns {{[key: string]: number}} Updated counts.
 */
function holdPopup(holds, key, on) {
  /** @type {{[key: string]: number}} */
  var next = {}
  for (var k in holds || {}) next[k] = holds[k]
  var count = (next[key] || 0) + (on ? 1 : -1)
  if (count > 0) next[key] = count
  else delete next[key]
  return next
}

/**
 * Computes popup anchors and margins for a bar position.
 * @param {*} barPosition - Bar position.
 * @param {*} barClearance - Clearance at the bar edge.
 * @param {*} gapsOut - Outer gap.
 * @returns {{anchors: object, margins: object}} Popup placement.
 */
function popupPlacement(barPosition, barClearance, gapsOut) {
  var position = String(barPosition || "top")
  var clearance = Number(barClearance)
  var gap = Number(gapsOut)
  if (!isFinite(clearance)) clearance = 0
  if (!isFinite(gap)) gap = 0
  return {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: {
      top: position === "top" ? clearance : gap,
      bottom: gap,
      left: gap,
      right: position === "right" ? clearance : gap
    }
  }
}

/**
 * Tests whether a time falls inside a quiet-hours window.
 * @param {?string} window - HH:MM-HH:MM window.
 * @param {?Date} date - Time to test.
 * @returns {boolean} Whether the time is quiet.
 */
function isWithinQuietHours(window, date) {
  var match = /^(\d{2}):(\d{2})-(\d{2}):(\d{2})$/.exec(String(window || "").trim())
  if (!match) return false
  var startHour = Number(match[1])
  var startMinute = Number(match[2])
  var endHour = Number(match[3])
  var endMinute = Number(match[4])
  if (
    [startHour, endHour].some(function (v) {
      return v > 23
    }) ||
    [startMinute, endMinute].some(function (v) {
      return v > 59
    })
  )
    return false
  var start = startHour * 60 + startMinute
  var end = endHour * 60 + endMinute
  var now = date instanceof Date ? date : new Date()
  var current = now.getHours() * 60 + now.getMinutes()
  if (start === end) return false
  return start < end ? current >= start && current < end : current >= start || current < end
}

if (typeof module !== "undefined")
  module.exports = {
    clampTimestamp: clampTimestamp,
    holdPopup: holdPopup,
    popupPlacement: popupPlacement,
    isWithinQuietHours: isWithinQuietHours
  }
