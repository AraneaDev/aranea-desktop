// Clipboard history rules for the Aranea clipboard picker. Forked from
// Omarchy's ClipboardHistory.js (shell/plugins/clipboard): same entry format
// and file, plus kinds, pins and masked, expiring secrets. Entries keep the
// extra fields (kind, secret, secretOverride, pinned, capturedAtMs); Omarchy's
// own parser ignores them, so the file stays readable by the stock picker.
// No QML, no I/O; tests/clipboard.test.sh runs this under Node.

/**
 * A clipboard history entry as stored in the history file.
 * @typedef {object} ClipboardEntry
 * @property {string} type - "text" or "image".
 * @property {string} [text] - The copied text (text entries).
 * @property {string} [path] - The image file (image entries).
 * @property {string} [mime] - The image MIME type (image entries).
 * @property {string} [capturedAt] - Human-readable capture time from the capture script (image entries).
 * @property {string} [kind] - One of KINDS.
 * @property {boolean} [secret] - Masked in the picker and expired after a while.
 * @property {boolean} [secretOverride] - The user's secret choice, which wins over detection.
 * @property {boolean} [pinned] - Kept by limits, expiry and clearing.
 * @property {number} [pinnedAtMs] - When the entry was pinned, in ms.
 * @property {number} [capturedAtMs] - When the entry was captured, in ms.
 */

/**
 * One row of the picker list, built by displayRows.
 * @typedef {object} ClipboardRow
 * @property {string} section - "pinned" or "recent".
 * @property {number} historyIndex - Index of the entry in the history array.
 * @property {string} kind - The entry's kind.
 * @property {boolean} secret - Whether the row is masked.
 * @property {boolean} pinned - Whether the entry is pinned.
 * @property {string} title - The row title.
 * @property {string} detail - "<kind or secret> · <age>".
 * @property {string} fullText - Text for the preview pane ("" for secrets and images).
 * @property {string} previewImage - Image file to preview, or "".
 * @property {string} path - The image or single file path, or "".
 * @property {string} mime - The image MIME type, or "text/plain".
 * @property {string} colour - Colour value for a swatch, or "".
 * @property {string} swatch - Qt colour for the swatch (see swatchColor), or "".
 * @property {number} [pinnedAtMs] - Sort key for pinned rows (pin time, else capture time); set on every row right after it is built.
 */

/**
 * Validates the base fields of a history entry: a non-blank string or text
 * entry becomes {type:"text", text}, an image entry with a path becomes
 * {type:"image", path, mime, capturedAt?}; the extra fields are dropped.
 * @param {*} value - A raw string or parsed entry object.
 * @returns {?ClipboardEntry} The base entry, or null when the value is not a usable entry.
 */
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
    /** @type {ClipboardEntry} */
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

/**
 * Normalizes an entry like normalizeBase and keeps the Aranea extras (kind,
 * secret, secretOverride, pinned, pinnedAtMs, capturedAtMs) when they have the right type.
 * @param {*} value - A raw string or parsed entry object.
 * @returns {?ClipboardEntry} The normalized entry, or null when the value is not a usable entry.
 */
function normalizeEntry(value) {
  var entry = normalizeBase(value)
  if (!entry || !value || typeof value !== "object") return entry
  if (typeof value.kind === "string") entry.kind = value.kind
  if (typeof value.secret === "boolean") entry.secret = value.secret
  if (typeof value.secretOverride === "boolean") entry.secretOverride = value.secretOverride
  if (typeof value.pinned === "boolean") entry.pinned = value.pinned
  var pinnedAt = Number(value.pinnedAtMs)
  if (value.pinnedAtMs !== undefined && value.pinnedAtMs !== null && isFinite(pinnedAt))
    entry.pinnedAtMs = pinnedAt
  var at = Number(value.capturedAtMs)
  if (value.capturedAtMs !== undefined && value.capturedAtMs !== null && isFinite(at))
    entry.capturedAtMs = at
  return entry
}

/**
 * Builds the identity used to de-duplicate entries: "image:<path>" or "text:<text>".
 * @param {?ClipboardEntry} entry - The entry.
 * @returns {string} The key, or "" for a missing entry.
 */
function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

