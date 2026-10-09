// Generated desktop search facade; edit DesktopSearchRanking.js instead.
/** @typedef {{id: string, label: string, aliases?: Array<string>, description?: string, parent?: string, kind?: string, order?: number, [key: string]: *}} MenuItem */
/** @typedef {{[key: string]: MenuItem}} ItemMap */
/* @aranea-facade-start: plugins/araneadev.menu/MenuSearch.js */
// Pure search helpers for MenuModel.js: tokenization, matching and ranking.

/**
 * Replaces route separators with spaces so ids split into words.
 * @param {*} value - the token to normalize
 * @returns {string} the spaced token
 */
function searchableToken(value) {
  return String(value || "").replace(/[._-]+/g, " ")
}

/**
 * Returns the final segment of a dotted route id.
 * @param {*} id - the item id
 * @returns {string} the leaf segment
 */
function leafIdFor(id) {
  var parts = String(id || "").split(".")
  return parts.length > 0 ? parts[parts.length - 1] : id
}

/**
 * Builds the lower-cased text matched for an item's name.
 * @param {MenuItem} entry - the item
 * @returns {string} the searchable text
 */
function nameSearchText(entry) {
  if (!entry) return ""
  var aliases = []
  var values = Array.isArray(entry.aliases) ? entry.aliases : []
  for (var i = 0; i < values.length; i++) aliases.push(searchableToken(values[i]))
  return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")]
    .join(" ")
    .toLowerCase()
}

/**
 * Tells whether a term equals a whitespace-separated word.
 * @param {string} term - a lower-cased search term
 * @param {*} text - the text to split
 * @returns {boolean} true on a whole-word match
 */
function termInSearchWords(term, text) {
  var words = String(text || "")
    .toLowerCase()
    .split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i] === term) return true
  }
  return false
}

/**
 * Tells whether every query term is a whole word in the supplied text.
 * @param {*} query - the search query
 * @param {*} text - the description text
 * @returns {boolean} true when all terms match
 */
function descriptionTextMatches(query, text) {
  var terms = String(query || "")
    .toLowerCase()
    .trim()
    .split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termInSearchWords(terms[i], text)) return false
  }
  return true
}

/**
 * Tells whether a visible item matches every query term.
 * @param {MenuItem} entry - the item
 * @param {*} query - the search query
 * @param {boolean} visible - whether the item is visible
 * @returns {boolean} true when it matches
 */
function matchesQuery(entry, query, visible) {
  if (!entry || entry.id === "root") return false
  if (!visible) return false

  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var terms = String(query || "")
    .toLowerCase()
    .trim()
    .split(/\s+/)

  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    if (nameText.indexOf(terms[i]) >= 0) continue
    if (termInSearchWords(terms[i], descriptionText)) continue
    return false
  }

  return true
}

/**
 * Finds an item's depth without depending on MenuModel's other helpers.
 * @param {ItemMap} items - items by id
 * @param {string} id - the item id
 * @returns {number} the depth
 */
function searchDepthFor(items, id) {
  var depth = 0
  var current = items && items[id]
  /** @type {{[key: string]: boolean}} */
  var seen = {}
  while (current && current.parent && current.parent !== "root" && !seen[current.id]) {
    seen[current.id] = true
    depth++
    current = items[current.parent]
  }
  return depth
}

/**
 * Scores a search hit by match tier, depth and declared order.
 * @param {ItemMap} items - items by id
 * @param {MenuItem} entry - the item
 * @param {*} query - the search query
 * @returns {number} the sortable score
 */
function searchScore(items, entry, query) {
  var needle = String(query || "")
    .toLowerCase()
    .trim()
  var label = entry.label.toLowerCase()
  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var score = 80

  if (label === needle) score = entry.parent === "root" ? 2 : 0
  else if (entry.kind === "app" && label.split(/\s+/).indexOf(needle) >= 0) score = 0
  else if (label.indexOf(needle) === 0) score = 10
  else if (label.indexOf(needle) >= 0) score = 30
  else if (nameText.indexOf(needle) >= 0) score = 40
  else if (descriptionTextMatches(needle, descriptionText)) score = 60

  if (entry.kind === "menu" || entry.kind === "link") score -= 2
  if (entry.kind === "app") score -= 5

  return score * 1000 + searchDepthFor(items, entry.id) * 25 + entry.order
}

if (typeof module !== "undefined") {
  module.exports = {
    searchableToken: searchableToken,
    leafIdFor: leafIdFor,
    nameSearchText: nameSearchText,
    termInSearchWords: termInSearchWords,
    descriptionTextMatches: descriptionTextMatches,
    matchesQuery: matchesQuery,
    searchScore: searchScore
  }
}
/* @aranea-facade-end */
/* @aranea-facade-start: plugins/araneadev.menu/DesktopSearchRanking.js */
// Pure desktop record normalization and ranking. Matching is injected by the
// generated DesktopSearchLogic facade from the canonical MenuSearch module.

/** @typedef {"app"|"command"|"window"|"workspace"|"setting"|"action"} DesktopType */
/** @typedef {{appId?: string, itemId?: string, address?: string, workspaceId?: number|string, selector?: string, section?: string, actionId?:string}} DesktopTarget */
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
 * Parses optional type prefixes, leaving unknown prefixes as text.
 * @param {*} text - query text
 * @returns {{type: ?DesktopType, text: string}} the filter and trimmed query
 */
function parseQuery(text) {
  var raw = String(text || "").trim()
  var prefix = /^(app|command|window|workspace|setting|action):\s*/i.exec(raw)
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
    setting: "section",
    action: "actionId"
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
/* @aranea-facade-end */

/**
 * Ranks desktop results with the canonical menu matching semantics.
 * @param {*} records - current source records
 * @param {*} query - query text including an optional type prefix
 * @returns {Array<DesktopRecord>} up to 50 unique available normalized results
 */
function rankResults(records, query) {
  return rankDesktopResults(records, query, matchesQuery)
}

if (typeof module !== "undefined")
  module.exports = {
    parseQuery: parseQuery,
    normalizeRecord: normalizeRecord,
    normalizeRecords: normalizeRecords,
    rankResults: rankResults,
    resolveTarget: resolveTarget
  }
