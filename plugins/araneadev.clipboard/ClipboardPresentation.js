// Display-only formatting for clipboard rows.

/** @typedef {{secret?: boolean, pinned?: boolean, capturedAtMs?: number}} ClipboardPresentationEntry */

/**
 * Formats an elapsed timestamp for a clipboard row.
 * @param {*} ms - Captured timestamp.
 * @param {*} now - Current timestamp.
 * @returns {string} Short elapsed age.
 */
function relativeAge(ms, now) {
  var s = Math.max(0, Math.floor((Number(now) - Number(ms)) / 1000))
  if (s < 60) return "now"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  if (h < 24) return h + "h"
  return Math.floor(h / 24) + "d"
}

/**
 * Formats the remaining lifetime of an unpinned secret entry.
 * @param {?ClipboardPresentationEntry} entry - Clipboard entry.
 * @param {*} now - Current timestamp.
 * @param {*} ttlMs - Secret lifetime.
 * @returns {string} Expiry label or an empty string.
 */
function secretExpiryText(entry, now, ttlMs) {
  if (!entry || !entry.secret || entry.pinned) return ""
  var left = Number(entry.capturedAtMs) + Number(ttlMs) - Number(now)
  var minutes = Math.floor(left / 60000)
  if (!(minutes >= 1)) return "expires in <1m"
  if (minutes >= 60) return "expires in " + Math.floor(minutes / 60) + "h"
  return "expires in " + minutes + "m"
}

if (typeof module !== "undefined")
  module.exports = { relativeAge: relativeAge, secretExpiryText: secretExpiryText }