/**
 * Returns a copy of the history without the entry at index; an out-of-range index gives an unchanged copy.
 * @param {*} history - The history array (anything else counts as empty).
 * @param {*} index - The position to remove, coerced with Number().
 * @returns {Array<ClipboardEntry>} The new history array.
 */
function removeEntryAt(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values.slice()

  var next = values.slice()
  next.splice(target, 1)
  return next
}

/**
 * Parses one JSON-encoded entry (as the capture script prints it) and normalizes it.
 * @param {*} line - The JSON text; null or blank gives null.
 * @returns {?ClipboardEntry} The entry, or null when the text is blank, invalid JSON or not an entry.
 */
function parseEntryJson(line) {
  var raw = String(line || "").trim()
  if (!raw) return null
  try {
    return normalizeEntry(JSON.parse(raw))
  } catch (e) {
    return null
  }
}

/**
 * Builds the text the filter matches against: for images "image screenshot"
 * plus mime and capture time, for text the text plus its file-name summary.
 * @param {?ClipboardEntry} entry - The entry.
 * @returns {string} The searchable text, or "" for a missing entry.
 */
function searchableText(entry) {
  if (!entry) return ""
  if (entry.type === "image")
    return "image screenshot " + String(entry.mime || "") + " " + String(entry.capturedAt || "")
  return String(entry.text || "") + " " + fileEntryText(entry)
}

/**
 * Converts a file:// URI (optionally file://localhost/) to an absolute,
 * percent-decoded path; a malformed escape leaves the path undecoded.
 * @param {*} uri - The URI text.
 * @returns {string} The path, or "" when the value is not an absolute file:// URI.
 */
function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try {
    return decodeURIComponent(path)
  } catch (e) {
    return path
  }
}

/**
 * Lists the paths of the file:// URIs in a text entry, one per line (e.g. a file-manager copy).
 * @param {?ClipboardEntry} entry - The entry.
 * @returns {Array<string>} The decoded paths; empty for images and plain text.
 */
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

/**
 * Returns the last "/"-separated component of a path.
 * @param {*} path - The path.
 * @returns {string} The file name.
 */
function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

/**
 * Tells whether a path ends in a common image extension (png, jpg, jpeg, webp, gif, bmp, tif, tiff).
 * @param {*} path - The path.
 * @returns {boolean} True for an image file name.
 */
function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

/**
 * Summarizes the file URIs of a text entry: the file name for one file, "N files" for several.
 * @param {?ClipboardEntry} entry - The entry.
 * @returns {string} The summary, or "" when the entry holds no file URIs.
 */
function fileEntryText(entry) {
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return paths.length + " files"
}

/**
 * Labels an image entry: "Screenshot from <time>" for PNG, "Image from <time>" otherwise, "Image" without a capture time.
 * @param {?ClipboardEntry} entry - The image entry.
 * @returns {string} The label.
 */
function imagePreviewText(entry) {
  var timestamp = String((entry && entry.capturedAt) || "")
  if (!timestamp) return "Image"

  var label = String((entry && entry.mime) || "") === "image/png" ? "Screenshot" : "Image"
  return label + " from " + timestamp
}

/**
 * One-line preview of an entry: the image label, the file summary, or the text with whitespace runs collapsed to single spaces.
 * @param {?ClipboardEntry} entry - The entry.
 * @returns {string} The preview, or "" for a missing entry.
 */
function previewText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return imagePreviewText(entry)
  var fileText = fileEntryText(entry)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

/**
 * Full text of an entry for the preview pane: its file paths one per line, or the raw text.
 * @param {?ClipboardEntry} entry - The entry.
 * @returns {string} The text, or "" for a missing entry.
 */
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

/**
 * Returns a text entry cut to displayTextLimit characters (at the last line
 * break before the limit when there is one); other entries come back as they are.
 * The cut copy keeps only type and text.
 * @param {?ClipboardEntry} entry - The entry.
 * @returns {?ClipboardEntry} The entry itself or a shortened text-only copy.
 */
function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  // Cut on a line break so a file:// URI never truncates into a bogus path.
  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  return { type: "text", text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit) }
}

// ---------------------------------------------------- kinds

