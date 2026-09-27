// Clipboard history rules for the Aranea clipboard picker. Forked from
// Omarchy's ClipboardHistory.js (shell/plugins/clipboard): same entry format
// and file, plus kinds, pins and masked, expiring secrets. Entries keep the
// extra fields (kind, secret, secretOverride, pinned, capturedAtMs); Omarchy's
// own parser ignores them, so the file stays readable by the stock picker.
// No QML, no I/O; tests/clipboard.test.sh runs this under Node.

function normalizeBase(value) {
  if (typeof value === "string")
    return value.trim().length > 0 ? { type: "text", text: value } : null

  if (!value || typeof value !== "object") return null

  var type = String(value.type || value.kind || "")
  if (type === "text") {
    var text = String(value.text || "")
    return text.trim().length > 0 ? { type: "text", text: text } : null
  }

  if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    var entry = {
      type: "image",
      path: path,
      mime: String(value.mime || "image/png")
    }
    if (value.capturedAt !== undefined && value.capturedAt !== null)
      entry.capturedAt = String(value.capturedAt)
    return entry
  }

  return null
}

function normalizeEntry(value) {
  var entry = normalizeBase(value)
  if (!entry || !value || typeof value !== "object") return entry
  if (typeof value.kind === "string") entry.kind = value.kind
  if (typeof value.secret === "boolean") entry.secret = value.secret
  if (typeof value.secretOverride === "boolean") entry.secretOverride = value.secretOverride
  if (typeof value.pinned === "boolean") entry.pinned = value.pinned
  var pinnedAt = Number(value.pinnedAtMs)
  if (value.pinnedAtMs !== undefined && value.pinnedAtMs !== null && isFinite(pinnedAt)) entry.pinnedAtMs = pinnedAt
  var at = Number(value.capturedAtMs)
  if (value.capturedAtMs !== undefined && value.capturedAtMs !== null && isFinite(at)) entry.capturedAtMs = at
  return entry
}

function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}



function removeEntryAt(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values.slice()

  var next = values.slice()
  next.splice(target, 1)
  return next
}


function parseEntryJson(line) {
  var raw = String(line || "").trim()
  if (!raw) return null
  try { return normalizeEntry(JSON.parse(raw)) } catch (e) { return null }
}

function searchableText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image screenshot " + String(entry.mime || "") + " " + String(entry.capturedAt || "")
  return String(entry.text || "") + " " + fileEntryText(entry)
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(entry) {
  if (!entry || entry.type !== "text") return []

  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

function fileEntryText(entry) {
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return paths.length + " files"
}

function imagePreviewText(entry) {
  var timestamp = String(entry && entry.capturedAt || "")
  if (!timestamp) return "Image"

  var label = String(entry && entry.mime || "") === "image/png" ? "Screenshot" : "Image"
  return label + " from " + timestamp
}

function previewText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return imagePreviewText(entry)
  var fileText = fileEntryText(entry)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

function fullText(entry) {
  if (!entry) return ""
  var paths = filePaths(entry)
  if (paths.length > 0) return paths.join("\n")
  return String(entry.text || "")
}

// The picker only ever searches and renders a prefix of an entry, so scan and
// render just that much. A single huge paste otherwise costs hundreds of
// megabytes of string work on every keystroke and stalls the whole shell.
// Pasting reads the full entry back from history by index, so nothing is lost.
var displayTextLimit = 8192

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  // Cut on a line break so a file:// URI never truncates into a bogus path.
  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  return { type: "text", text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit) }
}


// ---------------------------------------------------- kinds

