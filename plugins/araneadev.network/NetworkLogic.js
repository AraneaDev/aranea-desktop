// Pure rules for the Aranea network dropdown (Panel.qml): parsing nmcli and
// `ip -j` output, building the interface/saved-network rows, and vertical
// keyboard navigation (header, band, DNS, Wi-Fi, saved -- VPN control moved
// to araneadev.vpn). The cursor safety primitives
// (reselectIndex, followCursor, cursorConfirmed, keepRows, rowKeyMatches,
// pressIntent) and the throughput graph's points (pushSample, graphPoints)
// moved to `araneadev.shared` (CursorLogic.js, GraphLogic.js) so
// araneadev.vpn can reuse them. Panel.qml imports CursorLogic.js and
// GraphLogic.js directly for its own calls; this file's own
// keyTargetConfirmed/pressOutcome (Network-only section logic) call a
// generated copy of CursorLogic's cursorConfirmed/pressIntent instead of a
// hand-duplicated copy, as does splitTerse for NmcliTerse.js, via
// `tools/js-facade-generator.mjs` (see docs/development.md's "JavaScript
// facades"), since there is no cross-`.js`-file import mechanism usable
// from both QML and Node in this codebase. No QML, no I/O;
// tests/js/network-logic.test.js runs this under Node.

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
 * followCursor for a cursor that may be showing its outline: when the row
 * whose key the cursor held is gone, the outline hides too (`keyboard`
 * false), so it never marks a row Enter would refuse. The next key only
 * reveals the cursor again, where it now sits, and a later Enter acts.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the new rows
 * @param {string|null|undefined} key - the key the cursor was deliberately put on, or ""
 * @param {number} index - the cursor's index before the change
 * @param {boolean} keyboard - whether the keyboard shows the outline
 * @returns {{index: number, key: string, confirmed: boolean, keyboard: boolean}} followCursor's answer and whether the outline still shows
 */
function followShown(rows, key, index, keyboard) {
  var next = followCursor(rows, key, index)
  var lost = typeof key === "string" && key !== "" && !next.confirmed
  return {
    index: next.index,
    key: next.key,
    confirmed: next.confirmed,
    keyboard: !!keyboard && !lost
  }
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
 * What Enter or Space does on a keyed list. Like an arrow, it first only
 * reveals a cursor the keyboard is not showing: on its row when that is
 * still shown, else on the first row. Only on a shown cursor's row does it
 * hand that row back to act on. With no rows it does nothing.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {{key: string, keyboard: boolean, row: ?object}} the cursor key, the new mode and the row to act on, or null
 */
function keyedPress(rows, key, keyboard, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  var i = keyIndex(list, key, keyOf)
  if (pressIntent(i >= 0, keyboard) === "act") return { key: key, keyboard: true, row: list[i] }
  if (list.length === 0) return { key: key, keyboard: keyboard, row: null }
  return { key: i >= 0 ? key : keyOf(list[0]), keyboard: true, row: null }
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
    followShown: followShown,
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

/* @aranea-facade-start: plugins/araneadev.shared/NmcliTerse.js */
// Shared nmcli terse-output parsing, generated into
// `araneadev.network/NetworkLogic.js` and `araneadev.vpn/VpnLogic.js` by
// `tools/js-facade-generator.mjs` (see docs/development.md's "JavaScript
// facades") rather than imported or hand-copied, since no cross-`.js`-file
// import mechanism is usable from both QML and Node in this codebase. No
// QML, no I/O; tests/js/nmcli-terse.test.js runs this under Node.

/**
 * Splits one `nmcli -t` line into its fields, on unescaped `:` only, and
 * unescapes `\:` and `\\` within each field.
 * @param {string|undefined} line - one line of `nmcli -t` output
 * @returns {string[]} the line's fields, unescaped
 */
function splitTerse(line) {
  var s = String(line || "")
  var fields = []
  var cur = ""
  for (var i = 0; i < s.length; i++) {
    var c = s[i]
    if (c === "\\" && i + 1 < s.length && (s[i + 1] === ":" || s[i + 1] === "\\")) {
      cur += s[i + 1]
      i++
      continue
    }
    if (c === ":") {
      fields.push(cur)
      cur = ""
      continue
    }
    cur += c
  }
  fields.push(cur)
  return fields
}

if (typeof module !== "undefined") module.exports = { splitTerse: splitTerse }
/* @aranea-facade-end */

/** @type {Record<string, string>} */
var interfaceTypeLabels = {
  wifi: "Wi-Fi",
  ethernet: "Ethernet",
  gsm: "Mobile",
  cdma: "Mobile",
  wireguard: "WireGuard",
  tun: "Tunnel"
}

/** @type {Record<string, number>} */
var interfaceGlyphs = {
  wifi: 0xf05a9,
  ethernet: 0xf0200,
  gsm: 0xf08bc,
  cdma: 0xf08bc,
  wireguard: 0xf0582,
  tun: 0xf0582
}

/**
 * Unescapes a single nmcli terse field: `\:` becomes `:` and `\\` becomes `\`.
 * @param {string} raw - one field's raw (still-escaped) text
 * @returns {string} the unescaped text
 */
function unescapeTerse(raw) {
  var s = String(raw || "")
  var out = ""
  for (var i = 0; i < s.length; i++) {
    var c = s[i]
    if (c === "\\" && i + 1 < s.length && (s[i + 1] === ":" || s[i + 1] === "\\")) {
      out += s[i + 1]
      i++
      continue
    }
    out += c
  }
  return out
}

/**
 * Splits text into sections on lines that are exactly `---`.
 * @param {string|undefined} text - the combined command output
 * @returns {string[]} each section's text; `[]` when text is missing
 */
function splitSections(text) {
  if (!text) return []
  var lines = String(text).split("\n")
  var sections = []
  var current = []
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] === "---") {
      sections.push(current.join("\n"))
      current = []
    } else {
      current.push(lines[i])
    }
  }
  sections.push(current.join("\n"))
  return sections
}