var COLOUR_RE = /^(#[0-9a-f]{3}|#[0-9a-f]{6}|#[0-9a-f]{8}|rgba?\([^)]*\)|hsla?\([^)]*\))$/i

/**
 * Classifies an entry by content: image, path (file URIs or lines that are
 * absolute or ~/ paths), link (single http(s) URL), colour (hex, rgb(a),
 * hsl(a)), code (indented multi-line text, or a first line starting "$ " or
 * containing " | " or "&&") and otherwise text.
 * @param {?ClipboardEntry} entry - The entry.
 * @returns {string} One of the KINDS names.
 */
function detectKind(entry) {
  if (!entry) return "text"
  if (entry.type === "image") return "image"
  if (filePaths(entry).length > 0) return "path"
  var text = String(entry.text || "").trim()
  var lines = text.split(/\r?\n/)
  if (lines.length === 1 && /^https?:\/\/\S+$/i.test(text)) return "link"
  if (COLOUR_RE.test(text)) return "colour"
  var allPaths = lines.every(function (l) {
    return /^(\/|~\/)\S*$/.test(l.trim()) && l.trim().length > 1
  })
  if (allPaths) return "path"
  var indented =
    lines.length >= 2 &&
    lines.some(function (l) {
      return /^(\t| {2,})\S/.test(l)
    })
  if (indented || /^\$ /.test(lines[0]) || / \| /.test(lines[0]) || /&&/.test(lines[0]))
    return "code"
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

/**
 * Shannon entropy of the characters of a string, in bits per character.
 * @param {string} text - The text.
 * @returns {number} The entropy; 0 for an empty string.
 */
function entropy(text) {
  /** @type {{[key: string]: number}} */
  var counts = {}
  for (var i = 0; i < text.length; i++) counts[text[i]] = (counts[text[i]] || 0) + 1
  var h = 0
  for (var c in counts) {
    var p = counts[c] / text.length
    h -= (p * Math.log(p)) / Math.LN2
  }
  return h
}

/**
 * Share of a string's letters and digits that sit in word runs of three or
 * more letters (runs split at case changes: "getUserById2Async" gives get,
 * User, By, Id, Async).
 * @param {string} text - The text.
 * @returns {number} A value from 0 to 1; 0 when there are no letters or digits.
 */
function wordShare(text) {
  var runs = text.match(/[A-Z]?[a-z]+|[A-Z]+(?![a-z])/g) || []
  var inWords = 0
  for (var i = 0; i < runs.length; i++) if (runs[i].length >= 3) inWords += runs[i].length
  var alnum = (text.match(/[A-Za-z0-9]/g) || []).length
  return alnum ? inWords / alnum : 0
}

/**
 * Tells whether a string is mostly made of words (wordShare of 0.65 or more).
 * @param {string} text - The text.
 * @returns {boolean} True when word-like.
 */
function wordLike(text) {
  return wordShare(text) >= 0.65
}

/**
 * Recognises developer text that is never a secret: URLs, Unix, home and
 * Windows paths, git hashes, UUIDs, emails, dotted names (optionally ending
 * in "()"), file:line, versions, algo:hex digests, slash-separated word-like
 * names such as owner/repo, and file names with a lowercase extension.
 * @param {string} text - Trimmed text without whitespace.
 * @returns {boolean} True when the text is one of those shapes.
 */
function isDeveloperText(text) {
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(text) || /^https?:/i.test(text)) return true
  if (text.charAt(0) === "/" || text.indexOf("~/") === 0 || /^[A-Za-z]:\\/.test(text)) return true
  if (/^[0-9a-f]{7,40}$/.test(text)) return true
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)) return true
  if (/^[\w.+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/.test(text)) return true
  if (/^[A-Za-z_$][\w$]*(\.[A-Za-z_$][\w$]*)+(\(\))?$/.test(text)) return true
  if (/^[\w.-]+\.[A-Za-z0-9]{1,6}:\d+(:\d+)?$/.test(text)) return true
  if (/^v?\d+(\.\d+)+([-+][0-9A-Za-z.+-]*)?$/.test(text)) return true
  if (/^[a-z0-9]+:[0-9a-f]{16,}$/i.test(text)) return true
  if (
    /^[\w.-]+(\/[\w.-]+)+$/.test(text) &&
    text.split("/").every(function (s) {
      return s.length < 3 || wordLike(s)
    })
  )
    return true
  if (/^[\w-][\w.-]*\.[a-z][a-z0-9]{0,5}$/.test(text)) return true
  return false
}

