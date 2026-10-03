// Pure rules for the Aranea Bluetooth dropdown (Panel.qml): the glyph for a
// device type, the signal level behind an available device's node glow,
// reading RSSI from BlueZ's managed objects, the power switch's pending
// state, the per-device action queue and where the keyboard cursor goes
// after a keyboard Forget. No QML, no I/O; tests/js/bluetooth-logic.test.js
// runs this under Node. followForget's afterRemoval and Panel.qml's keyed
// rowKeyMatches run a generated copy of araneadev.shared/CursorLogic.js
// (tools/js-facade-generator.mjs), since there is no cross-.js-file import
// usable from both QML and Node in this codebase.

/** @type {Record<string, number>} */
var typeGlyphs = {
  "audio-headset": 0xf02cb,
  "audio-headphones": 0xf02cb,
  "audio-card": 0xf04c3,
  "input-mouse": 0xf037d,
  "input-keyboard": 0xf030c,
  "input-gaming": 0xf0297,
  phone: 0xf03f2,
  computer: 0xf07c0
}

/**
 * The glyph for a Bluetooth device.
 * @param {string|undefined} icon - BlueZ icon name (Quickshell BluetoothDevice.icon)
 * @param {boolean} connected - the device is connected (generic glyph only)
 * @returns {string} a Nerd Font glyph
 */
function deviceGlyph(icon, connected) {
  var code = typeGlyphs[String(icon || "")]
  if (code) return String.fromCodePoint(code)
  return String.fromCodePoint(connected ? 0xf00b1 : 0xf00af)
}

/**
 * Signal level for an RSSI reading.
 * @param {number|undefined} rssi - dBm
 * @returns {number} 3 strong, 2 fair, 1 weak, 0 none
 */
function signalLevel(rssi) {
  if (typeof rssi !== "number" || !isFinite(rssi)) return 0
  if (rssi >= -60) return 3
  if (rssi >= -75) return 2
  if (rssi >= -90) return 1
  return 0
}

/**
 * RSSI per device address from `busctl --json=short call org.bluez /
 * org.freedesktop.DBus.ObjectManager GetManagedObjects` output.
 * @param {string|undefined} json - the command's stdout
 * @returns {Record<string, number>} upper-case address to RSSI
 */
function parseRssi(json) {
  /** @type {Record<string, number>} */
  var out = {}
  var parsed
  try {
    parsed = JSON.parse(String(json || ""))
  } catch (e) {
    return out
  }
  var objects = parsed && Array.isArray(parsed.data) ? parsed.data[0] : null
  if (!objects || typeof objects !== "object") return out
  for (var path in objects) {
    var device = objects[path] && objects[path]["org.bluez.Device1"]
    if (!device || !device.Address || !device.RSSI) continue
    var rssi = Number(device.RSSI.data)
    if (isFinite(rssi)) out[String(device.Address.data).toUpperCase()] = rssi
  }
  return out
}

/**
 * The dropdown's empty text, stock's wording with the adapter checked
 * first: without one the view hides every list, whatever the device rows.
 * @param {boolean} hasAdapter - a Bluetooth adapter is present
 * @param {boolean} enabled - the adapter is powered on
 * @param {boolean} hasRows - any connected, paired or available row exists
 * @returns {string} the text, or "" when the lists speak for themselves
 */
function emptyText(hasAdapter, enabled, hasRows) {
  if (!hasAdapter) return "No Bluetooth adapter"
  if (hasRows) return ""
  return enabled ? "Scanning for devices…" : "Turn Bluetooth on to scan"
}

/**
 * Whether a new RSSI poll differs from the readings already held, so an
 * unchanged poll can skip reassigning them (and rebuilding the view).
 * @param {Record<string, number>|undefined} prev - the readings held now
 * @param {Record<string, number>|undefined} next - the new poll's readings
 * @returns {boolean} true when an address or a value differs
 */
function rssiChanged(prev, next) {
  return JSON.stringify(prev || {}) !== JSON.stringify(next || {})
}

/**
 * A pending power change: `target` is the state sent to the adapter and not
 * yet echoed back by BlueZ's Powered (null when idle), `queued` the state
 * clicked while waiting (null for none).
 * @typedef {{target: ?boolean, queued: ?boolean}} PowerPending
 */

/**
 * The idle power state: nothing sent, nothing queued.
 * @returns {PowerPending} a fresh idle state
 */
function powerIdle() {
  return { target: null, queued: null }
}

