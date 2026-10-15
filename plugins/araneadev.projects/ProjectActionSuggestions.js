/** @typedef {{[key:string]:any}} SuggestionData */

var SOURCE_ORDER = ["package.json", "composer", "makefile", "justfile", "cargo", "python"]
/** @type {{[id:string]:string}} */
var SOURCE_NAMES = {
  "package.json": "package.json",
  composer: "Composer",
  makefile: "Makefile",
  justfile: "justfile",
  cargo: "Cargo",
  python: "Python"
}
var PICKS = [
  ["test", "pytest", "artisan test"],
  ["dev", "start", "serve", "artisan serve"],
  ["build"]
]
var PROJECT_LIMIT = 50

/**
 * Readable source name.
 * @param {string} id - detector source id
 * @returns {string} display name
 */
function sourceName(id) {
  return SOURCE_NAMES[id] || id
}

// Live definitions, not the cached alreadySaved flag, decide what is still offered.
/**
 * Suggestions that no saved definition already covers.
 * @param {SuggestionData | null} detection - cached detection for the selected checkout
 * @param {Array<SuggestionData>} definitions - live saved definitions
 * @returns {Array<SuggestionData>} unsaved suggestions in detection order
 */
function pending(detection, definitions) {
  var rows = detection && Array.isArray(detection.suggestions) ? detection.suggestions : []
  var saved = (definitions || []).map(function (d) {
    return JSON.stringify([d.argv, d.cwdRelative])
  })
  return rows.filter(function (row) {
    return !!row && !!row.definition && saved.indexOf(JSON.stringify([row.definition.argv, row.definition.cwdRelative])) < 0
  })
}

/**
 * Rows grouped by package folder: root first, then folders A to Z.
 * @param {Array<SuggestionData>} rows - unsaved suggestions
 * @returns {Array<SuggestionData>} groups with path, title and rows
 */
function groups(rows) {
  /** @type {{[path:string]:Array<{row:SuggestionData,index:number}>}} */
  var byPath = {}
  ;(rows || []).forEach(function (row, index) {
    var path = row.definition.cwdRelative
    ;(byPath[path] = byPath[path] || []).push({ row: row, index: index })
  })
  return Object.keys(byPath)
    .sort(function (/** @type {string} */ a, /** @type {string} */ b) {
      return a === "." ? -1 : b === "." ? 1 : a.localeCompare(b)
    })
    .map(function (path) {
      return {
        path: path,
        title: path === "." ? "Repository root" : path,
        rows: byPath[path]
          .sort(function (/** @type {{row:SuggestionData,index:number}} */ a, /** @type {{row:SuggestionData,index:number}} */ b) {
            return SOURCE_ORDER.indexOf(a.row.source) - SOURCE_ORDER.indexOf(b.row.source) || a.index - b.index
          })
          .map(function (/** @type {{row:SuggestionData,index:number}} */ item) {
            return item.row
          })
      }
    })
}

/**
 * At most one test, dev and build suggestion for the empty Overview.
 * @param {Array<SuggestionData>} rows - unsaved suggestions
 * @returns {Array<SuggestionData>} up to three picks
 */
function overviewPicks(rows) {
  var list = rows || []
  /** @type {Array<SuggestionData>} */
  var picks = []
  PICKS.forEach(function (names) {
    var matches = list.filter(function (row) {
      return names.indexOf(row.entry) >= 0 && picks.indexOf(row) < 0
    })
    var pick =
      matches.filter(function (row) {
        return row.definition.cwdRelative === "."
      })[0] || matches[0]
    if (pick) picks.push(pick)
  })
  return picks
}

/**
 * Rows Add all may save without exceeding the per-project definition limit.
 * @param {Array<SuggestionData>} rows - unsaved suggestions
 * @param {number} savedCount - live saved definitions for this project
 * @returns {SuggestionData} rows, capacity and whether the list was cut
 */
function addPlan(rows, savedCount) {
  var list = rows || []
  var capacity = Math.max(0, PROJECT_LIMIT - (savedCount || 0))
  return { rows: list.slice(0, capacity), capacity: capacity, limited: list.length > capacity }
}

/**
 * Folder, source and command on one line.
 * @param {SuggestionData} row - suggestion
 * @returns {string} source line
 */
function sourceLine(row) {
  var parts = []
  if (row.definition.cwdRelative !== ".") parts.push(row.definition.cwdRelative)
  parts.push(sourceName(row.source))
  parts.push(row.definition.argv.join(" "))
  return parts.join(" · ")
}

/**
 * Preview host and the evidence for its port.
 * @param {SuggestionData} row - suggestion
 * @returns {string} preview line or empty
 */
function previewLine(row) {
  var url = row.definition.previewUrl
  if (!url) return ""
  var host = url.replace(/^https?:\/\//, "").replace(/\/$/, "")
  return row.previewEvidence ? host + " · " + row.previewEvidence : host
}

/**
 * One informational line about sources that were skipped or cut short.
 * @param {Array<SuggestionData> | null} sources - detector source statuses
 * @returns {string} note or empty
 */
function sourceNote(sources) {
  var list = Array.isArray(sources) ? sources : []
  var parts = []
  var missing = list
    .filter(function (s) {
      return s.status === "unavailable"
    })
    .map(function (s) {
      var reason = String(s.reason || "")
      return sourceName(s.source) + (reason ? " (" + reason.charAt(0).toLowerCase() + reason.slice(1) + ")" : "")
    })
  if (missing.length) parts.push("Not checked: " + missing.join(", "))
  list.forEach(function (s) {
    if ((s.status === "invalid" || s.status === "truncated") && s.reason) parts.push(s.reason)
  })
  return parts.join(" · ")
}
