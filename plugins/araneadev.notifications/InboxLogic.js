// Pure rules for the notification inbox, toast stack and center. No QML, no
// I/O: Service.qml, Inbox.qml and Panel.qml call these, and
// tests/notifications.test.sh runs them under Node. followRemoval's
// afterRemoval call runs a generated copy of araneadev.shared/CursorLogic.js
// (tools/js-facade-generator.mjs), since there is no cross-.js-file import
// mechanism usable from both QML and Node in this codebase (as
// araneadev.network/NetworkLogic.js's own copy, for the same reason).

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
    if (aged && Number(e.urgency) !== CRITICAL) drop.push(e)
    else keep.push(e)
  }
  keep.sort(newestFirst)

  /**
   * Moves the oldest entries that match the predicate from keep to
   * drop until keep fits MAX_ITEMS.
   * @param {(entry: Dict) => boolean} predicate - which entries may go
   */
  function dropOldest(predicate) {
    for (var j = keep.length - 1; j >= 0 && keep.length > MAX_ITEMS; j--) {
      if (predicate(keep[j])) drop.push(keep.splice(j, 1)[0])
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

/** The fields of an inbox row, as Inbox.qml stores them in its ListModel. */
var ROW_FIELDS = [
  "fileName",
  "id",
  "originalId",
  "app",
  "appIcon",
  "summary",
  "body",
  "image",
  "glyph",
  "execArgv",
  "urgency",
  "expireTimeout",
  "timestamp",
  "sourceKey"
]

/**
 * Plain copies of inbox rows (ROW_FIELDS only). Inbox.qml publishes these as
 * its snapshot, so bindings never hold live ListModel objects: a binding that
 * hands those to a view re-enters itself through their change notifications
 * (the `rows` binding loop).
 * @param {Array<Dict>} rows - inbox rows, live or plain
 * @returns {Array<Dict>} one new plain object per row, in order
 */
function snapshotOf(rows) {
  var list = Array.isArray(rows) ? rows : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var row = list[i] || {}
    /** @type {Dict} */
    var copy = {}
    for (var k = 0; k < ROW_FIELDS.length; k++) copy[ROW_FIELDS[k]] = row[ROW_FIELDS[k]]
    out.push(copy)
  }
  return out
}

/**
 * The center's rows for an inbox snapshot: sorted critical first, grouped by
 * app and flattened into group, entry and "more" rows.
 * @param {Array<Dict>} entries - the inbox snapshot (snapshotOf)
 * @param {?{[key: string]: boolean}} expanded - per-app expand overrides
 * @returns {Array<Dict>} flattenGroups rows
 */
function centerRows(entries, expanded) {
  return flattenGroups(groupView(sortForCenter(entries), expanded))
}

/**
 * How many entries are critical (urgency 2).
 * @param {Array<Dict>} entries - the inbox snapshot (snapshotOf)
 * @returns {number} the critical count
 */
function criticalCount(entries) {
  var list = Array.isArray(entries) ? entries : []
  var n = 0
  for (var i = 0; i < list.length; i++) if (list[i] && Number(list[i].urgency) === CRITICAL) n++
  return n
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
  return String.fromCodePoint(silenced ? 0xf009b : 0xf009a)
}

/**
 * The center list's height: its content, capped so the header above the
 * list and the footer below it (the Clear row and the key hint) still fit
 * inside the card's content area.
 * @param {number} contentHeight - the list's full content height
 * @param {number} innerMax - the card's largest content height (inside padding and border)
 * @param {number} slotTop - the height above the list
 * @param {number} footerHeight - the height below the list
 * @returns {number} the list height, never below 0
 */
function listHeight(contentHeight, innerMax, slotTop, footerHeight) {
  var room = (Number(innerMax) || 0) - (Number(slotTop) || 0) - (Number(footerHeight) || 0)
  return Math.max(0, Math.min(Number(contentHeight) || 0, room))
}

/**
 * The center header's caption: the quiet-hours text while quiet hours are
 * active and the window parsed, else "N unread", or "Nothing new" at 0.
 * @param {number} count - inbox entries
 * @param {boolean} quiet - whether quiet hours are active
 * @param {string} quietUntilText - the window's end ("HH:MM", quietUntil), "" when malformed
 * @returns {string} the caption
 */
function centerCaption(count, quiet, quietUntilText) {
  if (quiet && quietUntilText) return "Quiet until " + quietUntilText
  var n = Number(count) || 0
  return n > 0 ? n + " unread" : "Nothing new"
}

/**
 * The center's key hint line, by state (the network dropdown's keyHint
 * pattern): with entries, every row key; with none, only moving (the DND
 * switch is still a stop) and Tab.
 * @param {number} count - inbox entries
 * @returns {string} the hint
 */
function centerKeyHint(count) {
  if ((Number(count) || 0) > 0) return "↑↓ move · x dismiss · ⇧del group · tab next"
  return "↑↓ move · tab next"
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
 * The keyboard cursor's stops in the center, top to bottom: the "Do not
 * disturb" switch (key "dnd"), every entry and "+N more" row (keyed by
 * rowKey; group headers are passed over, as before), then the "Clear all"
 * pill (key "clear") while it shows. Row keys start with "e:", "m:" or
 * "g:", so they never collide with "dnd" or "clear".
 * @param {Array<Dict>} rows - center rows (flattenGroups)
 * @param {boolean} clearVisible - whether the Clear pill shows
 * @returns {Array<{key: string, section: string, index: number}>} the stops; section is "dnd", "rows" or "clear", index the row's position (-1 off the list)
 */
function centerStops(rows, clearVisible) {
  var stops = [{ key: "dnd", section: "dnd", index: -1 }]
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    if (row && (row.kind === "entry" || row.kind === "more"))
      stops.push({ key: rowKey(row), section: "rows", index: i })
  }
  if (clearVisible) stops.push({ key: "clear", section: "clear", index: -1 })
  return stops
}