/**
 * Parses `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device` output.
 * @param {string|undefined} text - the command's stdout
 * @returns {Array<{device: string, type: string, state: string, connection: string}>} the devices
 */
function parseDevices(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var f = splitTerse(line)
    if (f.length < 4) continue
    out.push({ device: f[0], type: f[1], state: f[2], connection: f[3] })
  }
  return out
}

/**
 * Parses `nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,TIMESTAMP,STATE connection show`
 * output. STATE ("activating", "activated", ...) is "" when nmcli leaves it
 * out or the profile isn't active.
 * @param {string|undefined} text - the command's stdout
 * @returns {Array<{name: string, uuid: string, type: string, device: string, active: boolean, timestamp: number, state: string}>} the connections
 */
function parseConnections(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var f = splitTerse(line)
    if (f.length < 6) continue
    var ts = Number(f[5])
    out.push({
      name: f[0],
      uuid: f[1],
      type: f[2],
      device: f[3],
      active: f[4] === "yes",
      timestamp: isFinite(ts) ? ts : 0,
      state: f[6] || ""
    })
  }
  return out
}

/**
 * Parses `ip -j -4 -br addr` output into each interface's first IPv4 address.
 * @param {string|undefined} json - the command's stdout
 * @returns {Record<string, string>} interface name to IPv4 address; `{}` on bad input
 */
function parseAddrs(json) {
  /** @type {Record<string, string>} */
  var out = {}
  var parsed
  try {
    parsed = JSON.parse(String(json || ""))
  } catch (e) {
    return out
  }
  if (!Array.isArray(parsed)) return out
  for (var i = 0; i < parsed.length; i++) {
    var item = parsed[i] || {}
    var infos = Array.isArray(item.addr_info) ? item.addr_info : []
    var local = infos.length > 0 && infos[0] ? infos[0].local : undefined
    if (item.ifname && local) out[item.ifname] = local
  }
  return out
}

