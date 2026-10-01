// Pure rules for the Aranea VPN dropdown (Panel.qml): parsing nmcli's VPN
// connection list and per-connection session fields, building the
// Connected/Available rows (NetworkManager profiles and own-app VPNs), the
// secrets sent to nmcli on stdin, auth-failure detection, the nmcli argv for
// connect/disconnect, and the small text helpers (uptime, status, header
// caption, key hints). No QML, no I/O; tests/js/vpn-logic.test.js runs this
// under Node.
//
// `splitTerse` is a generated copy of `araneadev.shared/NmcliTerse.js`
// (`tools/js-facade-generator.mjs`, see docs/development.md's "JavaScript
// facades"), not imported or hand-copied: there is no cross-`.js`-file
// import mechanism usable from both QML and Node in this codebase, so every
// plugin that needs it gets the generator's copy instead.

/** @type {number} the glyph shared by NetworkManager VPN and WireGuard rows (same mark NetworkLogic uses for its VPN rows) */
var VPN_GLYPH = 0xf0582

/** @type {number} the glyph for an own-app VPN row ("open in new"); Task 3's QML may swap this for a different mark */
var APP_GLYPH = 0xf05f4

/**
 * One parsed VPN or WireGuard connection, from
 * `nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,STATE connection show`.
 * @typedef {{name: string, uuid: string, type: string, device: string, active: boolean, state: string}} VpnConnection
 */

/**
 * A connection's session fields, from `nmcli -t -g
 * IP4.ADDRESS,vpn.data,vpn.service-type,wireguard.peers connection show uuid <u>`.
 * @typedef {{ip: string, server: string, vpnType: string}} VpnSession
 */

/**
 * One own-app VPN entry, as parsed by `araneadev.shared/VpnApps.js`.
 * @typedef {{name: string, label: string, detect: object, open: string[]}} VpnAppEntry
 */

/**
 * A Connected or Available row: a NetworkManager profile (`kind: "nm"`,
 * keyed by its uuid, carrying a static `detail` type label) or an own-app
 * VPN (`kind: "app"`, keyed by `"app:" + name`, no static detail since its
 * status line is a separate, fast-changing view property).
 * @typedef {{key: string, kind: string, name: string, glyph: string, label: string, detail: string}} NmRow
 * @typedef {{key: string, kind: string, name: string, glyph: string, label: string}} AppRow
 */

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

/**
 * Parses `nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,STATE connection show`
 * output, keeping only `vpn` and `wireguard` connections.
 * @param {string|undefined} text - the command's stdout
 * @returns {VpnConnection[]} the VPN and WireGuard connections
 */
function parseVpnConnections(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var f = splitTerse(line)
    if (f.length < 6) continue
    var type = f[2]
    if (type !== "vpn" && type !== "wireguard") continue
    out.push({
      name: f[0],
      uuid: f[1],
      type: type,
      device: f[3],
      active: f[4] === "yes",
      state: f[5]
    })
  }
  return out
}

/**
 * The first address in a comma-separated `nmcli -g IP4.ADDRESS` value, with
 * its `/prefix` suffix dropped.
 * @param {string|undefined} line - the IP4.ADDRESS line
 * @returns {string} the first address, or "" when the line is empty
 */
function firstAddress(line) {
  var s = String(line || "").trim()
  if (!s) return ""
  var first = s.split(",")[0].trim()
  var slash = first.indexOf("/")
  return slash === -1 ? first : first.substring(0, slash)
}

/**
 * Parses a `key = value, key = value` line (nmcli's rendering of a complex
 * property such as `vpn.data`, or one WireGuard peer's attributes) into a
 * plain map.
 * @param {string|undefined} line - the raw line (or peer segment)
 * @returns {Record<string, string>} key to value
 */
function parseKeyValueList(line) {
  /** @type {Record<string, string>} */
  var out = {}
  var s = String(line || "").trim()
  if (!s) return out
  var parts = s.split(",")
  for (var i = 0; i < parts.length; i++) {
    var pair = parts[i]
    var eq = pair.indexOf("=")
    if (eq === -1) continue
    var key = pair.substring(0, eq).trim()
    var value = pair.substring(eq + 1).trim()
    if (key) out[key] = value
  }
  return out
}

/**
 * One key's value from a `vpn.data`-shaped line, parsed with
 * `parseKeyValueList`.
 * @param {string|undefined} line - the vpn.data line
 * @param {string} key - the key to read ("remote" or "gateway")
 * @returns {string} the value, or "" when the key is absent
 */
function vpnDataValue(line, key) {
  var map = parseKeyValueList(line)
  return Object.prototype.hasOwnProperty.call(map, key) ? map[key] : ""
}