/**
 * Position of the stop with a given key.
 * @param {Array<{key: string}>} stops - centerStops output
 * @param {string} key - the cursor's key, or ""
 * @returns {number} the index, or -1 when key is "" or gone
 */
function stopIndex(stops, key) {
  if (!key || !Array.isArray(stops)) return -1
  for (var i = 0; i < stops.length; i++) if (stops[i].key === key) return i
  return -1
}

/**
 * Where the first navigation key shows the cursor: the stop at `fallback`
 * (where a vanished cursor last was) clamped into the stops, else the first
 * row, else the first stop (the DND switch).
 * @param {Array<{section: string}>} stops - centerStops output
 * @param {number} fallback - the cursor's last stop, or -1 for none
 * @returns {number} the stop index, or -1 with no stops
 */
function revealStop(stops, fallback) {
  var list = Array.isArray(stops) ? stops : []
  if (list.length === 0) return -1
  if (typeof fallback === "number" && fallback >= 0)
    return Math.min(list.length - 1, Math.floor(fallback))
  for (var i = 0; i < list.length; i++) if (list[i].section === "rows") return i
  return 0
}

/**
 * Where the cursor stands after its stops changed: it keeps its key and
 * visibility while that key is still a stop; otherwise the key is dropped
 * and the cursor hides, so the same key coming back later never shows the
 * outline again without a key press.
 * @param {Array<{key: string}>} stops - centerStops output
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} shown - whether the keyboard cursor shows
 * @returns {{key: string, shown: boolean}} the cursor's key and visibility
 */
function followStop(stops, key, shown) {
  if (stopIndex(stops, key) >= 0) return { key: key, shown: !!shown }
  return { key: "", shown: false }
}

/* @aranea-facade-start: plugins/araneadev.shared/CursorLogic.js */
// Shared keyboard-cursor safety rules, moved out of the Network plugin so
// araneadev.vpn can reuse them: a cursor follows the row key it was put on
// (never its position), a lost or evacuated key is refused rather than
// retargeted, and a pointer action only ever lands on the row it names. No
// QML, no I/O; tests/js/cursor-logic.test.js runs this under Node. The
// keyed helpers (keyIndex, keyStep, keyedMove, keyedPress, keyedOutline)
// are Health's and Workspaces' dropdown cursors, keyed by a host function.

