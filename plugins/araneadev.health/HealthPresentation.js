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

/**
 * The key a dropdown row is followed and acted on by: the problem's id,
 * falling back to its text when it has none.
 * @param {?{key?: *, summary?: *}} row - a dropdown row
 * @returns {string} the id, else the summary, else ""
 */
function problemKey(row) {
  if (!row) return ""
  if (typeof row.key === "string" && row.key !== "") return row.key
  return typeof row.summary === "string" ? row.summary : ""
}

/**
 * Every row's problemKey joined by newlines, so a host can tell when the
 * rows really moved (an equal list rebuilt gives the same string).
 * @param {?Array<?{key?: *, summary?: *}>} rows - dropdown rows
 * @returns {string} the joined keys, "" for no rows
 */
function problemKeys(rows) {
  return (rows || []).map(problemKey).join("\n")
}

/**
 * The row a keyed action names: row `index`, but only while it still has
 * `key`, so a click or Enter aimed before a re-sort never opens another
 * problem.
 * @param {?Array<?{key?: *, summary?: *}>} rows - dropdown rows
 * @param {number} index - the row the action names
 * @param {*} key - the key the view saw at that row
 * @returns {?object} the row, or null when it no longer carries the key
 */
function keyedProblem(rows, index, key) {
  if (typeof key !== "string" || key === "") return null
  var row = (rows || [])[index]
  return row && problemKey(row) === key ? row : null
}

/**
 * The lit fraction of a strand bar for a usage percentage.
 * @param {number} percent - usage, 0..100
 * @returns {number} the fraction, clamped to 0..1; 0 for a non-number
 */
function barFraction(percent) {
  var p = Number(percent)
  if (!isFinite(p)) return 0
  return Math.max(0, Math.min(1, p / 100))
}

/**
 * Turns the CPU history (percentages, oldest first) into the shared
 * LinkGraph's samples: the load as the receive line, no send line.
 * @param {?Array<number>} history - CPU percentages
 * @returns {Array<{rx: number, tx: number}>} one sample per entry, clamped to 0..100
 */
function cpuSamples(history) {
  return (history || []).map(function (v) {
    return { rx: Math.max(0, Math.min(100, Number(v) || 0)), tx: 0 }
  })
}

if (typeof module !== "undefined")
  module.exports = {
    humanBytes: humanBytes,
    problemKey: problemKey,
    problemKeys: problemKeys,
    keyedProblem: keyedProblem,
    barFraction: barFraction,
    cpuSamples: cpuSamples
  }