/**
 * Guesses whether copied text is a secret. Checked in order: a PEM/PGP
 * private key block or a known token format (GitHub, OpenAI-style sk-,
 * Slack, AWS key id, JWT) is one; text with whitespace and developer text
 * (see isDeveloperText) are not; anything shorter than 16 characters is not;
 * text of only letters, digits, _ and - is not when word-like (an
 * identifier); the rest is one when it has at least three character classes
 * and an entropy of 3.5 bits or more.
 * @param {*} value - The text.
 * @returns {boolean} True when the text looks like a secret.
 */
function isSecretText(value) {
  var text = String(value || "").trim()
  if (!text) return false
  if (/-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----/.test(text)) return true
  // Token formats first: a JWT is also a dotted name.
  for (var i = 0; i < SECRET_PATTERNS.length; i++) if (SECRET_PATTERNS[i].test(text)) return true
  if (/\s/.test(text)) return false
  if (isDeveloperText(text)) return false
  if (text.length < 16) return false
  if (/^[A-Za-z0-9_-]+$/.test(text) && wordLike(text)) return false
  var classes =
    (/[a-z]/.test(text) ? 1 : 0) +
    (/[A-Z]/.test(text) ? 1 : 0) +
    (/[0-9]/.test(text) ? 1 : 0) +
    (/[^A-Za-z0-9_-]/.test(text) ? 1 : 0)
  return classes >= 3 && entropy(text) >= 3.5
}

// ---------------------------------------------------- history

/**
 * Normalizes an entry and fills the Aranea fields: capturedAtMs (now when
 * missing), kind (detected unless a known one is stored), secret (false for
 * images, else secretOverride when set, else detected) and pinned (false by default).
 * @param {*} value - A raw string or parsed entry object.
 * @param {*} now - The current time in ms, coerced with Number() (0 when not a number).
 * @returns {?ClipboardEntry} The enriched entry, or null when the value is not a usable entry.
 */
function enrich(value, now) {
  var entry = normalizeEntry(value)
  if (!entry) return null
  if (!(typeof entry.capturedAtMs === "number" && isFinite(entry.capturedAtMs)))
    entry.capturedAtMs = Number(now) || 0
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
// the loader then saves once, so the stamped time (and secret expiry)
// survives restarts.
/**
 * Checks the raw history JSON for an entry without a usable capture time: a
 * plain string entry, or an object whose capturedAtMs is not a finite number
 * (missing, null or a string). Mirrors enrich(), which stamps exactly those.
 * @param {*} raw - The history file contents; empty means "[]".
 * @returns {boolean} True when some entry lacks a capture time; false for invalid JSON or a non-array.
 */
function hadUnstamped(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(parsed)) return false
    return parsed.some(function (e) {
      if (typeof e === "string") return true
      return (
        !!e &&
        typeof e === "object" &&
        !(typeof e.capturedAtMs === "number" && isFinite(e.capturedAtMs))
      )
    })
  } catch (e) {
    return false
  }
}

/**
 * Parses the history file JSON and enriches every entry, dropping unusable ones.
 * @param {*} raw - The history file contents; empty means "[]".
 * @param {*} now - The time in ms stamped on entries that have none.
 * @returns {Array<ClipboardEntry>} The entries; empty for invalid JSON or a non-array.
 */
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
/**
 * Trims a history list to the limit while never dropping pinned entries.
 * @param {Array<ClipboardEntry>} list - The history, newest first.
 * @param {*} limit - The number of unpinned entries to keep, coerced with Number() (0 when not a number).
 * @returns {Array<ClipboardEntry>} The trimmed list.
 */
function applyLimit(list, limit) {
  var max = Math.max(0, Number(limit) || 0)
  var unpinned = 0
  return list.filter(function (e) {
    if (e.pinned) return true
    unpinned++
    return unpinned <= max
  })
}

