// Pure desktop record normalization and ranking. Matching is injected by the
// generated DesktopSearchLogic facade from the canonical MenuSearch module.

/** @typedef {"app"|"command"|"window"|"workspace"|"setting"} DesktopType */
/** @typedef {{appId?: string, itemId?: string, address?: string, workspaceId?: number|string, selector?: string, section?: string}} DesktopTarget */
/** @typedef {{key: string, type: DesktopType, label: string, detail: string, aliases: Array<string>, target: DesktopTarget, available: boolean, pinned: boolean, recentRank: ?number, activeWorkspace: boolean}} DesktopRecord */
/** @typedef {{id: string, label: string, aliases: Array<string>, description: string}} DesktopMatchEntry */
/**
 * Canonical menu matching callback.
 * @callback DesktopMatcher
 * @param {DesktopMatchEntry} entry - searchable fields
 * @param {string} query - query text
 * @param {boolean} visible - whether the result is available
 * @returns {boolean} whether every query term matches
 */

/**
 * Parses the five optional type prefixes, leaving unknown prefixes as text.
 * @param {*} text - query text
 * @returns {{type: ?DesktopType, text: string}} the filter and trimmed query
 */
function parseQuery(text) {
  var raw = String(text || "").trim()
  var prefix = /^(app|command|window|workspace|setting):\s*/i.exec(raw)
  return {
    type: prefix ? /** @type {DesktopType} */ (prefix[1].toLowerCase()) : null,
    text: prefix ? raw.slice(prefix[0].length).trim() : raw
  }
}

/**
 * Normalizes one selectable result, deriving its key from typed identity.
 * Workspace selectors are optional source-validated compositor metadata;
 * they never replace the canonical workspace id or come from display labels.
 * @param {*} record - source record
 * @returns {?DesktopRecord} a fresh normalized record, or null for invalid data
 */
function normalizeRecord(record) {
  if (!record || typeof record !== "object") return null
  var type = record.type
  /** @type {{[key: string]: string}} */
  var fields = {
    app: "appId",
    command: "itemId",
    window: "address",
    workspace: "workspaceId",
    setting: "section"
  }
  if (!Object.prototype.hasOwnProperty.call(fields, type)) return null
  var label = typeof record.label === "string" ? record.label.trim() : ""
  var sourceTarget = record.target
  if (!label || !sourceTarget || typeof sourceTarget !== "object") return null
  var identity = sourceTarget[fields[type]]
  if (type === "workspace" && typeof identity === "number") {
    if (!isFinite(identity) || Math.floor(identity) !== identity) return null
  } else {
    if (typeof identity !== "string" || !identity.trim()) return null
    identity = identity.trim()
  }
  if (
    type === "setting" &&
    ["appearance", "display", "schedule", "integrations", "notifications"].indexOf(identity) < 0
  )
    return null
  /** @type {DesktopTarget & {[key: string]: *}} */
  var target = {}
  target[fields[type]] = identity
  if (
    type === "workspace" &&
    typeof sourceTarget.selector === "string" &&
    sourceTarget.selector.trim()
  )
    target.selector = sourceTarget.selector.trim()
  var recentRank = record.recentRank
  /** @type {Array<*>} */
  var aliases = Array.isArray(record.aliases) ? record.aliases : []
  return {
    key: type + ":" + identity,
    type: type,
    label: label,
    detail: typeof record.detail === "string" ? record.detail : "",
    aliases: aliases.filter(function (alias) {
      return typeof alias === "string" && !!alias.trim()
    }),
    target: target,
    available: record.available !== false,
    pinned: type === "app" && record.pinned === true,
    recentRank:
      type === "app" && typeof recentRank === "number" && isFinite(recentRank) && recentRank >= 0
        ? recentRank
        : null,
    activeWorkspace: type === "window" && record.activeWorkspace === true
  }
}

/**
 * Normalizes a source snapshot without mutating or deduplicating its records.
 * @param {*} records - source snapshot
 * @returns {Array<DesktopRecord>} valid selectable record shapes
 */
function normalizeRecords(records) {
  var source = Array.isArray(records) ? records : []
  var normalized = []
  for (var i = 0; i < source.length; i++) {
    var record = normalizeRecord(source[i])
    if (record) normalized.push(record)
  }
  return normalized
}

/**
 * Classifies a match using the existing menu matcher for term eligibility.
 * @param {DesktopRecord} record - normalized result
 * @param {string} query - trimmed query without a prefix
 * @param {DesktopMatcher} matcher - canonical menu matching helper
 * @returns {number} tier 0 through 4, or -1 for no match
 */
function desktopMatchTier(record, query, matcher) {
  var needle = query.toLowerCase()
  var label = record.label.toLowerCase()
  var entry = { id: "", label: record.label, aliases: record.aliases, description: record.detail }
  if (!matcher(entry, needle, true)) return -1
  if (!needle || label === needle) return 0
  if (label.indexOf(needle) === 0) return 1
  if (label.indexOf(needle) >= 0) return 2
  if (matcher({ id: "", label: record.label, aliases: [], description: "" }, needle, true)) return 2
  entry.description = ""
  return matcher(entry, needle, true) ? 3 : 4
}

/**
 * Orders normalized matching records with preferences confined to one tier.
 * @param {*} records - current source records
 * @param {*} query - query text including an optional type prefix
 * @param {DesktopMatcher} matcher - canonical menu matching helper
 * @returns {Array<DesktopRecord>} at most 50 unique available results
 */
function rankDesktopResults(records, query, matcher) {
  var parsed = parseQuery(query)
  var ranked = []
  var normalized = normalizeRecords(records)
  for (var i = 0; i < normalized.length; i++) {
    var record = normalized[i]
    if (!record.available || (parsed.type && parsed.type !== record.type)) continue
    var tier = desktopMatchTier(record, parsed.text, matcher)
    if (tier < 0) continue
    ranked.push({
      record: record,
      tuple: [
        tier,
        record.pinned ? 0 : 1,
        record.activeWorkspace ? 0 : 1,
        record.recentRank === null ? Infinity : record.recentRank,
        record.label.toLowerCase(),
        record.key
      ]
    })
  }
  ranked.sort(function (a, b) {
    for (var index = 0; index < a.tuple.length; index++) {
      if (a.tuple[index] !== b.tuple[index]) return a.tuple[index] < b.tuple[index] ? -1 : 1
    }
    return 0
  })
  /** @type {{[key: string]: boolean}} */
  var seen = {}
  var out = []
  for (var j = 0; j < ranked.length && out.length < 50; j++) {
    var row = ranked[j].record
    if (seen[row.key]) continue
    seen[row.key] = true
    out.push(row)
  }
  return out
}

/**
 * Re-resolves a canonical key against the current available snapshot.
 * @param {*} records - current source records, never a captured result list
 * @param {string} key - selected result's canonical key
 * @returns {?DesktopRecord} the current available record, or null
 */
function resolveTarget(records, key) {
  var normalized = normalizeRecords(records)
  for (var i = 0; i < normalized.length; i++) {
    if (normalized[i].key === key && normalized[i].available) return normalized[i]
  }
  return null
}

if (typeof module !== "undefined")
  module.exports = {
    parseQuery: parseQuery,
    normalizeRecord: normalizeRecord,
    normalizeRecords: normalizeRecords,
    rankDesktopResults: rankDesktopResults,
    resolveTarget: resolveTarget
  }