/**
 * A click on the power switch (or b, or the bar icon's right-click). Idle,
 * it sends the opposite of the adapter's state at once. While a change is in
 * flight it only queues the opposite of what the switch shows; the last
 * click wins, and a click back to the in-flight state empties the queue.
 * @param {?PowerPending} state - the pending state (null counts as idle)
 * @param {boolean} actual - the adapter's Powered
 * @returns {{state: PowerPending, send: ?boolean}} the next state and the value to send now (null: send nothing)
 */
function powerClick(state, actual) {
  var s = state || powerIdle()
  if (s.target === null || s.target === undefined) {
    var target = !actual
    return { state: { target: target, queued: null }, send: target }
  }
  var shown = s.queued !== null && s.queued !== undefined ? s.queued : s.target
  var next = !shown
  return { state: { target: s.target, queued: next === s.target ? null : next }, send: null }
}

/**
 * The adapter's Powered changed (or was read back). When it reaches the
 * in-flight target, a queued state that differs is sent next; otherwise the
 * switch goes idle. A value other than the target keeps waiting (a timeout
 * calls powerIdle).
 * @param {?PowerPending} state - the pending state
 * @param {boolean} actual - the adapter's Powered now
 * @returns {{state: PowerPending, send: ?boolean}} the next state and the value to send now (null: send nothing)
 */
function powerEcho(state, actual) {
  var s = state || powerIdle()
  if (s.target === null || s.target === undefined || s.target !== !!actual)
    return { state: s, send: null }
  if (s.queued !== null && s.queued !== undefined && s.queued !== !!actual)
    return { state: { target: s.queued, queued: null }, send: s.queued }
  return { state: powerIdle(), send: null }
}

/**
 * What the power switch shows: the queued state, else the in-flight one,
 * else the adapter's; busy (pulsing) while a change is in flight.
 * @param {?PowerPending} state - the pending state
 * @param {boolean} actual - the adapter's Powered
 * @returns {{on: boolean, busy: boolean}} the header's power part
 */
function powerView(state, actual) {
  var s = state || powerIdle()
  var busy = s.target !== null && s.target !== undefined
  var on = s.queued !== null && s.queued !== undefined ? s.queued : busy ? s.target : !!actual
  return { on: !!on, busy: busy }
}

/**
 * What a row action asks of its device, by the rules the panel always used:
 * a primary click disconnects a connected device and connects (or pairs)
 * any other; a right-click disconnects a connected device and forgets a
 * remembered one (an Available row has none); forget forgets.
 * @param {string} name - "primary", "secondary" or "forget"
 * @param {boolean} connected - the device is connected
 * @param {string} section - "connected", "known" or "discovered"
 * @returns {string} "connect", "disconnect", "forget" or "" for nothing
 */
function rowIntent(name, connected, section) {
  if (name === "primary") return connected ? "disconnect" : "connect"
  if (name === "secondary") {
    if (connected) return "disconnect"
    return section !== "discovered" ? "forget" : ""
  }
  return name === "forget" ? "forget" : ""
}

/**
 * The action a device is busy with: the panel's own pending action first,
 * then BlueZ's connecting (3) or disconnecting (2) state or a pairing in
 * progress. A device is busy exactly when this isn't "".
 * @param {string|undefined} pending - "connecting", "disconnecting", "forgetting" or ""
 * @param {number|undefined} state - BlueZ's device state
 * @param {boolean|undefined} pairing - a pairing is in progress
 * @returns {string} "connect", "disconnect", "forget" or ""
 */
function inFlightIntent(pending, state, pairing) {
  if (pending === "connecting") return "connect"
  if (pending === "disconnecting") return "disconnect"
  if (pending === "forgetting") return "forget"
  if (state === 3 || pairing === true) return "connect"
  if (state === 2) return "disconnect"
  return ""
}

/**
 * A device action asked for (a click or a key). An idle device runs it at
 * once. A busy one queues it, one per device and the last one wins; an
 * action equal to the one in flight is dropped and empties that device's
 * queue. The input map is never mutated.
 * @param {Record<string, string>|null|undefined} queue - address to queued intent
 * @param {string} key - the device's address
 * @param {string} intent - "connect", "disconnect" or "forget" ("" for nothing)
 * @param {string} inFlight - inFlightIntent for the device ("" when idle)
 * @returns {{queue: Record<string, string>, run: string}} the next queue and the intent to run now ("" for none)
 */
function deviceClick(queue, key, intent, inFlight) {
  /** @type {Record<string, string>} */
  var q = Object.assign({}, queue || {})
  if (!intent || !key) return { queue: q, run: "" }
  if (!inFlight) {
    delete q[key]
    return { queue: q, run: intent }
  }
  if (intent === inFlight) delete q[key]
  else q[key] = intent
  return { queue: q, run: "" }
}

