function isChromiumDerived(app, appIcon) {
  var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
  return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0 ||
         source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0 ||
         source.indexOf("opera") >= 0
}

// True when a `<...>` run is an image tag, so the name is read the way Qt's
// parser reads it: after the `<`, the leading run of letters and digits.
//
// Skip everything up to that run rather than matching the separator, because
// there is no JavaScript expression for what Qt skips. QQuickStyledText calls
// skipSpace(), which is QChar::isSpace(), and that set is not `\s`: Qt counts
// U+0085 NEL and `\s` does not, while `\s` counts U+FEFF and Qt does not. A
// name read with `\s` therefore misses a tag written as `<`, U+0085, `img`:
// Qt skips the NEL, reads `img` and issues the GET, while the regex finds no
// name at all and the tag is kept. Measured against Qt 6.11.2.
//
// Over-skipping is the safe direction. It can only classify more runs as
// images, and dropping a run never manufactures a tag: a dropped run joins two
// stretches of text that each contain no `<`.
function isImageTag(tag) {
  var name = /^<[^A-Za-z0-9]*([A-Za-z0-9]+)/.exec(tag)
  return !!name && name[1].toLowerCase() === "img"
}

// The body renders as StyledText so notifications can use the markup the
// body-markup capability advertises (see Service.qml). StyledText honours
// <img src>, and a remote src makes the shell issue an unauthenticated GET
// with no user action, so image tags go before the renderer sees them.
//
// Work in whole tags, never in substrings of one. A `<` opens a tag that runs
// to the next `>`, nested `<` and all, and only a tag whose own name is `img`
// is dropped.
//
// That is the conservative bound, not Qt's exact one: Qt lets a `>` inside a
// quoted attribute value pass without closing the tag, so a Qt tag can be
// longer than the run taken here. Do not "correct" this to match Qt. Taking
// the shorter run only ever splits one Qt tag into several, and a split can
// only expose an `<img` to be dropped, never hide one — whereas honouring
// quotes would let `<b title="a>b"><img src="http://host/x.png">` through.
//
// Deleting a substring is what makes a naive `/<img[^>]*>/g` unsafe. Given
//
//   <im<img src="http://a/decoy.png">g src="http://a/beacon.png">
//
// Qt reads ONE malformed tag named `im` and renders nothing, but removing the
// inner match closes the surviving halves up into `<img src=".../beacon.png">`
// — a live tag the input never contained. The stripper would be manufacturing
// the very thing it exists to remove.
//
// Because every `<` opens a tag, the text between tags never contains one, so
// dropping a tag cannot splice its neighbours into a new one. That makes a
// single pass sufficient, with no re-scanning and no input bound to police.
function stripImageTags(text) {
  var out = ""
  var i = 0

  while (i < text.length) {
    var open = text.indexOf("<", i)
    if (open === -1) {
      out += text.slice(i)
      break
    }

    out += text.slice(i, open)

    // An unterminated tag at the end of the string still reaches the renderer,
    // which closes it itself, so treat the remainder as one tag.
    var close = text.indexOf(">", open)
    var tag = close === -1 ? text.slice(open) : text.slice(open, close + 1)

    if (!isImageTag(tag)) out += tag
    i = close === -1 ? text.length : close + 1
  }

  return out
}

// What the card renders, and the last thing to touch the string before Qt parses
// it. The newline rewrite belongs here rather than in the card because it inserts
// `<br/>` into text stripImageTags chose to KEEP, and a kept tag may hold a `<` of
// its own: `<x`, newline, `<img src="http://…">` is one tag named `x` to both the
// stripper and Qt, until the rewrite splits it into `<x<br/>` and a live image tag
// the input never contained. Measured against Qt 6.11.2 — the rewritten form
// fetches, the original does not. So strip again after, and what Qt parses is what
// was checked last.
function styledBody(body, app, appIcon) {
  return stripImageTags(sanitizeBody(body, app, appIcon).replace(/\r\n|\r|\n/g, "<br/>"))
}