/**
 * The index a list cursor should sit on after its rows changed: the row
 * whose `key` equals `key` wherever it moved, else `fallback` clamped into
 * the list. Lets a cursor follow its network or profile across a re-sort
 * instead of staying on a position that now holds another row.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the new rows
 * @param {string|null|undefined} key - the key the cursor was on
 * @param {number} fallback - the index to clamp when the key is gone
 * @returns {number} the index, or -1 when there are no rows
 */
function reselectIndex(rows, key, fallback) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0) return -1
  if (typeof key === "string") {
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (row && row.key === key) return i
    }
  }
  var f = Math.floor(Number(fallback)) || 0
  return Math.max(0, Math.min(list.length - 1, f))
}

/**
 * Where a list cursor goes after its rows changed: onto the row whose `key`
 * equals `key`, wherever it moved. When that row is gone (or there was no
 * key), the index is clamped into the list but the key is dropped, so the
 * row that slid into its place is never adopted as the user's choice.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the new rows
 * @param {string|null|undefined} key - the key the cursor was deliberately put on, or ""
 * @param {number} index - the cursor's index before the change
 * @returns {{index: number, key: string, confirmed: boolean}} the new index (-1 with no rows), the key it keeps ("" when lost) and whether the cursor's row is the chosen one
 */
function followCursor(rows, key, index) {
  var list = Array.isArray(rows) ? rows : []
  var chosen = typeof key === "string" && key !== "" ? key : null
  var next = reselectIndex(list, chosen, index)
  var row = next >= 0 ? list[next] : null
  var confirmed = chosen !== null && !!row && row.key === chosen
  return { index: next, key: confirmed ? chosen : "", confirmed: confirmed }
}

/**
 * Whether the cursor's row is still the one the user chose: `key` isn't
 * empty (a hidden SSID or no choice never is) and the row at `index` has it.
 * Keyboard actions refuse otherwise.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the section's rows
 * @param {string|null|undefined} key - the key the cursor was put on
 * @param {number} index - the cursor's index
 * @returns {boolean} true when the keyboard may act on that row
 */
function cursorConfirmed(rows, key, index) {
  if (!Array.isArray(rows) || typeof key !== "string" || key === "") return false
  var row = rows[index]
  return !!row && row.key === key
}

/**
 * What Enter or `x` does: nothing before any cursor exists, only reveal a
 * cursor the keyboard isn't showing (one the pointer placed), else act.
 * @param {boolean} cursorActive - whether a cursor has been placed
 * @param {boolean} keyboardCursor - whether its outline is showing
 * @returns {string} `ignore`, `reveal` or `act`
 */
function pressIntent(cursorActive, keyboardCursor) {
  if (!cursorActive) return "ignore"
  return keyboardCursor ? "act" : "reveal"
}

/**
 * Hands back the array last stored under `name` when `next` has the same
 * content, so a view's Repeater keeps its delegates (and nothing slides
 * under a still pointer) on a refresh that changed nothing. Stores `next`
 * otherwise. `cache` is mutated in place.
 * @param {Record<string, any>|null|undefined} cache - the arrays kept so far, by name
 * @param {string} name - which row array this is
 * @param {Array<any>} next - the freshly built rows
 * @returns {Array<any>} the kept array or `next`
 */
function keepRows(cache, name, next) {
  if (!cache || typeof cache !== "object") return next
  var prev = cache[name]
  if (prev !== undefined && JSON.stringify(prev) === JSON.stringify(next)) return prev
  cache[name] = next
  return next
}

/**
 * Whether row `index` still carries `key`, so a pointer action reported for
 * one row never lands on another.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the section's rows
 * @param {number} index - the row the action names
 * @param {string|undefined} key - the key the view saw at that row
 * @returns {boolean} true when the row is the one the user clicked
 */