/**
 * Parses `uuid<TAB>ssid` lines into a uuid-to-SSID map, unescaping the SSID
 * as `splitTerse` does. An empty SSID (a failed lookup) maps nothing.
 * @param {string|undefined} text - the command's stdout
 * @returns {Record<string, string>} connection uuid to SSID
 */
function parseSsids(text) {
  /** @type {Record<string, string>} */
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var tab = line.indexOf("\t")
    if (tab === -1) continue
    var ssid = unescapeTerse(line.substring(tab + 1))
    // A failed lookup prints an empty SSID: no mapping, not "".
    if (ssid === "") continue
    out[line.substring(0, tab)] = ssid
  }
  return out
}

/**
 * Whether a device name belongs to a virtual interface the dropdown hides
 * (container and bridge plumbing, never a network the user picks).
 * @param {string|undefined} device - the device name
 * @returns {boolean} true when the device should be dropped
 */
function isVirtualDevice(device) {
  var name = String(device || "")
  return (
    name.indexOf("docker") === 0 ||
    name.indexOf("veth") === 0 ||
    name.indexOf("br-") === 0 ||
    name.indexOf("virbr") === 0
  )
}

/**
 * The state text shown in an interface row's detail.
 * @param {string} type - the device type (`ethernet`, `wifi`, ...)
 * @param {string|undefined} state - the raw nmcli state
 * @returns {string} `connected`, `cable unplugged`, or the raw state
 */
function interfaceStateText(type, state) {
  var s = String(state || "")
  if (s.indexOf("connected") === 0) return "connected"
  if (type === "ethernet" && s === "unavailable") return "cable unplugged"
  return s
}

/**
 * Orders rows with active ones first, then alphabetically by label.
 * @param {{active: boolean, label: string}} a - a row
 * @param {{active: boolean, label: string}} b - another row
 * @returns {number} negative, zero or positive as `Array#sort` expects
 */
function compareActiveThenLabel(a, b) {
  if (a.active !== b.active) return a.active ? -1 : 1
  if (a.label < b.label) return -1
  if (a.label > b.label) return 1
  return 0
}

/**
 * Builds the interface rows (Wi-Fi, Ethernet, mobile, WireGuard, tunnel).
 * A null or non-object entry in `devices` is
 * ignored rather than thrown on.
 * @param {Array<{device: string, type: string, state: string, connection: string}>|undefined} devices - from `parseDevices`
 * @param {Record<string, string>|undefined} addrs - from `parseAddrs`
 * @returns {Array<{key: string, glyph: string, label: string, detail: string, active: boolean}>} the rows
 */
function interfaceRows(devices, addrs) {
  var list = Array.isArray(devices) ? devices : []
  var addrMap = addrs || {}
  var rows = []
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (!d) continue
    var type = d.type
    if (!Object.prototype.hasOwnProperty.call(interfaceTypeLabels, type)) continue
    if (d.state === "unmanaged") continue
    if (isVirtualDevice(d.device)) continue
    var active = String(d.state || "").indexOf("connected") === 0
    var detail = interfaceTypeLabels[type] + " · " + interfaceStateText(type, d.state)
    var ip = addrMap[d.device]
    if (ip) detail += " · " + ip
    rows.push({
      key: d.device,
      glyph: String.fromCodePoint(interfaceGlyphs[type]),
      label: d.device,
      detail: detail,
      active: active
    })
  }
  rows.sort(compareActiveThenLabel)
  return rows
}

/**
 * Parses `ip -j -4 -br addr` output into its link entries, for the own-app
 * VPN detection the Network status line uses
 * (`araneadev.shared/VpnApps.js`'s `appState` / `appInterface`). Anything
 * that isn't a JSON array of entries reads as no links.
 * @param {string|undefined} json - the command's stdout
 * @returns {Array<{ifname?: string, operstate?: string, addr_info?: any[]}>} the parsed links, or `[]` on bad input
 */