/**
 * The VPN type from `vpn.service-type` (NetworkManager VPN plugins) or, when
 * that is empty, from whether `wireguard.peers` carries anything (a
 * WireGuard connection has no `vpn.service-type` at all).
 * @param {string|undefined} serviceTypeLine - the vpn.service-type line
 * @param {string|undefined} peersLine - the wireguard.peers line
 * @returns {string} "OpenVPN", "OpenConnect", "WireGuard" or "VPN"
 */
function vpnTypeFromServiceType(serviceTypeLine, peersLine) {
  var s = String(serviceTypeLine || "").toLowerCase()
  if (s.indexOf("openvpn") !== -1) return "OpenVPN"
  if (s.indexOf("openconnect") !== -1) return "OpenConnect"
  if (!s && String(peersLine || "").trim() !== "") return "WireGuard"
  return "VPN"
}

/**
 * The first WireGuard peer's endpoint host (port stripped), from a
 * `wireguard.peers` line holding one or more peers separated by `" | "`,
 * each a `parseKeyValueList`-shaped segment with an `endpoint` key.
 * @param {string|undefined} peersLine - the wireguard.peers line
 * @returns {string} the first peer's endpoint host, or "" when there is none
 */
function firstPeerHost(peersLine) {
  var s = String(peersLine || "").trim()
  if (!s) return ""
  var firstPeer = s.split("|")[0]
  var map = parseKeyValueList(firstPeer)
  var endpoint = map.endpoint || ""
  if (!endpoint) return ""
  var colon = endpoint.lastIndexOf(":")
  return colon === -1 ? endpoint : endpoint.substring(0, colon)
}

/**
 * Parses a connection's session fields from `nmcli -t -g
 * IP4.ADDRESS,vpn.data,vpn.service-type,wireguard.peers connection show uuid
 * <u>`: one requested property per line, in that order. There are no real
 * VPN profiles to capture this from; the `vpn.data` and `wireguard.peers`
 * line shapes are constructed from nmcli's documented `key = value, ...`
 * rendering of a complex property (see the task report).
 * @param {string|undefined} text - the command's stdout
 * @returns {VpnSession} the IP, server and VPN type
 */
function parseSession(text) {
  var lines = String(text || "").split("\n")
  var ipLine = lines[0]
  var vpnDataLine = lines[1]
  var serviceTypeLine = lines[2]
  var peersLine = lines[3]

  var vpnType = vpnTypeFromServiceType(serviceTypeLine, peersLine)
  var server = ""
  if (vpnType === "OpenVPN") server = vpnDataValue(vpnDataLine, "remote")
  else if (vpnType === "OpenConnect") server = vpnDataValue(vpnDataLine, "gateway")
  else if (vpnType === "WireGuard") server = firstPeerHost(peersLine)

  return { ip: firstAddress(ipLine), server: server, vpnType: vpnType }
}

/**
 * The static type label for a connection's row: "WireGuard" for a WireGuard
 * connection, the precise service type ("OpenVPN" / "OpenConnect") when a
 * session is known for it, else the generic "VPN".
 * @param {{type: string}|null|undefined} conn - the connection, as from `parseVpnConnections`
 * @param {{vpnType: string}|null|undefined} session - the connection's session, as from `parseSession`, or null when not (yet) known
 * @returns {string} the type label
 */
function typeLabel(conn, session) {
  var type = conn && conn.type
  if (type === "wireguard") return "WireGuard"
  var vpnType = session && session.vpnType
  if (vpnType === "OpenVPN" || vpnType === "OpenConnect") return vpnType
  return "VPN"
}

/**
 * Orders rows by name, for the within-group sort `vpnRows` applies to both
 * the NetworkManager rows and the own-app rows.
 * @param {{name: string}} a - a row
 * @param {{name: string}} b - another row
 * @returns {number} negative, zero or positive as `Array#sort` expects
 */
function compareByName(a, b) {
  if (a.name < b.name) return -1
  if (a.name > b.name) return 1
  return 0
}

/**
 * Builds the Connected and Available rows: NetworkManager profiles first,
 * then own-app VPNs, each group ordered by name. A NetworkManager row is
 * Connected only when `active` and fully `activated`; one still
 * `activating` stays in Available (its busy status is a separate, fast-
 * changing view property, not part of this row). An own-app row is
 * Connected when its app state is `"connected"`. A null or malformed entry
 * in `conns` or `apps` is ignored rather than thrown on.
 *
 * `otpProfiles` isn't a parameter here: the controller ruled that rows don't
 * carry the OTP mode (append vs. challenge) at all, since the panel looks it
 * up by connection name, from the apps config's `profiles` map, only at
 * secrets-submit time, well after rows are built.
 * @param {VpnConnection[]|undefined} conns - from `parseVpnConnections`
 * @param {VpnAppEntry[]|undefined} apps - from `VpnApps.parseAppsConfig`
 * @param {Record<string, string>|undefined} appStates - app name to `VpnApps.appState` result
 * @returns {{connected: Array<NmRow|AppRow>, available: Array<NmRow|AppRow>}} the two row lists
 */