function rowKeyMatches(rows, index, key) {
  if (!Array.isArray(rows) || typeof key !== "string") return false
  var row = rows[index]
  return !!row && row.key === key
}

/**
 * Where the keyboard cursor goes after a row left the list (Bluetooth
 * Forget, Notifications Delete): the stop now at `lastIndex` (the row that
 * slid into the removed one's place), clamped to the last stop when it was
 * the bottom one. If `removedKey` still names a stop in `stops` (this read
 * hasn't caught up with the removal yet), that stop is returned as is
 * instead, since nothing has actually moved.
 * @param {Array<{key: string}|null|undefined>|undefined} stops - the stops, read after the removal
 * @param {string|null|undefined} removedKey - the key of the row that was removed
 * @param {number} lastIndex - the removed row's index before it left
 * @returns {{index: number, key: string}} the stop to keep the cursor on, or {index: -1, key: ""} with none left
 */
function afterRemoval(stops, removedKey, lastIndex) {
  var list = Array.isArray(stops) ? stops : []
  if (list.length === 0) return { index: -1, key: "" }
  if (typeof removedKey === "string" && removedKey !== "") {
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (row && row.key === removedKey) return { index: i, key: removedKey }
    }
  }
  var idx = Math.max(0, Math.min(list.length - 1, Math.floor(Number(lastIndex)) || 0))
  var stop = list[idx]
  return { index: idx, key: stop && typeof stop.key === "string" ? stop.key : "" }
}

/**
 * Position of the row whose `keyOf(row)` is `key`. The keyed-cursor helpers
 * below (keyStep, keyedMove, keyedPress, keyedOutline) follow a cursor by
 * the row key a host's `keyOf` gives (Health's problemKey, Workspaces'
 * workspaceKey), never by position.
 * @param {*} rows - the dropdown rows (anything but an array counts as none)
 * @param {string} key - the row key, or ""
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {number} its index, or -1 (always for an empty key)
 */
function keyIndex(rows, key, keyOf) {
  if (!key) return -1
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) if (keyOf(list[i]) === key) return i
  return -1
}

/**
 * Key of the row `delta` steps from the row with this key, wrapping; the
 * first (delta > 0) or last row when the key is empty or gone.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the current cursor key, or ""
 * @param {number} delta - rows to move (sign matters)
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {string} the new cursor key, or "" when there are no rows
 */
function keyStep(rows, key, delta, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0) return ""
  var i = keyIndex(list, key, keyOf)
  if (i < 0) return keyOf(list[delta < 0 ? list.length - 1 : 0])
  return keyOf(list[(i + delta + list.length) % list.length])
}

/**
 * The cursor after an up or down key. Dropdowns are reveal-first: the first
 * key after opening or after pointer use (keyboard false) only reveals the
 * cursor, on the row the pointer left it on, else the first (dy > 0) or
 * last row. Later keys move it, wrapping.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {number} dy - rows to move (sign matters); 0 does nothing
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {{key: string, keyboard: boolean}} the new cursor key and mode
 */
function keyedMove(rows, key, keyboard, dy, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0 || !dy) return { key: key, keyboard: keyboard }
  if (!keyboard)
    return {
      key: keyIndex(list, key, keyOf) >= 0 ? key : keyStep(list, "", dy, keyOf),
      keyboard: true
    }
  return { key: keyStep(list, key, dy, keyOf), keyboard: true }
}

/**
 * What Enter or Space does on a keyed list, by pressIntent: nothing without
 * a cursor on a shown row, only reveal one the keyboard is not showing,
 * else hand back the cursor's row to act on.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {{keyboard: boolean, row: ?object}} the new mode and the row to act on, or null
 */
function keyedPress(rows, key, keyboard, keyOf) {
  var i = keyIndex(rows, key, keyOf)
  var intent = pressIntent(i >= 0, keyboard)
  if (intent === "ignore") return { keyboard: keyboard, row: null }
  return { keyboard: true, row: intent === "act" ? rows[i] : null }
}