function parseLinks(json) {
  var parsed
  try {
    parsed = JSON.parse(String(json || ""))
  } catch (e) {
    return []
  }
  return Array.isArray(parsed) ? parsed : []
}

/**
 * The SSID for a saved Wi-Fi connection: the scanned SSID when it is known,
 * else the connection's own name.
 * @param {{name: string, uuid: string}} connection - the saved connection
 * @param {Record<string, string>} ssidByUuid - connection uuid to SSID
 * @returns {string} the SSID to show
 */
function savedSsid(connection, ssidByUuid) {
  var hasMapping = Object.prototype.hasOwnProperty.call(ssidByUuid, connection.uuid)
  return hasMapping ? ssidByUuid[connection.uuid] : connection.name
}

/**
 * Builds the saved-network rows: known Wi-Fi connections not already shown
 * as a scanned network. A null or non-object entry in `connections` is
 * ignored rather than thrown on.
 * @param {Array<{name: string, uuid: string, type: string, device: string, active: boolean, timestamp: number}>|undefined} connections - from `parseConnections`
 * @param {Record<string, string>|undefined} ssidByUuid - from `parseSsids`
 * @param {string[]|undefined} scannedSsids - SSIDs already shown in the live scan
 * @param {number} nowSeconds - the current time, in epoch seconds
 * @returns {Array<{key: string, label: string, detail: string}>} the rows, newest first
 */
function savedRows(connections, ssidByUuid, scannedSsids, nowSeconds) {
  var list = Array.isArray(connections) ? connections : []
  var ssidMap = ssidByUuid || {}
  var scanned = Array.isArray(scannedSsids) ? scannedSsids : []
  /** @type {Array<{name: string, uuid: string, type: string, device: string, active: boolean, timestamp: number}>} */
  var entries = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!c) continue
    if (c.type !== "802-11-wireless") continue
    var ssid = savedSsid(c, ssidMap)
    if (!ssid) continue
    if (scanned.indexOf(ssid) !== -1) continue
    entries.push(c)
  }
  entries.sort(function (a, b) {
    return b.timestamp - a.timestamp
  })
  var rows = []
  for (var j = 0; j < entries.length; j++) {
    var entry = entries[j]
    rows.push({
      key: entry.uuid,
      label: savedSsid(entry, ssidMap),
      detail: lastUsedText(entry.timestamp, nowSeconds)
    })
  }
  return rows
}

/**
 * The "last used" text for a saved network's detail.
 * @param {number|undefined} ts - the connection's last-used time, in epoch seconds
 * @param {number|undefined} now - the current time, in epoch seconds
 * @returns {string} `never used`, `last used today`, `last used yesterday`, or `last used N days ago`
 */
function lastUsedText(ts, now) {
  var t = Number(ts) || 0
  var n = Number(now) || 0
  if (t <= 0) return "never used"
  var diff = n - t
  if (diff < 86400) return "last used today"
  if (diff < 172800) return "last used yesterday"
  return "last used " + Math.floor(diff / 86400) + " days ago"
}

/**
 * The next keyboard-navigation state after moving vertically, following the
 * dropdown's header/band/DNS/wifi/saved section order and skipping any
 * section with nothing in it. QML can hand this a null `state` before its
 * bindings settle, in which case it lands on dns/auto; a null `avail` reads
 * as nothing available anywhere.
 * @param {{section: string, index: number, bandAuto: boolean}|null|undefined} state - the current navigation state
 * @param {number} dy - the direction: negative for up, positive for down
 * @param {{header: number, band: boolean, bandPills: boolean, wifi: number, saved: number}|null|undefined} avail - what's available to land on
 * @returns {{section: string, index: number, bandAuto: boolean}} the next state
 */
