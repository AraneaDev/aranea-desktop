// Pure rules for the notification inbox, toast stack and center. No QML, no
// I/O: Service.qml, Inbox.qml and Panel.qml call these, and
// tests/notifications.test.sh runs them under Node.

var MAX_ITEMS = 100
var MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000
var MAX_VISIBLE_TOASTS = 3
var COLLAPSE_AT = 3
var CONFIRM_CLEAR_ABOVE = 20
var SWIPE_DISTANCE_RATIO = 0.35
var SWIPE_FLICK_VELOCITY = 900
var CLICK_SUPPRESS_PX = 4

var LOW = 0
var CRITICAL = 2

// Whether a notification earns an inbox entry. `transient` is the freedesktop
// "popup only, don't store" hint. Low-urgency CLI/omarchy-action toasts are
// feedback for something the user just did (volume, "Theme changed").
function shouldStore(ephemeralApp, urgency, transient) {
  if (transient) return false
  return !(ephemeralApp && Number(urgency) === LOW)
}

// A toast that simply ran out of time was missed, so it waits in the center.
// Any deliberate action on it means the user has seen it.
function removesFromInbox(reason) {
  return String(reason) !== "expire"
}

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

function newestFirst(a, b) {
  return (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0)
}

// Entries on screen are never pruned: their toast still owns the file.
function pruneInbox(entries, now) {
  var rows = (Array.isArray(entries) ? entries : []).filter(function(e) { return !!e })
  var keep = []
  var drop = []
  var cutoff = Number(now) - MAX_AGE_MS
  for (var i = 0; i < rows.length; i++) {
    var e = rows[i]
    var aged = (Number(e.timestamp) || 0) < cutoff
    if (aged && !e.onScreen && Number(e.urgency) !== CRITICAL) drop.push(e)
    else keep.push(e)
  }
  keep.sort(newestFirst)

  function dropOldest(predicate) {
    for (var j = keep.length - 1; j >= 0 && keep.length > MAX_ITEMS; j--) {
      if (!keep[j].onScreen && predicate(keep[j])) drop.push(keep.splice(j, 1)[0])
    }
  }
  dropOldest(function(x) { return Number(x.urgency) !== CRITICAL })
  dropOldest(function() { return true })
  return { keep: keep, drop: drop }
}

// rows are newest-first (index 0 is the top of the stack).
function stackSplit(rows, maxVisible) {
  var list = Array.isArray(rows) ? rows : []
  var max = Math.max(0, Number(maxVisible) || 0)
  var chosen = []
  for (var i = 0; i < list.length && chosen.length < max; i++) {
    if (list[i] && Number(list[i].urgency) === CRITICAL) chosen.push(i)
  }
  for (var j = 0; j < list.length && chosen.length < max; j++) {
    if (chosen.indexOf(j) < 0) chosen.push(j)
  }
  chosen.sort(function(a, b) { return a - b })
  return { visible: chosen, overflow: Math.max(0, list.length - chosen.length) }
}

function swipeOutcome(dx, width, velocity) {
  var d = Number(dx) || 0
  if (d <= 0) return "restore"
  if (d >= (Number(width) || 0) * SWIPE_DISTANCE_RATIO) return "dismiss"
  if ((Number(velocity) || 0) >= SWIPE_FLICK_VELOCITY) return "dismiss"
  return "restore"
}

function suppressesClick(distance) {
  return Math.abs(Number(distance) || 0) > CLICK_SUPPRESS_PX
}

// entries newest-first; expanded maps app -> true/false for user overrides.
function groupView(entries, expanded) {
  var overrides = expanded || {}
  var groups = []
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

function flattenGroups(groups) {
  var out = []
  var list = Array.isArray(groups) ? groups : []
  for (var i = 0; i < list.length; i++) {
    var g = list[i]
    out.push({ kind: "group", app: g.app, count: g.count, collapsed: g.collapsed })
    for (var j = 0; j < g.visible.length; j++) out.push({ kind: "entry", app: g.app, entry: g.visible[j] })
    if (g.hidden > 0) out.push({ kind: "more", app: g.app, hidden: g.hidden })
  }
  return out
}

function badgeLabel(count) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  if (n === 0) return ""
  return n > 9 ? "9+" : String(n)
}

function tooltipText(count, dnd, quiet) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  var noun = n === 1 ? "notification" : "notifications"
  var state = quiet ? "Quiet hours" : (dnd ? "DND on" : "DND off")
  return n + " " + noun + " · " + state
}

// nf-md-bell (U+F009A) and nf-md-bell_off (U+F009B), as surrogate pairs so
// the file stays ASCII.
function bellGlyph(silenced) {
  return silenced ? "󰂛" : "󰂚"
}

function needsClearConfirm(count) {
  return (Number(count) || 0) > CONFIRM_CLEAR_ABOVE
}

function quietUntil(window) {
  var match = /^(\d{2}):(\d{2})-(\d{2}):(\d{2})$/.exec(String(window || "").trim())
  return match ? match[3] + ":" + match[4] : ""
}

function relativeTime(timestamp, now) {
  var seconds = Math.max(0, Math.floor(((Number(now) || 0) - (Number(timestamp) || 0)) / 1000))
  if (seconds < 60) return "now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  return Math.floor(hours / 24) + "d"
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_ITEMS: MAX_ITEMS,
    MAX_AGE_MS: MAX_AGE_MS,
    MAX_VISIBLE_TOASTS: MAX_VISIBLE_TOASTS,
    COLLAPSE_AT: COLLAPSE_AT,
    CONFIRM_CLEAR_ABOVE: CONFIRM_CLEAR_ABOVE,
    SWIPE_DISTANCE_RATIO: SWIPE_DISTANCE_RATIO,
    SWIPE_FLICK_VELOCITY: SWIPE_FLICK_VELOCITY,
    CLICK_SUPPRESS_PX: CLICK_SUPPRESS_PX,
    shouldStore: shouldStore,
    removesFromInbox: removesFromInbox,
    upsertOrder: upsertOrder,
    pruneInbox: pruneInbox,
    stackSplit: stackSplit,
    swipeOutcome: swipeOutcome,
    suppressesClick: suppressesClick,
    groupView: groupView,
    flattenGroups: flattenGroups,
    badgeLabel: badgeLabel,
    tooltipText: tooltipText,
    bellGlyph: bellGlyph,
    needsClearConfirm: needsClearConfirm,
    quietUntil: quietUntil,
    relativeTime: relativeTime
  }
}