/**
 * The row the mint outline is drawn on: the cursor's, only while the
 * keyboard drives it.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {number} the row index, or -1 for no outline
 */
function keyedOutline(rows, key, keyboard, keyOf) {
  return keyboard ? keyIndex(rows, key, keyOf) : -1
}

if (typeof module !== "undefined")
  module.exports = {
    reselectIndex: reselectIndex,
    followCursor: followCursor,
    cursorConfirmed: cursorConfirmed,
    pressIntent: pressIntent,
    keepRows: keepRows,
    rowKeyMatches: rowKeyMatches,
    afterRemoval: afterRemoval,
    keyIndex: keyIndex,
    keyStep: keyStep,
    keyedMove: keyedMove,
    keyedPress: keyedPress,
    keyedOutline: keyedOutline
  }
/* @aranea-facade-end */

/**
 * Where the keyboard cursor goes after a stop change (centerStops
 * recomputed, or the cursor's key itself changed): Panel.qml's single call
 * from onCursorStopChanged. When `pendingKey` is armed for a keyboard
 * removal (Panel.qml's deleteCursor, set to the cursor's own key before the
 * row leaves) and that key just vanished from `stops`, the shared
 * afterRemoval (CursorLogic, generated above) lands the cursor on the
 * neighbour and keeps it shown; `pendingKey` is cleared.
 *
 * Otherwise this mirrors followStop: a vanished key hides the cursor, a
 * surviving one keeps `shown` exactly as given, so a hover-placed cursor,
 * or one merely carried to a new index by a re-sort, is never flipped by
 * this alone. Either way, an armed `pendingKey` is dropped the moment the
 * cursor's own key survives a stop change, so a Delete that never actually
 * removed anything (an arrival landing first, say) can't fire afterRemoval
 * on a later, unrelated vanish.
 * @param {Array<{key: string}>} stops - centerStops output, read after the change
 * @param {string} pendingKey - the key a keyboard Delete armed, or "" when none
 * @param {string} cursorKey - the cursor's key before this change
 * @param {number} lastStop - the stop the cursor was last on (Panel.qml's lastStop)
 * @param {boolean} shown - whether the keyboard cursor currently shows
 * @returns {{key: string, shown: boolean, pendingKey: string}} the cursor's next key, visibility and pending-removal key
 */
function followRemoval(stops, pendingKey, cursorKey, lastStop, shown) {
  var survived = stopIndex(stops, cursorKey) >= 0
  if (!survived && pendingKey && pendingKey === cursorKey) {
    var next = afterRemoval(stops, pendingKey, lastStop)
    return { key: next.key, shown: next.key !== "", pendingKey: "" }
  }
  var result = followStop(stops, cursorKey, shown)
  return { key: result.key, shown: result.shown, pendingKey: survived ? "" : pendingKey }
}

/**
 * The stop one step (`delta`) from `at`, held at both ends (no wrap, as in
 * the other Aranea dropdowns).
 * @param {Array<*>} stops - centerStops output
 * @param {number} at - the cursor's stop
 * @param {number} delta - -1 up, +1 down
 * @returns {number} the next stop index, or -1 with no stops
 */
function moveStop(stops, at, delta) {
  var n = Array.isArray(stops) ? stops.length : 0
  if (n === 0) return -1
  var from = Math.max(0, Math.min(n - 1, Math.floor(Number(at)) || 0))
  var step = delta > 0 ? 1 : delta < 0 ? -1 : 0
  return Math.max(0, Math.min(n - 1, from + step))
}

/**
 * A pending Do Not Disturb change: `target` is the state sent to the
 * service and not yet echoed back (null when idle), `queued` the state
 * clicked while waiting (null for none).
 * @typedef {{target: ?boolean, queued: ?boolean}} DndPending
 */

/**
 * The idle DND state: nothing sent, nothing queued.
 * @returns {DndPending} a fresh idle state
 */
function dndIdle() {
  return { target: null, queued: null }
}