function moveVertical(state, dy, avail) {
  if (!state) return { section: "dns", index: 0, bandAuto: true }
  var section = state.section
  var index = Number(state.index) || 0
  var bandAuto = !!state.bandAuto
  var header = avail ? Number(avail.header) || 0 : 0
  var band = avail ? !!avail.band : false
  var bandPills = avail ? !!avail.bandPills : false
  var wifi = avail ? Number(avail.wifi) || 0 : 0
  var saved = avail ? Number(avail.saved) || 0 : 0
  var here = { section: section, index: index, bandAuto: bandAuto }

  if (section === "header") {
    if (dy < 0) return here
    if (band) return { section: "band", index: 0, bandAuto: true }
    return { section: "dns", index: 0, bandAuto: bandAuto }
  }

  if (section === "band") {
    if (dy < 0) {
      if (!bandAuto) return { section: "band", index: 0, bandAuto: true }
      if (header > 0) return { section: "header", index: 0, bandAuto: bandAuto }
      return here
    }
    if (bandAuto && bandPills) return { section: "band", index: 0, bandAuto: false }
    return { section: "dns", index: 0, bandAuto: bandAuto }
  }

  if (section === "dns") {
    if (dy < 0) {
      if (band) return { section: "band", index: 0, bandAuto: !bandPills }
      if (header > 0) return { section: "header", index: 0, bandAuto: bandAuto }
      return here
    }
    if (wifi > 0) return { section: "wifi", index: 0, bandAuto: bandAuto }
    if (saved > 0) return { section: "saved", index: 0, bandAuto: bandAuto }
    return here
  }

  if (section === "wifi") {
    var wifiNext = index + dy
    if (wifiNext < 0) return { section: "dns", index: 0, bandAuto: bandAuto }
    if (wifiNext > wifi - 1) {
      if (saved > 0) return { section: "saved", index: 0, bandAuto: bandAuto }
      return here
    }
    return { section: "wifi", index: wifiNext, bandAuto: bandAuto }
  }

  if (section === "saved") {
    var savedNext = index + dy
    if (savedNext < 0) {
      if (wifi > 0) return { section: "wifi", index: wifi - 1, bandAuto: bandAuto }
      return { section: "dns", index: 0, bandAuto: bandAuto }
    }
    if (savedNext > saved - 1) return here
    return { section: "saved", index: savedNext, bandAuto: bandAuto }
  }

  return here
}

/**
 * Whether a key press may act on the cursor's target: the cursor must be in
 * the section the user last deliberately put it in (an automatic move, such
 * as a section emptying or hiding under it, never counts), and on a fixed
 * control or on the row whose key it holds (the generated `cursorConfirmed`,
 * shared with `araneadev.shared/CursorLogic.js` via
 * `tools/js-facade-generator.mjs`).
 * @param {{section: string, chosen: string, fixed?: boolean, rows?: Array<{key: string}|null|undefined>, key?: string, index?: number}|null|undefined} target - the cursor's section, the section last chosen, whether the section's controls never move, and its rows, key and index
 * @returns {boolean} true when the keyboard may act
 */
function keyTargetConfirmed(target) {
  if (!target || !target.section || target.section !== target.chosen) return false
  if (target.fixed) return true
  return cursorConfirmed(target.rows, target.key, Number(target.index))
}

/**
 * The choice a fresh open makes: stock's open handler puts the Wi-Fi cursor
 * on row 0, a deliberate placement, so that row (and its section) count as
 * chosen. With no Wi-Fi rows nothing is chosen until a move, a click or a
 * keyboard reveal (revealTarget).
 * @param {Array<{key: string}|null|undefined>|undefined} wifiRows - the Wi-Fi rows at open
 * @returns {{chosen: string, key: string}} the chosen section ("wifi" or "") and row 0's key
 */
function openChoice(wifiRows) {
  if (!Array.isArray(wifiRows) || wifiRows.length === 0) return { chosen: "", key: "" }
  var row = wifiRows[0]
  return { chosen: "wifi", key: row && typeof row.key === "string" ? row.key : "" }
}

/**
 * Where the cursor goes when the Saved section empties under it: the last
 * Wi-Fi row (or DNS without one), with no key, so Enter there is refused
 * until the user picks a row.
 * @param {number|undefined} wifiCount - how many Wi-Fi rows there are
 * @returns {{section: string, index: number, key: string}} the new cursor
 */
