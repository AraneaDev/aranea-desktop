// Rules for the Aranea emoji picker: the recent row and the name shown for
// the selected emoji. No QML, no I/O; tests/emojis.test.sh runs this under
// Node. Search and data are Omarchy's own (EmojiSearch.js, emojis.json).

var RECENT_CAP = 16

/**
 * Reads the recent-emoji list from the recents state file, keeping only
 * non-empty strings; any parse error or unexpected shape gives an empty list.
 * @param {?string} text - Contents of the recents JSON file ({ version, recent: [...] }).
 * @returns {Array<string>} The stored recent emojis, newest first.
 */
function parseRecents(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || !Array.isArray(parsed.recent)) return []
    return parsed.recent.filter(function (/** @type {*} */ e) {
      return typeof e === "string" && e.length > 0
    })
  } catch (e) {
    return []
  }
}

/**
 * Serializes a recent-emoji list for the recents state file, capped at
 * RECENT_CAP entries, with a trailing newline.
 * @param {?Array<string>} list - Recent emojis, newest first; null counts as empty.
 * @returns {string} The JSON text `{"version":1,"recent":[...]}` plus "\n".
 */
function serializeRecents(list) {
  return JSON.stringify({ version: 1, recent: (list || []).slice(0, RECENT_CAP) }) + "\n"
}

// Newest first, no duplicates, capped.
/**
 * Moves an emoji to the front of the recent list, dropping its older copy
 * and trimming the list to the cap.
 * @param {?Array<string>} list - Current recent emojis; anything that is not an array counts as empty.
 * @param {string} emoji - The emoji just used.
 * @param {number} [cap] - Maximum list length; falsy (missing or 0) means RECENT_CAP.
 * @returns {Array<string>} A new list starting with `emoji`.
 */
function pushRecent(list, emoji, cap) {
  var max = cap || RECENT_CAP
  var next = [emoji]
  var values = Array.isArray(list) ? list : []
  for (var i = 0; i < values.length && next.length < max; i++) {
    if (values[i] !== emoji) next.push(values[i])
  }
  return next
}

// Keywords start with the emoji's name ("grinning face smile grinning
// happy"); take at most three words, stopping at the first repeat.
/**
 * Derives a display name from an emoji's keyword string.
 * @param {?string} keywords - Space-separated keywords from emojis.json.
 * @returns {string} Up to three leading words, cut at the first repeated word; "" when there are none.
 */
function emojiName(keywords) {
  var words = String(keywords || "")
    .trim()
    .split(/\s+/)
    .filter(function (w) {
      return w.length > 0
    })
  var out = []
  for (var i = 0; i < words.length && out.length < 3; i++) {
    if (out.indexOf(words[i]) >= 0) break
    out.push(words[i])
  }
  return out.join(" ")
}

// Keywords for an emoji; a copy stored with the VS16 selector (U+FE0F)
// falls back to the base form the data uses, and vice versa.
/**
 * Looks up an emoji's keywords, trying the exact form, then without VS16
 * selectors, then with a trailing VS16.
 * @param {?{[key: string]: string}} map - Keywords by emoji, built from emojis.json.
 * @param {?string} emoji - The emoji to look up.
 * @returns {string} Its keywords, or "" when no form is found.
 */
function keywordsFor(map, emoji) {
  var m = map || {}
  var e = String(emoji || "")
  if (m[e] !== undefined) return m[e]
  var bare = e.replace(/\uFE0F/g, "")
  if (m[bare] !== undefined) return m[bare]
  if (m[e + "\uFE0F"] !== undefined) return m[e + "\uFE0F"]
  return ""
}

if (typeof module !== "undefined") {
  module.exports = {
    parseRecents: parseRecents,
    serializeRecents: serializeRecents,
    pushRecent: pushRecent,
    emojiName: emojiName,
    keywordsFor: keywordsFor
  }
}