/**
 * Puts a newly copied value at the top of the history, removing an older
 * copy of the same content (keeping its pin and secretOverride), re-stamping
 * its capture time, and trimming to the limit.
 * @param {*} history - The history array (anything else counts as empty).
 * @param {*} value - The new raw string or entry object.
 * @param {?number} [limit] - Unpinned entries to keep; 300 when null or omitted.
 * @param {*} [now] - The current time in ms.
 * @returns {Array<ClipboardEntry>} The new history, or a copy of the old one when the value is not a usable entry.
 */
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
      if (typeof existing.secretOverride === "boolean")
        entry.secretOverride = existing.secretOverride
      continue
    }
    rest.push(existing)
  }
  delete entry.capturedAtMs
  return applyLimit(
    [enrich(entry, now)].concat(rest),
    limit === undefined || limit === null ? 300 : limit
  )
}

/**
 * Drops unpinned secret entries captured more than ttlMs before now.
 * @param {*} history - The history array (anything else counts as empty).
 * @param {*} now - The current time in ms.
 * @param {*} ttlMs - How long a secret is kept, in ms.
 * @returns {{history: Array<ClipboardEntry>, changed: boolean}} The kept entries and whether any were dropped.
 */
function expire(history, now, ttlMs) {
  var values = Array.isArray(history) ? history : []
  var cutoff = Number(now) - Number(ttlMs)
  var next = values.filter(function (e) {
    return !(e && e.secret && !e.pinned && Number(e.capturedAtMs) < cutoff)
  })
  return { history: next, changed: next.length !== values.length }
}

/**
 * Returns a copy of the history in which the entry at index is replaced by a
 * shallow copy that change() has modified; an invalid index gives an unchanged copy.
 * @param {*} history - The history array (anything else counts as empty).
 * @param {*} index - The position of the entry, coerced with Number().
 * @param {function({[key: string]: *}): void} change - Mutates the copied entry.
 * @returns {Array<ClipboardEntry>} The new history array.
 */
function withEntry(history, index, change) {
  var values = Array.isArray(history) ? history.slice() : []
  var i = Number(index)
  if (!(i >= 0 && i < values.length) || !values[i]) return values
  /** @type {{[key: string]: *}} */
  var copy = {}
  for (var k in values[i]) copy[k] = values[i][k]
  change(copy)
  values[i] = copy
  return values
}

/**
 * Flips the pin of the entry at index, stamping pinnedAtMs when it becomes pinned and removing it when unpinned.
 * @param {*} history - The history array.
 * @param {*} index - The position of the entry.
 * @param {*} now - The current time in ms.
 * @returns {Array<ClipboardEntry>} The new history array.
 */
function togglePinned(history, index, now) {
  return withEntry(history, index, function (e) {
    e.pinned = !e.pinned
    if (e.pinned) e.pinnedAtMs = Number(now) || 0
    else delete e.pinnedAtMs
  })
}

/**
 * Flips the secret flag of the entry at index and records the choice in
 * secretOverride so detection does not undo it; images are left unchanged.
 * Marking an entry secret restamps its capture time, so an old item is not
 * expired the moment it is marked.
 * @param {*} history - The history array.
 * @param {*} index - The position of the entry.
 * @param {*} [now] - The current time in ms; the stamp is left alone when omitted.
 * @returns {Array<ClipboardEntry>} The new history array.
 */
function toggleSecret(history, index, now) {
  return withEntry(history, index, function (e) {
    // Images are never secrets (the thumbnail would still show).
    if (e.type === "image") return
    e.secretOverride = !e.secret
    e.secret = e.secretOverride
    if (e.secret && now !== undefined) e.capturedAtMs = Number(now) || 0
  })
}

/**
 * Removes every unpinned entry.
 * @param {*} history - The history array (anything else counts as empty).
 * @returns {Array<ClipboardEntry>} The pinned entries.
 */
function clearUnpinned(history) {
  return (Array.isArray(history) ? history : []).filter(function (e) {
    return e && e.pinned
  })
}

/**
 * Tells whether an entry may be opened in the editor: secrets never are,
 * because opening writes the text to a file.
 * @param {?{secret?: boolean}} entry - The entry or display row.
 * @returns {boolean} True when it may be opened.
 */
function canOpen(entry) {
  return !!entry && !entry.secret
}

// ---------------------------------------------------- display

/**
 * Formats the time since ms as "now" (under a minute), "Nm", "Nh" or "Nd".
 * @param {*} ms - The past time in ms.
 * @param {*} now - The current time in ms.
 * @returns {string} The short age.
 */