/**
 * The queued device actions whose device has gone idle, to run now. A
 * device missing from `inFlight` is gone, so its entry is dropped.
 * @param {Record<string, string>|null|undefined} queue - address to queued intent
 * @param {Record<string, string>|null|undefined} inFlight - address to inFlightIntent, for every device present
 * @returns {{queue: Record<string, string>, run: Array<{key: string, intent: string}>}} what still waits and what runs now
 */
function takeReady(queue, inFlight) {
  /** @type {Record<string, string>} */
  var rest = {}
  var run = []
  var busy = inFlight || {}
  var q = queue || {}
  for (var key in q) {
    if (!(key in busy)) continue
    if (busy[key] === "") run.push({ key: key, intent: q[key] })
    else rest[key] = q[key]
  }
  return { queue: rest, run: run }
}

/**
 * The keyboard cursor's stops for following a keyboard Forget, top to
 * bottom: the power switch ("header"), the Connected and Paired rows keyed
 * by address, then the Available rows keyed "scan:" plus the address, so a
 * forgotten device that the scan shows again counts as gone from where it
 * was.
 * @param {Array<string>|null|undefined} connected - Connected addresses
 * @param {Array<string>|null|undefined} known - Paired addresses
 * @param {Array<string>|null|undefined} discovered - Available addresses (only while shown)
 * @returns {Array<{key: string, section: string, index: number}>} the stops
 */
function forgetStops(connected, known, discovered) {
  var stops = [{ key: "header", section: "header", index: -1 }]
  var parts = [
    { list: connected, section: "connected", prefix: "" },
    { list: known, section: "known", prefix: "" },
    { list: discovered, section: "discovered", prefix: "scan:" }
  ]
  for (var p = 0; p < parts.length; p++) {
    var l = Array.isArray(parts[p].list) ? parts[p].list : []
    for (var i = 0; i < l.length; i++)
      stops.push({ key: parts[p].prefix + String(l[i]), section: parts[p].section, index: i })
  }
  return stops
}

/**
 * Where the keyboard cursor goes after the device lists changed while a
 * keyboard Forget was pending. While `pendingKey` (the device's address)
 * still names a stop, the forget hasn't landed: nothing follows and its
 * stop index is tracked. Once it is gone, the cursor lands on the
 * neighbour (CursorLogic.afterRemoval): the row now at its index, else the
 * one before, and the pending key is spent.
 * @param {Array<{key: string, section: string, index: number}>} stops - forgetStops, read after the change
 * @param {string} pendingKey - the address a keyboard Forget armed, "" for none
 * @param {number} lastIndex - the forgotten row's last stop index
 * @returns {{follow: boolean, pendingKey: string, lastIndex: number, key?: string, section?: string, index?: number}} whether to move the cursor, and where (section and index within it)
 */
function followForget(stops, pendingKey, lastIndex) {
  if (!pendingKey) return { follow: false, pendingKey: "", lastIndex: lastIndex }
  for (var i = 0; i < stops.length; i++)
    if (stops[i].key === pendingKey) return { follow: false, pendingKey: pendingKey, lastIndex: i }
  var next = afterRemoval(stops, pendingKey, lastIndex)
  var stop = stops[next.index]
  return {
    follow: true,
    pendingKey: "",
    lastIndex: next.index,
    key: next.key,
    section: stop.section,
    index: stop.index
  }
}

/* @aranea-facade-start: plugins/araneadev.shared/CursorLogic.js */
// Shared keyboard-cursor safety rules, moved out of the Network plugin so
// araneadev.vpn can reuse them: a cursor follows the row key it was put on
// (never its position), a lost or evacuated key is refused rather than
// retargeted, and a pointer action only ever lands on the row it names. No
// QML, no I/O; tests/js/cursor-logic.test.js runs this under Node.

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

if (typeof module !== "undefined")
  module.exports = {
    reselectIndex: reselectIndex,
    followCursor: followCursor,
    cursorConfirmed: cursorConfirmed,
    pressIntent: pressIntent,
    keepRows: keepRows,
    rowKeyMatches: rowKeyMatches,
    afterRemoval: afterRemoval
  }
/* @aranea-facade-end */

if (typeof module !== "undefined")
  module.exports = {
    deviceGlyph,
    signalLevel,
    parseRssi,
    emptyText,
    rssiChanged,
    powerIdle,
    powerClick,
    powerEcho,
    powerView,
    rowIntent,
    inFlightIntent,
    deviceClick,
    takeReady,
    forgetStops,
    followForget,
    rowKeyMatches
  }
