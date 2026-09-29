// Pure search helpers for MenuModel.js: tokenization, matching and ranking.

/** Replaces route separators with spaces so ids split into words. */
function searchableToken(value) {
  return String(value || "").replace(/[._-]+/g, " ")
}

/** Returns the final segment of a dotted route id. */
function leafIdFor(id) {
  var parts = String(id || "").split(".")
  return parts.length > 0 ? parts[parts.length - 1] : id
}

/** Builds the lower-cased text matched for an item's name. */
function nameSearchText(entry) {
  if (!entry) return ""
  var aliases = []
  var values = Array.isArray(entry.aliases) ? entry.aliases : []
  for (var i = 0; i < values.length; i++) aliases.push(searchableToken(values[i]))
  return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")]
    .join(" ")
    .toLowerCase()
}

/** Tells whether a term equals a whitespace-separated word. */
function termInSearchWords(term, text) {
  var words = String(text || "")
    .toLowerCase()
    .split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i] === term) return true
  }
  return false
}

/** Tells whether every query term is a whole word in the supplied text. */
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

/** Tells whether a visible item matches every query term. */
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

/** Finds an item's depth without depending on MenuModel's other helpers. */
function searchDepthFor(items, id) {
  var depth = 0
  var current = items && items[id]
  var seen = {}
  while (current && current.parent && current.parent !== "root" && !seen[current.id]) {
    seen[current.id] = true
    depth++
    current = items[current.parent]
  }
  return depth
}

/** Scores a search hit by match tier, depth and declared order. */
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