function relativeAge(ms, now) {
  var s = Math.max(0, Math.floor((Number(now) - Number(ms)) / 1000))
  if (s < 60) return "now"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  if (h < 24) return h + "h"
  return Math.floor(h / 24) + "d"
}

/**
 * Time left before an unpinned secret leaves history: "expires in Nm",
 * "expires in Nh" from an hour on, or "expires in <1m".
 * @param {?ClipboardEntry} entry - The entry.
 * @param {*} now - The current time in ms.
 * @param {*} ttlMs - How long a secret is kept, in ms.
 * @returns {string} The text, or "" for a missing, pinned or non-secret entry.
 */
function secretExpiryText(entry, now, ttlMs) {
  if (!entry || !entry.secret || entry.pinned) return ""
  var left = Number(entry.capturedAtMs) + Number(ttlMs) - Number(now)
  var minutes = Math.floor(left / 60000)
  if (!(minutes >= 1)) return "expires in <1m"
  if (minutes >= 60) return "expires in " + Math.floor(minutes / 60) + "h"
  return "expires in " + minutes + "m"
}

/**
 * Splits an http(s) URL into its host (without "www.") and its path (without query or fragment; "" for a bare "/").
 * @param {*} text - The URL text.
 * @returns {{domain: string, path: string}} The parts; both "" when the text is not an http(s) URL.
 */
function linkParts(text) {
  var m = /^https?:\/\/([^/?#]+)([^?#]*)/i.exec(String(text || "").trim())
  if (!m) return { domain: "", path: "" }
  return { domain: m[1].replace(/^www\./, ""), path: m[2] === "/" ? "" : m[2] }
}

/**
 * Returns the trimmed text when it is a CSS colour the picker can swatch (hex, rgb(a), hsl(a)).
 * @param {*} text - The text.
 * @returns {string} The colour, or "".
 */
function colourValue(text) {
  var t = String(text || "").trim()
  return COLOUR_RE.test(t) ? t : ""
}

/**
 * Two lowercase hex digits for a channel value, rounded and clamped to 0–255.
 * @param {number} n - The channel value.
 * @returns {string} The hex pair.
 */
function hexByte(n) {
  var v = Math.max(0, Math.min(255, Math.round(n)))
  return (v < 16 ? "0" : "") + v.toString(16)
}

/**
 * Parses one CSS number, or a percentage of `full` when it ends in "%".
 * @param {string} part - The token, e.g. "59", "50%", "0.5" or "120deg".
 * @param {number} full - The value that 100% stands for.
 * @returns {number} The number, NaN when it is not one.
 */
function cssNumber(part, full) {
  var m = /^(-?\d*\.?\d+)(%|deg)?$/.exec(part)
  if (!m) return NaN
  var n = Number(m[1])
  return m[2] === "%" ? (n / 100) * full : n
}

/**
 * Converts a CSS colour to a string Qt parses with the same meaning:
 * #rgb and #rrggbb as they are (lowercase), #rrggbbaa to Qt's #aarrggbb,
 * and rgb()/rgba()/hsl()/hsla() (comma or space syntax, % or plain numbers,
 * optional alpha) to #rrggbb, or #aarrggbb when the alpha is below 1.
 * @param {*} text - The colour text.
 * @returns {string} The Qt colour, or "" when the text is not a colour this parses.
 */
function swatchColor(text) {
  var t = String(text || "")
    .trim()
    .toLowerCase()
  if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/.test(t)) return t
  var hex8 = /^#([0-9a-f]{6})([0-9a-f]{2})$/.exec(t)
  if (hex8) return "#" + hex8[2] + hex8[1]
  var fn = /^(rgba?|hsla?)\(([^)]*)\)$/.exec(t)
  if (!fn) return ""
  var parts = fn[2].split(/[\s,/]+/).filter(function (p) {
    return p.length > 0
  })
  if (parts.length < 3 || parts.length > 4) return ""
  var alpha = parts.length === 4 ? cssNumber(parts[3], 1) : 1
  var r, g, b
  if (fn[1].charAt(0) === "r") {
    r = cssNumber(parts[0], 255)
    g = cssNumber(parts[1], 255)
    b = cssNumber(parts[2], 255)
  } else {
    var h = (((cssNumber(parts[0], 360) % 360) + 360) % 360) / 360
    var s = cssNumber(parts[1], 1)
    var l = cssNumber(parts[2], 1)
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s
    var p = 2 * l - q
    /**
     * One RGB channel from the HSL helper values.
     * @param {number} x - The hue offset for the channel, 0 to 1 after wrapping.
     * @returns {number} The channel, 0 to 1.
     */
    var hue = function (x) {
      if (x < 0) x += 1
      if (x > 1) x -= 1
      if (x < 1 / 6) return p + (q - p) * 6 * x
      if (x < 1 / 2) return q
      if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6
      return p
    }
    r = hue(h + 1 / 3) * 255
    g = hue(h) * 255
    b = hue(h - 1 / 3) * 255
  }
  if (isNaN(r) || isNaN(g) || isNaN(b) || isNaN(alpha)) return ""
  var rgb = hexByte(r) + hexByte(g) + hexByte(b)
  alpha = Math.max(0, Math.min(1, alpha))
  return alpha < 1 ? "#" + hexByte(alpha * 255) + rgb : "#" + rgb
}

