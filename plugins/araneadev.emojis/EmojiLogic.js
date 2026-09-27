// Rules for the Aranea emoji picker: the recent row and the name shown for
// the selected emoji. No QML, no I/O; tests/emojis.test.sh runs this under
// Node. Search and data are Omarchy's own (EmojiSearch.js, emojis.json).

var RECENT_CAP = 16

function parseRecents(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || !Array.isArray(parsed.recent)) return []
    return parsed.recent.filter(function(e) { return typeof e === "string" && e.length > 0 })
  } catch (e) {
    return []
  }
}

function serializeRecents(list) {
  return JSON.stringify({ version: 1, recent: (list || []).slice(0, RECENT_CAP) }) + "\n"
}

// Newest first, no duplicates, capped.
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
function emojiName(keywords) {
  var words = String(keywords || "").trim().split(/\s+/).filter(function(w) { return w.length > 0 })
  var out = []
  for (var i = 0; i < words.length && out.length < 3; i++) {
    if (out.indexOf(words[i]) >= 0) break
    out.push(words[i])
  }
  return out.join(" ")
}

// Keywords for an emoji; a copy stored with the VS16 selector (U+FE0F)
// falls back to the base form the data uses, and vice versa.
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