function sanitizeBody(body, app, appIcon) {
  var text = stripImageTags(String(body || ""))
  if (!isChromiumDerived(app, appIcon)) return text

  return text
    .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
    .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
}

function summaryStartsWithGlyph(summary) {
  var text = String(summary || "").replace(/^\s+/, "")
  if (!text) return false

  var offset = 1
  var first = text.charCodeAt(0)
  if (first >= 0xd800 && first <= 0xdbff && text.length > 1) offset = 2

  var spaces = 0
  while (offset < text.length && text.charAt(offset) === " ") {
    spaces++
    offset++
  }

  return spaces >= 2
}

function shouldBypassDnd(notification, criticalUrgency) {
  var appName = String((notification && notification.appName) || "")
  if (appName === "omarchy-action") return true
  return appName === "notify-send" && notification && notification.urgency === criticalUrgency
}

function isEphemeralApp(appName) {
  var name = String(appName || "")
  return name === "notify-send" || name === "omarchy-action"
}

function stringHint(hints, name) {
  try {
    if (hints) {
      var value = hints[name]
      if (value !== undefined && value !== null) return String(value)
    }
  } catch (e) {
  }
  return ""
}

function glyphFromHints(hints) {
  return stringHint(hints, "omarchy-glyph")
}

// The click action: a JSON argv string from omarchy-notification-send
// --exec. Carried as data so a toast restored after a shell restart stays
// clickable (a libnotify action can't — its sender is gone). Run via
// Util.execArgv as bash positional parameters, never a shell string, so
// attacker-controlled values (a title, a filename) can't become commands.
function execArgvFromHints(hints) {
  return stringHint(hints, "omarchy-exec-argv")
}

// Validate a persisted omarchy-exec-argv into a runnable argv, or null. This is
// a STRUCTURAL check only: it fails closed on a malformed hint (non-array, a
// non-string or empty program, or a leading-dash program that argv would read as
// an option). It does not judge intent — a well-formed ["bash","-c",…] is
// accepted. WHICH senders may set this hint is a separate boundary: any
// session-bus process can, by the freedesktop protocol's design (see
// docs/notifications.md), which is equivalent to same-uid code execution.
function parseExecArgv(value) {
  var text = String(value || "")
  if (!text) return null

  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return null
  }

  if (!Array.isArray(parsed) || parsed.length === 0) return null
  for (var i = 0; i < parsed.length; i++) {
    if (typeof parsed[i] !== "string") return null
  }
  if (!parsed[0] || parsed[0].charAt(0) === "-") return null
  return parsed
}

function shouldRenderCompactGlyph(glyph, iconSource, singleLineToast) {
  return String(glyph || "").length > 0 && String(iconSource || "").length === 0 && !!singleLineToast
}

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function normalizedUrgency(value) {
  var urgency = finiteNumber(value, 1)
  return urgency === 0 || urgency === 2 ? urgency : 1
}

