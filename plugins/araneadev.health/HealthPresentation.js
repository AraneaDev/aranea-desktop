// Presentation helpers for health problem rows.

/**
 * Formats a byte count with 1024-based units.
 * @param {number} n - bytes; negative or non-numeric counts as 0
 * @returns {string} the formatted size
 */
function humanBytes(n) {
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var v = Math.max(0, Number(n) || 0)
  var i = 0
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  var text = v >= 10 || i === 0 ? String(Math.round(v)) : v.toFixed(1).replace(/\.0$/, "")
  return text + " " + units[i]
}

if (typeof module !== "undefined") module.exports = { humanBytes: humanBytes }