function vpnRows(conns, apps, appStates) {
  var connList = Array.isArray(conns) ? conns : []
  var appList = Array.isArray(apps) ? apps : []
  var states = appStates || {}

  /** @type {Array<NmRow|AppRow>} */
  var nmConnected = []
  /** @type {Array<NmRow|AppRow>} */
  var nmAvailable = []
  for (var i = 0; i < connList.length; i++) {
    var c = connList[i]
    if (!c || (c.type !== "vpn" && c.type !== "wireguard")) continue
    var nmRow = {
      key: c.uuid,
      kind: "nm",
      name: c.name,
      glyph: String.fromCodePoint(VPN_GLYPH),
      label: c.name,
      detail: typeLabel(c, null)
    }
    if (c.active && c.state === "activated") nmConnected.push(nmRow)
    else nmAvailable.push(nmRow)
  }

  /** @type {Array<NmRow|AppRow>} */
  var appConnected = []
  /** @type {Array<NmRow|AppRow>} */
  var appAvailable = []
  for (var j = 0; j < appList.length; j++) {
    var a = appList[j]
    if (!a || typeof a.name !== "string" || !a.name) continue
    var appRow = {
      key: "app:" + a.name,
      kind: "app",
      name: a.name,
      glyph: String.fromCodePoint(APP_GLYPH),
      label: typeof a.label === "string" && a.label ? a.label : a.name
    }
    if (states[a.name] === "connected") appConnected.push(appRow)
    else appAvailable.push(appRow)
  }

  nmConnected.sort(compareByName)
  nmAvailable.sort(compareByName)
  appConnected.sort(compareByName)
  appAvailable.sort(compareByName)

  return {
    connected: nmConnected.concat(appConnected),
    available: nmAvailable.concat(appAvailable)
  }
}

/**
 * Formats a duration for a connected row's uptime.
 * @param {number|undefined} ms - the duration, in milliseconds
 * @returns {string} "under a minute", "N min", or "H h M min"
 */
function uptimeText(ms) {
  var n = Number(ms)
  if (!isFinite(n) || n < 60000) return "under a minute"
  var totalMinutes = Math.floor(n / 60000)
  if (totalMinutes < 60) return totalMinutes + " min"
  var hours = Math.floor(totalMinutes / 60)
  var minutes = totalMinutes % 60
  return hours + " h " + minutes + " min"
}

/**
 * Strips any newline so a secret can never smuggle extra stdin lines (such
 * as a second `vpn.secrets.*` key) into the connect command.
 * @param {string|undefined} value - the raw password or 2FA code
 * @returns {string} the value with `\r` and `\n` removed
 */
function sanitizeSecret(value) {
  return String(value || "").replace(/[\r\n]/g, "")
}

/**
 * The secrets text written to nmcli's stdin (`passwd-file /dev/stdin`).
 * `"append"` (the default for anything other than `"challenge"`) appends the
 * 2FA code to the password, the WatchGuard / RADIUS convention; `"challenge"`
 * sends it as OpenVPN's separate static-challenge secret, omitted when there
 * is no code. Newlines inside the password or code are stripped first, so
 * neither can inject an extra secrets line.
 * @param {string|undefined} password - the password
 * @param {string|undefined} code - the optional 2FA code
 * @param {string|undefined} mode - "append" or "challenge"
 * @returns {string} the stdin text, always ending in `\n`
 */
function secretsStdin(password, code, mode) {
  var pw = sanitizeSecret(password)
  var code2 = sanitizeSecret(code)
  if (mode === "challenge") {
    var out = "vpn.secrets.password:" + pw + "\n"
    if (code2 !== "") out += "vpn.secrets.challenge-response:" + code2 + "\n"
    return out
  }
  return "vpn.secrets.password:" + pw + code2 + "\n"
}

/**
 * Whether nmcli's stderr says a non-interactive connect needs secrets it
 * wasn't given.
 * @param {string|undefined} stderr - the failed `nmcli connection up`'s stderr
 * @returns {boolean} true when secrets are needed
 */