var COLOUR_RE = /^(#[0-9a-f]{3}|#[0-9a-f]{6}|#[0-9a-f]{8}|rgba?\([^)]*\)|hsla?\([^)]*\))$/i

function detectKind(entry) {
  if (!entry) return "text"
  if (entry.type === "image") return "image"
  if (filePaths(entry).length > 0) return "path"
  var text = String(entry.text || "").trim()
  var lines = text.split(/\r?\n/)
  if (lines.length === 1 && /^https?:\/\/\S+$/i.test(text)) return "link"
  if (COLOUR_RE.test(text)) return "colour"
  var allPaths = lines.every(function(l) { return /^(\/|~\/)\S*$/.test(l.trim()) && l.trim().length > 1 })
  if (allPaths) return "path"
  var indented = lines.length >= 2 && lines.some(function(l) { return /^(\t| {2,})\S/.test(l) })
  if (indented || /^\$ /.test(lines[0]) || / \| /.test(lines[0]) || /&&/.test(lines[0])) return "code"
  return "text"
}

var KINDS = ["link", "path", "colour", "code", "image", "text"]

// ---------------------------------------------------- secrets

var SECRET_PATTERNS = [
  /^gh[pousr]_[A-Za-z0-9]{20,}$/,
  /^github_pat_[A-Za-z0-9_]{20,}$/,
  /^sk-[A-Za-z0-9_-]{20,}$/,
  /^xox[bpars]-[A-Za-z0-9-]{10,}$/,
  /^AKIA[0-9A-Z]{16}$/,
  /^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/
]

function entropy(text) {
  var counts = {}
  for (var i = 0; i < text.length; i++) counts[text[i]] = (counts[text[i]] || 0) + 1
  var h = 0
  for (var c in counts) {
    var p = counts[c] / text.length
    h -= p * Math.log(p) / Math.LN2
  }
  return h
}

function isSecretText(value) {
  var text = String(value || "").trim()
  if (!text) return false
  if (/-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----/.test(text)) return true
  if (/\s/.test(text)) return false
  if (/^https?:/i.test(text) || text.charAt(0) === "/" || text.indexOf("~/") === 0) return false
  if (/^[0-9a-f]{7,40}$/.test(text)) return false
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)) return false
  for (var i = 0; i < SECRET_PATTERNS.length; i++) if (SECRET_PATTERNS[i].test(text)) return true
  if (text.length < 16) return false
  // Dotted, slashed, colon or @ strings are identifiers, paths, versions,
  // emails or hashes with a prefix -- developer text, not passwords.
  if (/[.\/:@\\()]/.test(text)) return false
  // `-` and `_` join words; they do not make a string look random.
  var classes = (/[a-z]/.test(text) ? 1 : 0) + (/[A-Z]/.test(text) ? 1 : 0) +
    (/[0-9]/.test(text) ? 1 : 0) + (/[^A-Za-z0-9_-]/.test(text) ? 1 : 0)
  return classes >= 3 && entropy(text) >= 3.5
}

// ---------------------------------------------------- history

function enrich(value, now) {
  var entry = normalizeEntry(value)
  if (!entry) return null
  if (!(typeof entry.capturedAtMs === "number" && isFinite(entry.capturedAtMs))) entry.capturedAtMs = Number(now) || 0
  // A stored kind is reused: detecting it again means scanning the whole
  // text on every load.
  if (KINDS.indexOf(entry.kind) < 0) entry.kind = detectKind(entry)
  if (entry.type === "image") entry.secret = false
  else if (typeof entry.secretOverride === "boolean") entry.secret = entry.secretOverride
  else entry.secret = isSecretText(entry.text)
  if (typeof entry.pinned !== "boolean") entry.pinned = false
  return entry
}

// True when some entry has no capture time yet (written by the stock picker):
// the loader then saves once, so the stamped time -- and secret expiry --
// survives restarts.
function hadUnstamped(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(parsed)) return false
    return parsed.some(function(e) { return e && typeof e === "object" && !isFinite(Number(e.capturedAtMs)) })
  } catch (e) {
    return false
  }
}

function parseHistory(raw, now) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(parsed)) return []
    var out = []
    for (var i = 0; i < parsed.length; i++) {
      var entry = enrich(parsed[i], now)
      if (entry) out.push(entry)
    }
    return out
  } catch (e) {
    return []
  }
}

// Keep every pinned entry and the first `limit` unpinned ones, in order.
function applyLimit(list, limit) {
  var max = Math.max(0, Number(limit) || 0)
  var unpinned = 0
  return list.filter(function(e) {
    if (e.pinned) return true
    unpinned++
    return unpinned <= max
  })
}

function addEntry(history, value, limit, now) {
  var entry = normalizeEntry(value)
  if (!entry) return Array.isArray(history) ? history.slice() : []
  var key = entryKey(entry)
  var values = Array.isArray(history) ? history : []
  var rest = []
  for (var i = 0; i < values.length; i++) {
    var existing = values[i]
    if (!existing) continue
    if (entryKey(existing) === key) {
      // A re-copy keeps what the user decided about this item.
      if (existing.pinned) entry.pinned = true
      if (typeof existing.secretOverride === "boolean") entry.secretOverride = existing.secretOverride
      continue
    }
    rest.push(existing)
  }
  delete entry.capturedAtMs
  return applyLimit([enrich(entry, now)].concat(rest), limit === undefined || limit === null ? 300 : limit)
}

function expire(history, now, ttlMs) {
  var values = Array.isArray(history) ? history : []
  var cutoff = Number(now) - Number(ttlMs)
  var next = values.filter(function(e) {
    return !(e && e.secret && !e.pinned && Number(e.capturedAtMs) < cutoff)
  })
  return { history: next, changed: next.length !== values.length }
}

