// Pure rules for the screenshot stand-in names: scripts/capture-screenshots
// hands the Network and Bluetooth dropdowns (their `showcase` IPC method) a
// list of made-up names, and the views draw those instead of real nearby
// network and device names (Audio relabels its rows with showcaseLabels too). Display only; nothing is stored. No QML, no
// I/O; tests/js/showcase-logic.test.js runs this under Node.

/**
 * Reads the stand-in names handed to the `showcase` IPC method.
 * @param {string|undefined} json - a JSON array of strings
 * @returns {string[]|null} the names, or null when the input isn't one
 */
function parseNames(json) {
  var parsed
  try {
    parsed = JSON.parse(String(json))
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed)) return null
  for (var i = 0; i < parsed.length; i++) if (typeof parsed[i] !== "string") return null
  return parsed
}

/**
 * The answer to a `showcase` IPC call. Names are taken only while the
 * dropdown is open, so they can never outlive a capture into a real open
 * (the dropdown clears them on open and on close).
 * @param {boolean} opened - the dropdown is open
 * @param {string|undefined} json - the call's JSON array of strings
 * @returns {{answer: string, names: string[]|null}} "ok" with the names,
 *   or "closed" / "invalid" with null
 */
function showcaseCall(opened, json) {
  if (!opened) return { answer: "closed", names: null }
  var names = parseNames(json)
  return names === null ? { answer: "invalid", names: null } : { answer: "ok", names: names }
}

/**
 * View rows with their labels replaced, by display position, with stand-in
 * names. Rows past the names (or on an empty name) get "<prefix> N", never
 * their real label. Without names the rows come back as they are.
 * @param {Array<Record<string, any>>|null|undefined} rows - view rows, each with a label
 * @param {string[]|undefined} names - the stand-in names; empty when off
 * @param {string} fallbackPrefix - e.g. "Network" or "Device"
 * @param {number} [offset] - names already used by earlier sections
 * @returns {Array<Record<string, any>>} the rows (copies when renamed)
 */
function showcaseLabels(rows, names, fallbackPrefix, offset) {
  if (!Array.isArray(names) || names.length === 0)
    return /** @type {Array<Record<string, any>>} */ (rows)
  var list = Array.isArray(rows) ? rows : []
  var start = offset || 0
  var out = []
  for (var i = 0; i < list.length; i++) {
    /** @type {Record<string, any>} */
    var copy = {}
    for (var k in list[i]) copy[k] = list[i][k]
    var n = start + i
    copy.label = names[n] ? names[n] : fallbackPrefix + " " + (n + 1)
    out.push(copy)
  }
  return out
}

/**
 * The label of the connected row, for the Network header title.
 * @param {Array<{label: string, connected?: boolean}>|undefined} rows - view rows
 * @returns {string} the label, or "" when no row is connected
 */
function connectedLabel(rows) {
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) if (list[i].connected) return list[i].label
  return ""
}

if (typeof module !== "undefined")
  module.exports = { parseNames, showcaseCall, showcaseLabels, connectedLabel }