function needsSecrets(stderr) {
  var s = String(stderr || "").toLowerCase()
  return (
    s.indexOf("secrets were required") !== -1 ||
    s.indexOf("no secrets") !== -1 ||
    s.indexOf("passwords or encryption keys are required") !== -1
  )
}

/**
 * Whether nmcli's stderr says the connect failed because of authentication
 * (missing secrets, or secrets it was given being rejected), the case that
 * reopens the prompt rather than just showing a generic failure.
 * @param {string|undefined} stderr - the failed `nmcli connection up`'s stderr
 * @returns {boolean} true on any authentication failure
 */
function isAuthFailure(stderr) {
  if (needsSecrets(stderr)) return true
  return (
    String(stderr || "")
      .toLowerCase()
      .indexOf("auth") !== -1
  )
}

/**
 * The nmcli argv to bring a VPN profile up.
 * @param {string} uuid - the profile's uuid
 * @param {boolean} withSecrets - whether to pass secrets on stdin
 * @returns {string[]} the argv; secrets themselves never appear in it
 */
function connectCommand(uuid, withSecrets) {
  if (withSecrets)
    return ["nmcli", "--wait", "60", "connection", "up", "uuid", uuid, "passwd-file", "/dev/stdin"]
  return ["nmcli", "--wait", "30", "connection", "up", "uuid", uuid]
}

/**
 * The nmcli argv to take a VPN profile down.
 * @param {string} uuid - the profile's uuid
 * @returns {string[]} the argv
 */
function disconnectCommand(uuid) {
  return ["nmcli", "--wait", "20", "connection", "down", "uuid", uuid]
}

/**
 * The status text shown in a row's detail while connecting, disconnecting,
 * or after a failure.
 * @param {string} phase - "connecting", "disconnecting", "failedUp", "failedDown" or "failedOpen"
 * @param {number|undefined} waitedMs - how long "connecting" has been waiting, in milliseconds
 * @returns {string} the status text, or "" for an unknown phase
 */
function statusText(phase, waitedMs) {
  var ms = Number(waitedMs) || 0
  if (phase === "connecting") return ms >= 5000 ? "Connecting… approve on phone" : "Connecting…"
  if (phase === "disconnecting") return "Disconnecting…"
  if (phase === "failedUp") return "Couldn't connect"
  if (phase === "failedDown") return "Couldn't disconnect"
  if (phase === "failedOpen") return "Couldn't open"
  return ""
}

/**
 * The bar icon's state. A recent failure (connect, disconnect, open, or an
 * unexpected drop) wins over whatever else is up, so the icon still flags it
 * even while another VPN stays connected.
 * @param {boolean} anyUp - whether any VPN (NetworkManager or own-app) is up
 * @param {boolean} failedRecently - whether a failure happened within the last 4 s
 * @returns {"idle"|"up"|"alert"} the icon state
 */
function iconState(anyUp, failedRecently) {
  if (failedRecently) return "alert"
  return anyUp ? "up" : "idle"
}

/**
 * The header's connection-count caption.
 * @param {number|undefined} nUp - how many VPNs are connected
 * @param {number|undefined} nTotal - how many VPNs there are in total
 * @returns {string} "Not connected", or "N of M connected"
 */
function headerCaption(nUp, nTotal) {
  var up = Math.max(0, Math.floor(Number(nUp) || 0))
  var total = Math.max(0, Math.floor(Number(nTotal) || 0))
  if (up <= 0) return "Not connected"
  return up + " of " + total + " connected"
}

/**
 * The key-hint line for the cursor's section and the kind of row it's on,
 * saying what Enter does there (as Network's `keyHint` does for its
 * sections): an own-app row always opens its app; a NetworkManager row
 * connects from Available or disconnects from Connected.
 * @param {string|undefined} section - the cursor's section ("connected" or "available")
 * @param {string|undefined} rowKind - the cursor's row kind ("nm" or "app")
 * @returns {string} the hint
 */
function keyHint(section, rowKind) {
  if (rowKind === "app") return "↑↓ move · enter open app · tab next"
  if (section === "connected") return "↑↓ move · enter disconnect · tab next"
  return "↑↓ move · enter connect · tab next"
}

if (typeof module !== "undefined")
  module.exports = {
    splitTerse: splitTerse,
    parseVpnConnections: parseVpnConnections,
    parseSession: parseSession,
    typeLabel: typeLabel,
    vpnRows: vpnRows,
    uptimeText: uptimeText,
    secretsStdin: secretsStdin,
    needsSecrets: needsSecrets,
    isAuthFailure: isAuthFailure,
    connectCommand: connectCommand,
    disconnectCommand: disconnectCommand,
    statusText: statusText,
    iconState: iconState,
    headerCaption: headerCaption,
    keyHint: keyHint
  }
