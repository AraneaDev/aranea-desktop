// Pure rules for the notification inbox, toast stack and center. No QML, no
// I/O: Service.qml, Inbox.qml and Panel.qml call these, and
// tests/notifications.test.sh runs them under Node.

var MAX_ITEMS = 100
var MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000
var COLLAPSE_AT = 3
var CONFIRM_CLEAR_ABOVE = 20
var SWIPE_DISTANCE_RATIO = 0.35
var SWIPE_FLICK_VELOCITY = 900
var CLICK_SUPPRESS_PX = 4

var LOW = 0
var CRITICAL = 2

/**
 * A plain object with arbitrary keys: an inbox entry, a group, a center row.
 * @typedef {{[key: string]: *}} Dict
 */

/**
 * Whether a notification earns an inbox entry. `transient` is the freedesktop
 * "popup only, don't store" hint. Low-urgency CLI/omarchy-action toasts are
 * feedback for something the user just did (volume, "Theme changed").
 * @param {boolean} ephemeralApp - whether the sender is notify-send or omarchy-action
 * @param {number} urgency - the notification's urgency (0 low, 1 normal, 2 critical)
 * @param {boolean} transient - the freedesktop transient hint
 * @returns {boolean} true when the notification goes into the inbox
 */
function shouldStore(ephemeralApp, urgency, transient) {
  if (transient) return false
  return !(ephemeralApp && Number(urgency) === LOW)
}

/**
 * Whether closing a toast removes its inbox entry.
 *
 * A toast that simply ran out of time was missed, so it waits in the center.
 * Any deliberate action on it means the user has seen it.
 * @param {string} reason - why the toast closed, e.g. "expire" or "dismiss"
 * @returns {boolean} false only for "expire"
 */
function removesFromInbox(reason) {
  return String(reason) !== "expire"
}

/**
 * Replaces the entry with the same fileName in a copy of the list, or puts the
 * entry first when it is new.
 * @param {Array<Dict>} entries - inbox entries
 * @param {Dict} entry - the entry to insert or replace
 * @returns {Array<Dict>} a new array
 */
function upsertOrder(entries, entry) {
  var rows = Array.isArray(entries) ? entries.slice() : []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] && rows[i].fileName === entry.fileName) {
      rows[i] = entry
      return rows
    }
  }
  rows.unshift(entry)
  return rows
}

/**
 * Sort comparator that puts the larger timestamp first.
 * @param {Dict} a - an entry
 * @param {Dict} b - another entry
 * @returns {number} negative when a is newer
 */
function newestFirst(a, b) {
  return (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0)
}

/**
 * Splits the inbox into entries to keep and to delete: non-critical entries
 * older than MAX_AGE_MS go, then the oldest beyond MAX_ITEMS (non-critical
 * ones first).
 *
 * Entries on screen are never pruned: their toast still owns the file.
 * @param {Array<Dict>} entries - inbox entries
 * @param {number} now - current time in ms
 * @returns {Dict} {keep, drop}; keep is sorted newest first
 */
function pruneInbox(entries, now) {
  var rows = (Array.isArray(entries) ? entries : []).filter(function (e) {
    return !!e
  })
  /** @type {Array<Dict>} */
  var keep = []
  /** @type {Array<Dict>} */
  var drop = []
  var cutoff = Number(now) - MAX_AGE_MS
  for (var i = 0; i < rows.length; i++) {
    var e = rows[i]
    var aged = (Number(e.timestamp) || 0) < cutoff
    if (aged && !e.onScreen && Number(e.urgency) !== CRITICAL) drop.push(e)
    else keep.push(e)
  }
  keep.sort(newestFirst)

  /**
   * Moves the oldest off-screen entries that match the predicate from keep to
   * drop until keep fits MAX_ITEMS.
   * @param {function(Dict): boolean} predicate - which entries may go
   */
  function dropOldest(predicate) {
    for (var j = keep.length - 1; j >= 0 && keep.length > MAX_ITEMS; j--) {
      if (!keep[j].onScreen && predicate(keep[j])) drop.push(keep.splice(j, 1)[0])
    }
  }
  dropOldest(function (x) {
    return Number(x.urgency) !== CRITICAL
  })
  dropOldest(function () {
    return true
  })
  return { keep: keep, drop: drop }
}

/**
 * What a released swipe does: a rightward drag past SWIPE_DISTANCE_RATIO of the
 * card's width, or a rightward flick of SWIPE_FLICK_VELOCITY px/s, dismisses.
 * @param {number} dx - horizontal drag distance
 * @param {number} width - card width
 * @param {number} velocity - horizontal release velocity
 * @returns {string} "dismiss" or "restore"
 */
function swipeOutcome(dx, width, velocity) {
  var d = Number(dx) || 0
  if (d <= 0) return "restore"
  if (d >= (Number(width) || 0) * SWIPE_DISTANCE_RATIO) return "dismiss"
  if ((Number(velocity) || 0) >= SWIPE_FLICK_VELOCITY) return "dismiss"
  return "restore"
}

/**
 * Whether a drag moved far enough (over CLICK_SUPPRESS_PX) that its release
 * must not count as a click.
 * @param {number} distance - drag distance in px, either sign
 * @returns {boolean} true to swallow the click
 */