function withEntry(history, index, change) {
  var values = Array.isArray(history) ? history.slice() : []
  var i = Number(index)
  if (!(i >= 0 && i < values.length) || !values[i]) return values
  var copy = {}
  for (var k in values[i]) copy[k] = values[i][k]
  change(copy)
  values[i] = copy
  return values
}

function togglePinned(history, index, now) {
  return withEntry(history, index, function(e) {
    e.pinned = !e.pinned
    if (e.pinned) e.pinnedAtMs = Number(now) || 0
    else delete e.pinnedAtMs
  })
}

function toggleSecret(history, index) {
  return withEntry(history, index, function(e) {
    // Images are never secrets (the thumbnail would still show).
    if (e.type === "image") return
    e.secretOverride = !e.secret
    e.secret = e.secretOverride
  })
}

function clearUnpinned(history) {
  return (Array.isArray(history) ? history : []).filter(function(e) { return e && e.pinned })
}

// ---------------------------------------------------- display

function relativeAge(ms, now) {
  var s = Math.max(0, Math.floor((Number(now) - Number(ms)) / 1000))
  if (s < 60) return "now"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  if (h < 24) return h + "h"
  return Math.floor(h / 24) + "d"
}

function linkParts(text) {
  var m = /^https?:\/\/([^\/?#]+)([^?#]*)/i.exec(String(text || "").trim())
  if (!m) return { domain: "", path: "" }
  return { domain: m[1].replace(/^www\./, ""), path: m[2] === "/" ? "" : m[2] }
}

function colourValue(text) {
  var t = String(text || "").trim()
  return COLOUR_RE.test(t) ? t : ""
}

// `kind` comes from the full entry: a capped copy of a large paste has lost it.
function rowTitle(entry, kind) {
  if (entry.secret) return "••••••••"
  if (kind === "link") {
    var parts = linkParts(entry.text)
    return parts.domain + parts.path
  }
  if (kind === "code") return String(entry.text || "").split(/\r?\n/)[0]
  return previewText(entry)
}

function displayRows(history, query, limit, now) {
  var values = Array.isArray(history) ? history : []
  var needle = String(query || "").trim().toLowerCase()
  var max = limit === undefined || limit === null ? 50 : Math.max(0, Number(limit) || 0)
  var pinned = []
  var recent = []
  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry) continue
    var shown = entry.secret ? entry : cappedEntry(entry)
    // A secret is findable by its label only, never by its content.
    var haystack = entry.secret ? "secret" : searchableText(shown) + " " + (entry.kind || "")
    if (needle && haystack.toLowerCase().indexOf(needle) < 0) continue
    if (!entry.pinned && recent.length >= max) continue
    var paths = entry.secret ? [] : filePaths(shown)
    var isImage = entry.type === "image"
    var age = relativeAge(entry.capturedAtMs, now)
    var row = {
      section: entry.pinned ? "pinned" : "recent",
      historyIndex: i,
      kind: entry.kind || "text",
      secret: !!entry.secret,
      pinned: !!entry.pinned,
      title: rowTitle(shown, entry.kind),
      detail: (entry.secret ? "secret" : (entry.kind || "text")) + " · " + age,
      fullText: entry.secret || isImage ? "" : fullText(shown),
      previewImage: isImage ? String(entry.path || "") : (paths.length === 1 && isImagePath(paths[0]) ? paths[0] : ""),
      path: isImage ? String(entry.path || "") : (paths.length === 1 ? paths[0] : ""),
      mime: isImage ? String(entry.mime || "image/png") : "text/plain",
      colour: entry.secret ? "" : colourValue(entry.text)
    }
    row.pinnedAtMs = Number(entry.pinnedAtMs) || Number(entry.capturedAtMs) || 0
    if (entry.pinned) pinned.push(row)
    else recent.push(row)
  }
  // Most recently pinned first.
  pinned.sort(function(a, b) { return b.pinnedAtMs - a.pinnedAtMs })
  return pinned.concat(recent)
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeEntry: normalizeEntry,
    entryKey: entryKey,
    removeEntryAt: removeEntryAt,
    parseEntryJson: parseEntryJson,
    filePaths: filePaths,
    decodeFileUri: decodeFileUri,
    fullText: fullText,
    detectKind: detectKind,
    isSecretText: isSecretText,
    enrich: enrich,
    parseHistory: parseHistory,
    hadUnstamped: hadUnstamped,
    addEntry: addEntry,
    expire: expire,
    togglePinned: togglePinned,
    toggleSecret: toggleSecret,
    clearUnpinned: clearUnpinned,
    relativeAge: relativeAge,
    linkParts: linkParts,
    colourValue: colourValue,
    displayRows: displayRows
  }
}