function savedEmptyFallback(wifiCount) {
  var n = Math.floor(Number(wifiCount)) || 0
  if (n > 0) return { section: "wifi", index: n - 1, key: "" }
  return { section: "dns", index: -1, key: "" }
}

/**
 * What Enter or `x` does to the cursor's target. Before any cursor exists
 * or on a cursor the keyboard isn't showing it only reveals the outline
 * (`ignore` or `reveal`; the host reveals either way, see `revealTarget`);
 * otherwise it acts only when `keyTargetConfirmed`, else it's refused. The
 * ignore/reveal/act split is the generated `pressIntent`, shared with
 * `araneadev.shared/CursorLogic.js` via `tools/js-facade-generator.mjs`.
 * @param {{section: string, chosen: string, fixed?: boolean, rows?: Array<{key: string}|null|undefined>, key?: string, index?: number}|null|undefined} target - the cursor's target, as for keyTargetConfirmed
 * @param {boolean} cursorActive - whether a cursor has been placed
 * @param {boolean} keyboardCursor - whether its outline is showing
 * @returns {string} `ignore`, `reveal`, `refuse` or `act`
 */
function pressOutcome(target, cursorActive, keyboardCursor) {
  var intent = pressIntent(cursorActive, keyboardCursor)
  if (intent !== "act") return intent
  return keyTargetConfirmed(target) ? "act" : "refuse"
}

/**
 * The choice a keyboard reveal makes: the outline marks Enter's target, so
 * revealing it chooses the cursor's section and adopts the key of the row
 * (or band control) it now shows. Only the next Enter, on the visible
 * outline, acts, so joining a network still takes a deliberate second key.
 * @param {{section: string, chosen?: string, fixed?: boolean, rows?: Array<{key: string}|null|undefined>, key?: string, index?: number}|null|undefined} target - the cursor's target, as for keyTargetConfirmed
 * @returns {{section: string, chosen: string, fixed?: boolean, rows?: Array<{key: string}|null|undefined>, key: string, index?: number}} the target as the reveal leaves it
 */
function revealTarget(target) {
  var t = target || { section: "" }
  var rows = Array.isArray(t.rows) ? t.rows : []
  var row = rows[Math.floor(Number(t.index))]
  var key = !t.fixed && row && typeof row.key === "string" ? row.key : ""
  return {
    section: t.section,
    chosen: t.section || "",
    fixed: t.fixed,
    rows: t.rows,
    key: key,
    index: t.index
  }
}

/**
 * Whether a left/right press in `section` is a deliberate choice of the
 * control it lands on: the header actions, the band pills and the DNS
 * pills. On Automatic (`bandAuto`) it does nothing; on a Wi-Fi or Saved
 * row it only moves onto the row's forget action, which chooses no row.
 * @param {string} section - the cursor's section
 * @param {boolean} bandAuto - whether the band cursor is on the Automatic switch
 * @returns {boolean} true when the press chooses
 */
function sidewaysChooses(section, bandAuto) {
  if (section === "band") return !bandAuto
  return section === "header" || section === "dns"
}

/**
 * What Enter does on a confirmed row. On Saved, Enter only moves onto the
 * forget action; Enter there (or `x`) forgets. On Wi-Fi, Enter on a focused
 * forget action forgets, and does nothing once the row can't be forgotten
 * (so it never becomes a disconnect).
 * @param {string} section - the cursor's section
 * @param {boolean} actionFocused - whether the cursor is on the row's forget action
 * @param {boolean} forgettable - whether the row can be forgotten
 * @returns {string} `focusForget`, `forget`, `none` or `activate`
 */
function enterDecision(section, actionFocused, forgettable) {
  if (section === "saved") return actionFocused ? "forget" : "focusForget"
  if (section === "wifi" && actionFocused) return forgettable ? "forget" : "none"
  return "activate"
}