function suppressesClick(distance) {
  return Math.abs(Number(distance) || 0) > CLICK_SUPPRESS_PX
}

/**
 * Groups entries by app for the center. A group of COLLAPSE_AT or more starts
 * collapsed to its newest entry unless the user toggled it.
 *
 * entries newest-first; expanded maps app -> true/false for user overrides.
 * @param {Array<Dict>} entries - center entries
 * @param {?{[key: string]: boolean}} expanded - per-app expand overrides
 * @returns {Array<Dict>} groups of {app, count, newest, entries, collapsed, visible, hidden}
 */
function groupView(entries, expanded) {
  var overrides = expanded || {}
  /** @type {Array<Dict>} */
  var groups = []
  /** @type {{[key: string]: number}} */
  var index = {}
  var rows = Array.isArray(entries) ? entries : []
  for (var i = 0; i < rows.length; i++) {
    var entry = rows[i] || {}
    var app = String(entry.app || "unknown")
    if (index[app] === undefined) {
      index[app] = groups.length
      groups.push({ app: app, count: 0, newest: Number(entry.timestamp) || 0, entries: [] })
    }
    var group = groups[index[app]]
    group.entries.push(entry)
    group.count++
  }
  for (var k = 0; k < groups.length; k++) {
    var gr = groups[k]
    var collapsed = overrides[gr.app] === undefined ? gr.count >= COLLAPSE_AT : !overrides[gr.app]
    gr.collapsed = collapsed
    gr.visible = collapsed ? gr.entries.slice(0, 1) : gr.entries.slice()
    gr.hidden = gr.count - gr.visible.length
  }
  return groups
}

/**
 * Flattens groups into center rows: a "group" header, its visible "entry"
 * rows, then a "more" row when some entries are hidden.
 * @param {Array<Dict>} groups - groupView output
 * @returns {Array<Dict>} rows tagged by kind
 */
function flattenGroups(groups) {
  var out = []
  var list = Array.isArray(groups) ? groups : []
  for (var i = 0; i < list.length; i++) {
    var g = list[i]
    out.push({ kind: "group", app: g.app, count: g.count, collapsed: g.collapsed })
    for (var j = 0; j < g.visible.length; j++)
      out.push({ kind: "entry", app: g.app, entry: g.visible[j] })
    if (g.hidden > 0) out.push({ kind: "more", app: g.app, hidden: g.hidden })
  }
  return out
}

/**
 * Badge text for a count: "" for zero, "9+" above nine.
 * @param {number} count - how many to show
 * @returns {string} the label
 */
function badgeLabel(count) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  if (n === 0) return ""
  return n > 9 ? "9+" : String(n)
}

/**
 * The bell's tooltip, e.g. "3 notifications · 1 critical · DND off".
 * @param {number} count - inbox entries
 * @param {number} critical - critical entries
 * @param {boolean} dnd - Do Not Disturb is on
 * @param {boolean} quiet - quiet hours are active (wins over dnd)
 * @returns {string} the tooltip text
 */
function tooltipText(count, critical, dnd, quiet) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  var c = Math.max(0, Math.floor(Number(critical) || 0))
  var noun = n === 1 ? "notification" : "notifications"
  var state = quiet ? "Quiet hours" : dnd ? "DND on" : "DND off"
  return n + " " + noun + (c > 0 ? " · " + c + " critical" : "") + " · " + state
}

/**
 * Critical entries colour the bell red and show their own count, even under
 * DND; otherwise the badge counts everything, and DND hides it.
 * @param {number} total - inbox entries
 * @param {number} critical - critical entries
 * @param {boolean} dnd - whether DND (or quiet hours) silences the badge
 * @returns {Dict} {label, tone}, tone being "critical", "normal" or "none"
 */
function badgeState(total, critical, dnd) {
  var c = Math.max(0, Math.floor(Number(critical) || 0))
  if (c > 0) return { label: badgeLabel(c), tone: "critical" }
  if (dnd || !(Number(total) > 0)) return { label: "", tone: "none" }
  return { label: badgeLabel(total), tone: "normal" }
}

/**
 * Critical first, then newest first. Returns a new array.
 * @param {Array<Dict>} entries - inbox entries
 * @returns {Array<Dict>} the sorted copy
 */
function sortForCenter(entries) {
  var rows = (Array.isArray(entries) ? entries : []).slice()
  rows.sort(function (a, b) {
    var ca = Number(a.urgency) === CRITICAL ? 1 : 0
    var cb = Number(b.urgency) === CRITICAL ? 1 : 0
    if (ca !== cb) return cb - ca
    return newestFirst(a, b)
  })
  return rows
}

/**
 * Stable identity for a center row, so the keyboard cursor follows its item
 * when arrivals shift the list.
 * @param {?Dict} row - a flattenGroups row
 * @returns {string} "e:<fileName>", "m:<app>" or "g:<app>"; "" for no row
 */
function rowKey(row) {
  if (!row) return ""
  if (row.kind === "entry") return "e:" + (row.entry ? row.entry.fileName : "")
  return (row.kind === "more" ? "m:" : "g:") + row.app
}