function normalizedHints(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

// Normalize the dynamic D-Bus notification object once, before it reaches
// the QML model and card delegates. The protocol is intentionally dynamic;
// the rest of the UI should not have to defend every optional field again.
function normalizeNotification(notification) {
  var source = notification && typeof notification === "object" ? notification : {}
  var expireTimeout = finiteNumber(source.expireTimeout, 0)
  if (expireTimeout < 0) expireTimeout = 0

  return {
    id: finiteNumber(source.id, 0),
    appName: String(source.appName || ""),
    appIcon: String(source.appIcon || ""),
    summary: String(source.summary || ""),
    body: String(source.body || ""),
    image: String(source.image || ""),
    urgency: normalizedUrgency(source.urgency),
    expireTimeout: Math.round(expireTimeout),
    hints: normalizedHints(source.hints),
    tracked: !!source.tracked
  }
}

function snapshotOf(notification, timestamp) {
  var n = normalizeNotification(notification)
  var id = n.id
  var normalizedTimestamp = finiteNumber(timestamp, Date.now())
  return {
    id: id,
    originalId: id,
    app: n.appName,
    appIcon: n.appIcon,
    summary: n.summary,
    body: n.body,
    image: n.image,
    glyph: glyphFromHints(n.hints),
    execArgv: execArgvFromHints(n.hints),
    urgency: n.urgency,
    expireTimeout: n.expireTimeout,
    timestamp: normalizedTimestamp
  }
}

// Everything the popup card draws, and therefore everything an in-place
// update has to write through to the row and its file.
var POPUP_ROLES = ["app", "appIcon", "summary", "body", "image", "glyph", "execArgv", "urgency", "expireTimeout"]

function popupRoles() {
  return POPUP_ROLES
}

// Whether a refresh has anything to write. Each property a client updates
// emits its own signal, and the catch-up refresh after a row is inserted
// usually finds the object exactly as it was snapshotted — without this,
// one update would rewrite the file several times over.
function popupRowChanged(row, updated) {
  var current = row || {}
  var next = updated || {}
  for (var i = 0; i < POPUP_ROLES.length; i++) {
    var role = POPUP_ROLES[i]
    if (current[role] !== next[role]) return true
  }
  return false
}

// A client updating a notification through replaces_id keeps the identity of
// the popup it took over: the file name is the timestamp and id the popup was
// first persisted under, and the restore, replace and archive paths all key
// off that name. Only what the card draws comes from the updated object.
function replacementSnapshot(notification, originalId, timestamp) {
  var updated = snapshotOf(notification, timestamp)
  updated.id = originalId
  updated.originalId = originalId
  return updated
}

function historyEntry(value, normalUrgency) {
  var e = value || {}
  return {
    id: e.id || 0,
    originalId: e.originalId || e.id || 0,
    app: e.app || "",
    appIcon: e.appIcon || "",
    summary: e.summary || "",
    body: e.body || "",
    image: e.image || "",
    glyph: e.glyph || "",
    execArgv: e.execArgv || "",
    urgency: typeof e.urgency === "number" ? e.urgency : normalUrgency,
    expireTimeout: 0,
    timestamp: e.timestamp || 0,
    // Set on live items owned by a monitor (System health); "" otherwise.
    sourceKey: typeof e.sourceKey === "string" ? e.sourceKey : ""
  }
}

// notifications.json holds nothing but the last-set DND preference now that
// history is a directory of files. Older versions kept `pending`/`past`
// (and, older still, `entries`) arrays in there; their presence is reported
// so the service can rewrite the file without the dead payload.
function parseSettings(raw) {
  var text = String(raw || "").trim()
  if (!text) return { error: false, dnd: null, legacy: false }

  try {
    var parsed = JSON.parse(text)
    return {
      error: false,
      dnd: parsed && typeof parsed.dnd === "boolean" ? parsed.dnd : null,
      legacy: !!(parsed && (parsed.pending || parsed.past || parsed.entries))
    }
  } catch (e) {
    return { error: true, errorMessage: String(e), dnd: null, legacy: false }
  }
}

// ---------------------------------------------------- popup persistence
//
// Each on-screen popup is mirrored to its own file under
// ~/.local/state/omarchy/notifications/ so toasts survive shell restarts
// (e.g. the restart `omarchy-update` performs). The file exists exactly as
// long as the popup is on screen: it is written when the toast appears and
// moved into the history/ subdirectory when the toast expires, is dismissed,
// or its action is invoked. History is those moved files, newest last-10.

function popupEntry(value, normalUrgency) {
  var entry = historyEntry(value, normalUrgency)
  var expire = Number((value || {}).expireTimeout || 0)
  if (!isFinite(expire) || expire < 0) expire = 0
  entry.expireTimeout = expire
  // Absolute expiry deadline, set only when a restore resets a surviving
  // popup's display lifetime. Kept out of the entry entirely when unset so
  // restored rows match the roles of freshly received ones.
  var deadline = Number((value || {}).deadline || 0)
  if (isFinite(deadline) && deadline > 0) entry.deadline = deadline
  // Inbox files record whether their toast is still on screen. Files written
  // before the inbox existed have no flag; the loader treats them as live.
  if (value && typeof value.onScreen === "boolean") entry.onScreen = value.onScreen
  return entry
}

function popupFileName(entry) {
  return imageStem(entry) + ".json"
}

// ---------------------------------------------------- persisted images
//
// A notification's images only exist while it is live: Chromium-family
// senders (all Omarchy web apps) delete their scoped /tmp files on close,
// and image-data hints surface as in-process image:// URLs that die with
// the server object. Persisted entries therefore reference their own
// copies, named by the entry's file stem so cleanup can find them from
// the JSON file name alone.

var PERSISTED_IMAGE_ROLES = ["appIcon", "image"]

function imageStem(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || 0)
}