// `kind` comes from the full entry: a capped copy of a large paste has lost it.
/**
 * Title of a picker row: a mask for secrets, host plus path for links, the
 * first line for code, otherwise the one-line preview.
 * @param {ClipboardEntry} entry - The (possibly capped) entry to show.
 * @param {string} kind - The kind of the full entry.
 * @returns {string} The title.
 */
function rowTitle(entry, kind) {
  if (entry.secret) return "••••••••"
  if (kind === "link") {
    var parts = linkParts(entry.text)
    return parts.domain + parts.path
  }
  if (kind === "code") return String(entry.text || "").split(/\r?\n/)[0]
  return previewText(entry)
}

/**
 * Builds the picker rows: filters by query (secrets only match "secret"),
 * keeps every matching pinned entry plus up to limit recent ones, and puts
 * pinned rows first, most recently pinned on top.
 * @param {*} history - The history array (anything else counts as empty).
 * @param {*} query - The filter text; matched case-insensitively as a substring.
 * @param {?number} [limit] - Recent rows to show; 50 when null or omitted.
 * @param {*} [now] - The current time in ms, for the age in each row's detail.
 * @returns {Array<ClipboardRow>} The rows.
 */
function displayRows(history, query, limit, now) {
  var values = Array.isArray(history) ? history : []
  var needle = String(query || "")
    .trim()
    .toLowerCase()
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
    /** @type {ClipboardRow} */
    var row = {
      section: entry.pinned ? "pinned" : "recent",
      historyIndex: i,
      kind: entry.kind || "text",
      secret: !!entry.secret,
      pinned: !!entry.pinned,
      title: rowTitle(shown, entry.kind),
      detail: (entry.secret ? "secret" : entry.kind || "text") + " · " + age,
      fullText: entry.secret || isImage ? "" : fullText(shown),
      previewImage: isImage
        ? String(entry.path || "")
        : paths.length === 1 && isImagePath(paths[0])
          ? paths[0]
          : "",
      path: isImage ? String(entry.path || "") : paths.length === 1 ? paths[0] : "",
      mime: isImage ? String(entry.mime || "image/png") : "text/plain",
      colour: entry.secret ? "" : colourValue(entry.text),
      swatch: entry.secret ? "" : swatchColor(colourValue(entry.text))
    }
    row.pinnedAtMs = Number(entry.pinnedAtMs) || Number(entry.capturedAtMs) || 0
    if (entry.pinned) pinned.push(row)
    else recent.push(row)
  }
  // Most recently pinned first.
  pinned.sort(function (a, b) {
    return b.pinnedAtMs - a.pinnedAtMs
  })
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
    wordShare: wordShare,
    isDeveloperText: isDeveloperText,
    enrich: enrich,
    parseHistory: parseHistory,
    hadUnstamped: hadUnstamped,
    addEntry: addEntry,
    expire: expire,
    togglePinned: togglePinned,
    toggleSecret: toggleSecret,
    clearUnpinned: clearUnpinned,
    canOpen: canOpen,
    relativeAge: relativeAge,
    secretExpiryText: secretExpiryText,
    linkParts: linkParts,
    colourValue: colourValue,
    swatchColor: swatchColor,
    displayRows: displayRows
  }
}
