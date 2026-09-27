// Emoji search for the picker: parses emojis.json and filters it by keyword
// substring. Loaded by Emojis.qml; tests/emojis.test.sh runs it under Node.

/**
 * One emojis.json entry.
 * @typedef {object} EmojiEntry
 * @property {string} e - The emoji itself.
 * @property {string} k - Space-separated search keywords, starting with its name.
 */

/**
 * Parses the emojis.json text.
 * @param {?string} raw - File contents.
 * @returns {Array<EmojiEntry>} The entries, or an empty list when the text is not a JSON array.
 */
function parseEmojis(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

/**
 * Normalizes a search query for matching.
 * @param {?string} query - Raw text from the search field.
 * @returns {string} The query trimmed and lowercased; "" for null.
 */
function normalizedQuery(query) {
  return String(query || "")
    .trim()
    .toLowerCase()
}

/**
 * Returns an entry's keywords in lowercase for matching.
 * @param {?EmojiEntry} item - An emojis.json entry.
 * @returns {string} Its `k` field lowercased, or "".
 */
function keywordText(item) {
  return String((item && item.k) || "").toLowerCase()
}

/**
 * Filters entries whose keywords contain the query as a substring, in data
 * order; skips entries without an emoji; an empty query matches everything.
 * @param {?Array<EmojiEntry>} emojis - All entries; anything that is not an array counts as empty.
 * @param {?string} query - Search text (normalized with normalizedQuery).
 * @param {?number} [limit] - Maximum results; missing, null or NaN means 1000, negatives mean 0.
 * @returns {Array<EmojiEntry>} The matching entries, at most `limit`.
 */
function filterEmojis(emojis, query, limit) {
  var values = Array.isArray(emojis) ? emojis : []
  var needle = normalizedQuery(query)
  var max = limit === undefined || limit === null ? 1000 : Number(limit)
  if (isNaN(max)) max = 1000
  max = Math.max(0, max)
  if (max === 0) return []

  var out = []

  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item || !item.e) continue
    if (!needle || keywordText(item).indexOf(needle) >= 0) {
      out.push(item)
      if (out.length >= max) break
    }
  }

  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    normalizedQuery: normalizedQuery,
    filterEmojis: filterEmojis
  }
}