// The filesystem path behind a file-backed image value, or "" for anything
// a copy can't capture: themed icon names, in-process image:// URLs, empty.
function localImageFile(value) {
  var s = String(value || "")
  if (s.indexOf("file://") === 0) {
    s = s.slice(7)
    try { s = decodeURIComponent(s) } catch (e) {}
  }
  return s.charAt(0) === "/" ? s : ""
}

// The entry as it should hit the disk, plus the copies that make it true.
// File-backed images redirect to their copy under imagesDir; dead image://
// URLs drop to "" (the card falls back to the app icon). Already-redirected
// values map onto themselves and produce no copy, keeping restores no-ops.
function persistablePopup(entry, imagesDir) {
  var e = entry || {}
  var out = {}
  for (var key in e) out[key] = e[key]
  var copies = []
  for (var i = 0; i < PERSISTED_IMAGE_ROLES.length; i++) {
    var role = PERSISTED_IMAGE_ROLES[i]
    var value = String(out[role] || "")
    if (!value) continue
    var source = localImageFile(value)
    if (source) {
      var copy = String(imagesDir || "") + imageStem(e) + "-" + role
      if (source !== copy) copies.push({ from: source, to: copy })
      out[role] = "file://" + copy
    } else if (value.indexOf("image://") === 0) {
      out[role] = ""
    }
  }
  return { entry: out, copies: copies }
}

function serializePopup(entry, normalUrgency) {
  // Compact (single-line) on purpose: restore cats every file together and
  // parses line by line, which only works when each file is one line.
  return JSON.stringify(popupEntry(entry, normalUrgency))
}

// Parse the concatenation of every persisted popup file into entries,
// newest-first. Deliberately NO dedupe by originalId: ids restart from 1
// with every server process, so two files sharing an id are usually
// different generations — dropping the older one would silently discard a
// restored critical alert the moment a fresh notification reuses its id.
// The one case that leaves a genuine duplicate (a crash between a
// replacement's write and the replaced file's delete) merely re-shows a
// superseded toast, which expires or is dismissed and cleans itself up.
function parsePopupFiles(raw, normalUrgency) {
  var lines = String(raw || "").split("\n")
  var entries = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      if (value && typeof value === "object") entries.push(popupEntry(value, normalUrgency))
    } catch (e) {
      // A torn write from a crash mid-save — skip the line, keep the rest.
    }
  }
  entries.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return entries
}

// A persisted popup whose lifetime already ran out would have expired on
// screen had the shell kept running, so it is not restored. duration 0 means
// the popup never expires (critical urgency) and always survives restarts.
// A restore-reset deadline outranks the original timestamp: without it, a
// second restart would judge a re-shown toast by a clock that no longer
// governs its display and drop it while it is still on screen.
function popupExpired(entry, duration, now) {
  var deadline = Number((entry || {}).deadline || 0)
  if (isFinite(deadline) && deadline > 0) return Number(now) >= deadline
  var lifetime = Number(duration || 0)
  if (!isFinite(lifetime) || lifetime <= 0) return false
  return (Number(now) - Number((entry || {}).timestamp || 0)) >= lifetime
}