/**
 * A click on the DND switch. Idle, it sends the opposite of the service's
 * state at once. While a change is in flight it only queues the opposite of
 * what the switch shows; the last click wins, and a click back to the
 * in-flight state cancels the queue.
 * @param {?DndPending} state - the pending state (null counts as idle)
 * @param {boolean} actual - the service's doNotDisturb
 * @returns {{state: DndPending, send: ?boolean}} the next state and the value to send now (null: send nothing)
 */
function dndClick(state, actual) {
  var s = state || dndIdle()
  if (s.target === null || s.target === undefined) {
    var target = !actual
    return { state: { target: target, queued: null }, send: target }
  }
  var shown = s.queued !== null && s.queued !== undefined ? s.queued : s.target
  var next = !shown
  return { state: { target: s.target, queued: next === s.target ? null : next }, send: null }
}

/**
 * The service's doNotDisturb changed (or was read back). When it reaches the
 * in-flight target, a queued state that differs is sent next; otherwise the
 * switch goes idle. A value other than the target keeps waiting (a timeout
 * calls dndIdle).
 * @param {?DndPending} state - the pending state
 * @param {boolean} actual - the service's doNotDisturb now
 * @returns {{state: DndPending, send: ?boolean}} the next state and the value to send now (null: send nothing)
 */
function dndEcho(state, actual) {
  var s = state || dndIdle()
  if (s.target === null || s.target === undefined || s.target !== !!actual)
    return { state: s, send: null }
  if (s.queued !== null && s.queued !== undefined && s.queued !== !!actual)
    return { state: { target: s.queued, queued: null }, send: s.queued }
  return { state: dndIdle(), send: null }
}

/**
 * What the DND switch shows: the queued state, else the in-flight one, else
 * the service's; busy (pulsing) while a change is in flight.
 * @param {?DndPending} state - the pending state
 * @param {boolean} actual - the service's doNotDisturb
 * @returns {{on: boolean, busy: boolean}} the header view's dnd part
 */
function dndView(state, actual) {
  var s = state || dndIdle()
  var busy = s.target !== null && s.target !== undefined
  var on = s.queued !== null && s.queued !== undefined ? s.queued : busy ? s.target : !!actual
  return { on: !!on, busy: busy }
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
    centerStops: centerStops,
    stopIndex: stopIndex,
    followStop: followStop,
    followRemoval: followRemoval,
    revealStop: revealStop,
    moveStop: moveStop,
    dndIdle: dndIdle,
    dndClick: dndClick,
    dndEcho: dndEcho,
    dndView: dndView,
    mergeLoaded: mergeLoaded,
    MAX_ITEMS: MAX_ITEMS,
    MAX_AGE_MS: MAX_AGE_MS,
    COLLAPSE_AT: COLLAPSE_AT,
    CONFIRM_CLEAR_ABOVE: CONFIRM_CLEAR_ABOVE,
    SWIPE_DISTANCE_RATIO: SWIPE_DISTANCE_RATIO,
    SWIPE_FLICK_VELOCITY: SWIPE_FLICK_VELOCITY,
    CLICK_SUPPRESS_PX: CLICK_SUPPRESS_PX,
    shouldStore: shouldStore,
    pruneInbox: pruneInbox,
    swipeOutcome: swipeOutcome,
    suppressesClick: suppressesClick,
    groupView: groupView,
    flattenGroups: flattenGroups,
    badgeLabel: badgeLabel,
    tooltipText: tooltipText,
    badgeState: badgeState,
    sortForCenter: sortForCenter,
    ROW_FIELDS: ROW_FIELDS,
    snapshotOf: snapshotOf,
    centerRows: centerRows,
    criticalCount: criticalCount,
    rowKey: rowKey,
    indexOfKey: indexOfKey,
    bellGlyph: bellGlyph,
    centerCaption: centerCaption,
    centerKeyHint: centerKeyHint,
    listHeight: listHeight,
    needsClearConfirm: needsClearConfirm,
    quietUntil: quietUntil,
    relativeTime: relativeTime
  }
}