/**
 * What follows an extras read. A request that arrived while it ran (a forget
 * landing mid-poll) re-reads, since this result may predate it; a pending
 * forget's busy state and the SSID lookup settle only on a read that started
 * after the forget finished.
 * @param {boolean} dirty - whether another read was asked for while this one ran
 * @param {boolean} forgetRunning - whether a saved forget is still running
 * @returns {{rerun: boolean, settle: boolean}} whether to read again and whether this read settles pending work
 */
function extrasFollowUp(dirty, forgetRunning) {
  return { rerun: !!dirty, settle: !dirty && !forgetRunning }
}

/**
 * Whether the extras process exiting should read again: a request that
 * arrived after its output was applied (a forget finishing between the
 * output and the exit) only marked it dirty, and nothing else re-reads.
 * @param {boolean} dirty - whether another read was asked for and not yet followed up
 * @returns {boolean} true to read again
 */
function extrasExitFollowUp(dirty) {
  return !!dirty
}

/**
 * The Saved rows' action state by uuid: the profile being forgotten
 * breathes with "Forgetting…"; one whose forget failed reads "Couldn't
 * forget" (shown in the urgent colour). A running forget wins.
 * @param {string|null|undefined} forgettingUuid - the profile a forget is running for, or ""
 * @param {string|null|undefined} failedUuid - the profile whose last forget failed, or ""
 * @returns {Record<string, {busy: boolean, failed: boolean, text: string}>} uuid -> state
 */
function savedStatusMap(forgettingUuid, failedUuid) {
  /** @type {Record<string, {busy: boolean, failed: boolean, text: string}>} */
  var out = {}
  if (failedUuid) out[failedUuid] = { busy: false, failed: true, text: "Couldn't forget" }
  if (forgettingUuid) out[forgettingUuid] = { busy: true, failed: false, text: "Forgetting…" }
  return out
}

/**
 * The key-hint line for the cursor's section, saying what Enter does there.
 * @param {string|undefined} section - the cursor's section
 * @returns {string} the hint
 */
function keyHint(section) {
  if (section === "saved") return "↑↓ move · enter/→ select forget · x forget"
  if (section === "header" || section === "band" || section === "dns")
    return "↑↓ move · ←→ pick · enter apply"
  return "↑↓ move · ←→ pick · enter toggle · x forget"
}

/**
 * Which DNS provider the pills should show chosen: the one just requested
 * but not yet confirmed by `actionProc` exiting (`pendingDnsProvider`), so a
 * click (or Enter) moves the selected pill at once instead of waiting for
 * `omarchy-dns` to finish; else the provider last read from it. Mirrors
 * araneadev.power's `selectedProfile`.
 * @param {string|null|undefined} pendingDnsProvider - requested but unconfirmed, "" for none
 * @param {string|null|undefined} dnsProvider - the provider last read from omarchy-dns
 * @returns {string} the key the DNS pills should mark selected
 */
function selectedDnsProvider(pendingDnsProvider, dnsProvider) {
  return pendingDnsProvider || dnsProvider || ""
}

if (typeof module !== "undefined")
  module.exports = {
    splitTerse: splitTerse,
    splitSections: splitSections,
    parseDevices: parseDevices,
    parseConnections: parseConnections,
    parseAddrs: parseAddrs,
    parseSsids: parseSsids,
    parseLinks: parseLinks,
    interfaceRows: interfaceRows,
    savedRows: savedRows,
    lastUsedText: lastUsedText,
    moveVertical: moveVertical,
    keyTargetConfirmed: keyTargetConfirmed,
    openChoice: openChoice,
    pressOutcome: pressOutcome,
    revealTarget: revealTarget,
    sidewaysChooses: sidewaysChooses,
    extrasExitFollowUp: extrasExitFollowUp,
    savedStatusMap: savedStatusMap,
    savedEmptyFallback: savedEmptyFallback,
    enterDecision: enterDecision,
    extrasFollowUp: extrasFollowUp,
    keyHint: keyHint,
    selectedDnsProvider: selectedDnsProvider
  }