/**
 * Position of the row with a given rowKey.
 * @param {Array<Dict>} rows - flattenGroups rows
 * @param {string} key - a rowKey value
 * @returns {number} the index, or -1
 */
function indexOfKey(rows, key) {
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) if (rowKey(list[i]) === key) return i
  return -1
}

/**
 * The bell glyph: nf-md-bell (U+F009A), or nf-md-bell_off (U+F009B) when
 * silenced.
 * @param {boolean} silenced - whether DND or quiet hours are on
 * @returns {string} the bell_off glyph when silenced, else the bell
 */
function bellGlyph(silenced) {
  return silenced ? "󰂛" : "󰂚"
}

/**
 * Whether clearing this many entries asks for confirmation first (more than
 * CONFIRM_CLEAR_ABOVE).
 * @param {number} count - inbox entries
 * @returns {boolean} true to confirm
 */
function needsClearConfirm(count) {
  return (Number(count) || 0) > CONFIRM_CLEAR_ABOVE
}

/**
 * The end time of an "HH:MM-HH:MM" quiet-hours window.
 * @param {?string} window - the quiet-hours window
 * @returns {string} "HH:MM", or "" when the window is malformed
 */
function quietUntil(window) {
  var match = /^(\d{2}):(\d{2})-(\d{2}):(\d{2})$/.exec(String(window || "").trim())
  return match ? match[3] + ":" + match[4] : ""
}

/**
 * Compact age of a timestamp: "now" under a minute, then whole minutes, hours
 * or days ("5m", "3h", "2d").
 * @param {number} timestamp - time in ms
 * @param {number} now - current time in ms
 * @returns {string} the age label
 */
function relativeTime(timestamp, now) {
  var seconds = Math.max(0, Math.floor(((Number(now) || 0) - (Number(timestamp) || 0)) / 1000))
  if (seconds < 60) return "now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  return Math.floor(hours / 24) + "d"
}

/**
 * What Delete does on a center row: a "+N more" row expands its group (so
 * hidden entries are never deleted unseen), an entry is dismissed, a group
 * header, or any row with Shift, clears the whole app group.
 * @param {?{kind: string}} row - the row under the cursor
 * @param {boolean} wholeGroup - Shift was held
 * @returns {string} "expand", "dismiss", "group", or "" for no row
 */
function dismissAction(row, wholeGroup) {
  if (!row) return ""
  if (wholeGroup || row.kind === "group") return "group"
  if (row.kind === "more") return "expand"
  return "dismiss"
}

/**
 * Merges the rows read from disk at startup with rows already in the model:
 * disk rows cleared or removed while the read ran are dropped, model rows not
 * on disk (arrived during the read) are kept; newest first.
 * @param {Array<{fileName: string, timestamp: number}>} diskRows - rows parsed from the inbox files
 * @param {Array<{fileName: string, timestamp: number}>} liveRows - rows in the model when the read finished
 * @param {{[key: string]: boolean}} removed - file names removed while the read ran
 * @param {boolean} cleared - the inbox was cleared while the read ran
 * @returns {Array<{fileName: string, timestamp: number}>} the merged rows
 */
function mergeLoaded(diskRows, liveRows, removed, cleared) {
  /** @type {{[key: string]: boolean}} */
  var seen = {}
  var out = []
  for (var i = 0; i < (diskRows || []).length; i++) {
    var d = diskRows[i]
    seen[d.fileName] = true
    if (!cleared && !(removed || {})[d.fileName]) out.push(d)
  }
  for (var j = 0; j < (liveRows || []).length; j++)
    if (!seen[liveRows[j].fileName]) out.push(liveRows[j])
  return out.sort(function (a, b) {
    return (b.timestamp || 0) - (a.timestamp || 0)
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    dismissAction: dismissAction,
    mergeLoaded: mergeLoaded,
    MAX_ITEMS: MAX_ITEMS,
    MAX_AGE_MS: MAX_AGE_MS,
    COLLAPSE_AT: COLLAPSE_AT,
    CONFIRM_CLEAR_ABOVE: CONFIRM_CLEAR_ABOVE,
    SWIPE_DISTANCE_RATIO: SWIPE_DISTANCE_RATIO,
    SWIPE_FLICK_VELOCITY: SWIPE_FLICK_VELOCITY,
    CLICK_SUPPRESS_PX: CLICK_SUPPRESS_PX,
    shouldStore: shouldStore,
    removesFromInbox: removesFromInbox,
    upsertOrder: upsertOrder,
    pruneInbox: pruneInbox,
    swipeOutcome: swipeOutcome,
    suppressesClick: suppressesClick,
    groupView: groupView,
    flattenGroups: flattenGroups,
    badgeLabel: badgeLabel,
    tooltipText: tooltipText,
    badgeState: badgeState,
    sortForCenter: sortForCenter,
    rowKey: rowKey,
    indexOfKey: indexOfKey,
    bellGlyph: bellGlyph,
    needsClearConfirm: needsClearConfirm,
    quietUntil: quietUntil,
    relativeTime: relativeTime
  }
}