function popupPlacement(barPosition, barClearance, gapsOut) {
  var position = String(barPosition || "top")
  var clearance = Number(barClearance)
  var gap = Number(gapsOut)
  if (!isFinite(clearance)) clearance = 0
  if (!isFinite(gap)) gap = 0

  return {
    anchors: { top: true, bottom: false, left: false, right: true },
    margins: {
      top: position === "top" ? clearance : gap,
      bottom: gap,
      left: gap,
      right: position === "right" ? clearance : gap
    }
  }
}

function groupNotifications(entries) {
  var groups = []
  var indexes = {}
  var rows = Array.isArray(entries) ? entries : []
  for (var i = 0; i < rows.length; i++) {
    var entry = rows[i] || {}
    var key = String(entry.app || "unknown")
    if (indexes[key] === undefined) {
      indexes[key] = groups.length
      groups.push({ app: key, count: 0, entries: [] })
    }
    var group = groups[indexes[key]]
    group.entries.push(entry)
    group.count++
  }
  return groups
}

function collapseQuietHours(entries, quietHours) {
  var rows = Array.isArray(entries) ? entries : []
  return quietHours
    ? { visible: [], count: rows.length }
    : { visible: rows.slice(), count: 0 }
}

function limitHistory(entries, limit) {
  var rows = Array.isArray(entries) ? entries : []
  var max = Number(limit)
  if (!isFinite(max) || max < 0) max = 10
  return rows.slice(0, Math.floor(max))
}

function isWithinQuietHours(window, date) {
  var match = /^(\d{2}):(\d{2})-(\d{2}):(\d{2})$/.exec(String(window || "").trim())
  if (!match) return false
  var startHour = Number(match[1])
  var startMinute = Number(match[2])
  var endHour = Number(match[3])
  var endMinute = Number(match[4])
  if ([startHour, endHour].some(function(v) { return v > 23 }) ||
      [startMinute, endMinute].some(function(v) { return v > 59 })) return false

  var start = startHour * 60 + startMinute
  var end = endHour * 60 + endMinute
  var now = date instanceof Date ? date : new Date()
  var current = now.getHours() * 60 + now.getMinutes()
  if (start === end) return false
  return start < end ? current >= start && current < end : current >= start || current < end
}

if (typeof module !== "undefined") {
  module.exports = {
    isChromiumDerived: isChromiumDerived,
    sanitizeBody: sanitizeBody,
    styledBody: styledBody,
    summaryStartsWithGlyph: summaryStartsWithGlyph,
    shouldBypassDnd: shouldBypassDnd,
    isEphemeralApp: isEphemeralApp,
    stringHint: stringHint,
    glyphFromHints: glyphFromHints,
    execArgvFromHints: execArgvFromHints,
    parseExecArgv: parseExecArgv,
    shouldRenderCompactGlyph: shouldRenderCompactGlyph,
    normalizeNotification: normalizeNotification,
    snapshotOf: snapshotOf,
    popupRoles: popupRoles,
    popupRowChanged: popupRowChanged,
    replacementSnapshot: replacementSnapshot,
    historyEntry: historyEntry,
    parseSettings: parseSettings,
    popupEntry: popupEntry,
    popupFileName: popupFileName,
    imageStem: imageStem,
    localImageFile: localImageFile,
    persistablePopup: persistablePopup,
    serializePopup: serializePopup,
    parsePopupFiles: parsePopupFiles,
    popupExpired: popupExpired,
    popupPlacement: popupPlacement,
    groupNotifications: groupNotifications,
    collapseQuietHours: collapseQuietHours,
    limitHistory: limitHistory,
    isWithinQuietHours: isWithinQuietHours
  }
}
