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

/** @type {number} the glyph for an own-app VPN row (MDI "open in new") */
var APP_GLYPH = 0xf03cc

/**
 * One parsed VPN or WireGuard connection, from
 * `nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,STATE connection show`.
 * @typedef {{name: string, uuid: string, type: string, device: string, active: boolean, state: string}} VpnConnection
 */

/**
 * A connection's session fields, from `nmcli -t -f
 * IP4.ADDRESS,vpn.data,vpn.service-type,wireguard.peers connection show uuid <u>`
 * (see `sessionCommand`).
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
 * An `IP4.ADDRESS[n]` value with its `/prefix` suffix dropped.
 * @param {string|undefined} value - the address, as `parseNamedFields` returns it
 * @returns {string} the address without its prefix, or "" when there is none
 */
function stripPrefix(value) {
  var s = String(value || "").trim()
  if (!s) return ""
  var slash = s.indexOf("/")
  return slash === -1 ? s : s.substring(0, slash)
}

/**
 * Splits one `nmcli -t -f <names> ... show` line into its field name and raw
 * value, on the first unescaped `:` only (unlike `splitTerse`, which splits
 * every unescaped `:` into separate fields). Past that first colon nmcli does
 * not escape further colons in this named-field mode (confirmed against a
 * real profile: `vpn.data`'s `remote = host:port` comes through with its
 * colon intact), so the value is taken verbatim to the end of the line.
 * @param {string} line - one line of the command's stdout
 * @returns {{name: string, value: string}|null} the field, or null when the line has no unescaped colon
 */
function splitNamedField(line) {
  var s = String(line || "")
  for (var i = 0; i < s.length; i++) {
    var c = s[i]
    if (c === "\\" && i + 1 < s.length && (s[i + 1] === ":" || s[i + 1] === "\\")) {
      i++
      continue
    }
    if (c === ":") return { name: s.substring(0, i), value: s.substring(i + 1) }
  }
  return null
}

/**
 * Parses `nmcli -t -f <names> ... connection show`-style output: one
 * requested property per line as `name:value` (or `name[n]:value` for a
 * multi-valued property such as `IP4.ADDRESS`), with a property that
 * doesn't apply to this connection (an inactive one's `IP4.ADDRESS`, a
 * non-WireGuard one's `wireguard.peers`) omitted entirely rather than
 * printed empty (confirmed against a real, inactive OpenVPN profile, whose
 * `-t -f IP4.ADDRESS,vpn.data,vpn.service-type,wireguard.peers` output was
 * only 2 lines, not 4). Keeps each base name's FIRST line only, so an
 * indexed property's `[1]` always wins over its `[2]`.
 * @param {string|undefined} text - the command's stdout
 * @returns {Record<string, string>} base field name (index suffix stripped) to its first value
 */
function parseNamedFields(text) {
  var lines = String(text || "").split("\n")
  /** @type {Record<string, string>} */
  var out = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var field = splitNamedField(line)
    if (!field) continue
    var baseName = field.name.replace(/\[\d+\]$/, "")
    if (!Object.prototype.hasOwnProperty.call(out, baseName)) out[baseName] = field.value
  }
  return out
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
 * The first WireGuard peer's endpoint host (port stripped). `peersLine` is
 * already the first peer's own `key = value, key = value` attributes
 * (`parseNamedFields` keeps only `wireguard.peers[1]`, the first index), so
 * this just reads its `endpoint` key. There's no real WireGuard profile on
 * this machine to confirm a peer's inner shape against (unlike `vpn.data`,
 * captured from a real OpenVPN profile below); it's constructed from the
 * same `key = value` convention nmcli uses for `vpn.data` (see the task
 * report).
 * @param {string|undefined} peersLine - the first peer's attributes (`wireguard.peers[1]`'s value)
 * @returns {string} the peer's endpoint host, or "" when there is none
 */
function firstPeerHost(peersLine) {
  var map = parseKeyValueList(peersLine)
  var endpoint = map.endpoint || ""
  if (!endpoint) return ""
  var colon = endpoint.lastIndexOf(":")
  return colon === -1 ? endpoint : endpoint.substring(0, colon)
}

/**
 * The nmcli argv that reads a connection's session fields (fed to
 * `parseSession`).
 * @param {string} uuid - the profile's uuid
 * @returns {string[]} the argv
 */
function sessionCommand(uuid) {
  return [
    "nmcli",
    "-t",
    "-f",
    "IP4.ADDRESS,vpn.data,vpn.service-type,wireguard.peers",
    "connection",
    "show",
    "uuid",
    uuid
  ]
}

/**
 * Parses a connection's session fields from `sessionCommand`'s `nmcli -t -f
 * IP4.ADDRESS,vpn.data,vpn.service-type,wireguard.peers connection show uuid
 * <u>` (named fields, not `-g`: real nmcli output for a multi-property `-g`
 * request on one `connection show` target is NOT one line per requested
 * field in request order: an inapplicable property's line is omitted
 * entirely, which silently shifts every later field. Named `-t -f` output
 * carries each property's own name, immune to that shift).
 * @param {string|undefined} text - the command's stdout
 * @returns {VpnSession} the IP, server and VPN type
 */
function parseSession(text) {
  var fields = parseNamedFields(text)
  var vpnDataLine = fields["vpn.data"] || ""
  var serviceTypeLine = fields["vpn.service-type"] || ""
  var peersLine = fields["wireguard.peers"] || ""

  var vpnType = vpnTypeFromServiceType(serviceTypeLine, peersLine)
  var server = ""
  if (vpnType === "OpenVPN") server = vpnDataValue(vpnDataLine, "remote")
  else if (vpnType === "OpenConnect") server = vpnDataValue(vpnDataLine, "gateway")
  else if (vpnType === "WireGuard") server = firstPeerHost(peersLine)

  return { ip: stripPrefix(fields["IP4.ADDRESS"]), server: server, vpnType: vpnType }
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
 * reopens the prompt rather than just showing a generic failure. Requires
 * the full "authentication failed" phrase, not a bare "auth": that alone
 * also matches unrelated nmcli/NetworkManager noise such as "Auth dialog
 * failed to open", "HTTP proxy auth file" or a "PolicyKit Authentication
 * Agent" log line, none of which mean the VPN's own secrets were rejected.
 * @param {string|undefined} stderr - the failed `nmcli connection up`'s stderr
 * @returns {boolean} true on any authentication failure
 */
function isAuthFailure(stderr) {
  if (needsSecrets(stderr)) return true
  return (
    String(stderr || "")
      .toLowerCase()
      .indexOf("authentication failed") !== -1
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

// --- Panel wiring rules (Panel.qml) -------------------------------------------

/**
 * A row keyed for the view: `{key, kind, name, glyph, label}`, `label`
 * being the detail line under the name (the type, or the app's label).
 * @typedef {{key: string, kind: string, name: string, glyph: string, label: string}} ViewRow
 */

/**
 * The username stored in a profile's `vpn.data` (`username = ...`), read
 * from `sessionCommand`'s output, for the prompt's read-only line.
 * @param {string|undefined} text - `sessionCommand`'s stdout
 * @returns {string} the username, or "" when the profile has none
 */
function parseUsername(text) {
  return vpnDataValue(parseNamedFields(text)["vpn.data"], "username")
}

/**
 * The view rows for one section: NetworkManager rows get their type as the
 * detail label (`typeLabel` with the profile's session when it's known, so
 * "OpenVPN" rather than the generic "VPN"); app rows keep their label.
 * @param {Array<NmRow|AppRow>|undefined} rows - one of `vpnRows`' lists
 * @param {VpnConnection[]|undefined} conns - from `parseVpnConnections`
 * @param {Record<string, VpnSession>|undefined} sessions - uuid to session, as from `parseSession`
 * @returns {ViewRow[]} the rows, in the same order
 */
function viewRows(rows, conns, sessions) {
  var list = Array.isArray(rows) ? rows : []
  var connList = Array.isArray(conns) ? conns : []
  var known = sessions || {}
  /** @type {ViewRow[]} */
  var out = []
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    var label = r.label
    if (r.kind === "nm") {
      var conn = null
      for (var j = 0; j < connList.length; j++) if (connList[j].uuid === r.key) conn = connList[j]
      label = typeLabel(conn, known[r.key] || null)
    }
    out.push({ key: r.key, kind: r.kind, name: r.name, glyph: r.glyph, label: label })
  }
  return out
}

/**
 * Which connection uuids need their session fields (re)read: every profile
 * not seen before, and every one whose connected state changed since the
 * last read (its IP comes or goes). Sessions are read on change, never
 * polled.
 * @param {Record<string, boolean>|undefined} seen - uuid to whether it was connected at the last read
 * @param {VpnConnection[]|undefined} conns - the current connections
 * @returns {{fetch: string[], seen: Record<string, boolean>}} the uuids to read and the new `seen` map
 */
function sessionsToFetch(seen, conns) {
  var prev = seen || {}
  var list = Array.isArray(conns) ? conns : []
  var fetch = []
  /** @type {Record<string, boolean>} */
  var next = {}
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    var up = !!c.active && c.state === "activated"
    next[c.uuid] = up
    if (!Object.prototype.hasOwnProperty.call(prev, c.uuid) || prev[c.uuid] !== up)
      fetch.push(c.uuid)
  }
  return { fetch: fetch, seen: next }
}

/**
 * The argv that reads links and running processes for the own-app VPNs:
 * `ip -j addr`, a `---` line, then each configured process name that
 * `pgrep -x` finds, one per line (printed in full). `pgrep -x` matches the
 * kernel's process name, which is cut to 15 bytes, so a longer name is
 * matched on its first 15 bytes (`LC_ALL=C` makes `${p:0:15}` count bytes,
 * not characters). The names travel as positional arguments to
 * `bash -c`, never interpolated into the script.
 * @param {string[]|undefined} processNames - the apps' `detect.process` names
 * @returns {string[]} the argv
 */
function linkCommand(processNames) {
  var names = Array.isArray(processNames) ? processNames : []
  return [
    "bash",
    "-c",
    'export LC_ALL=C; ip -j addr 2>/dev/null || echo "[]"; echo; echo ---; for p; do pgrep -x -- "${p:0:15}" >/dev/null 2>&1 && printf \'%s\\n\' "$p"; done; exit 0',
    "_"
  ].concat(names.map(String))
}

/**
 * Parses `linkCommand`'s output into the links (`ip -j addr`) and the
 * running process names. Anything unparsable reads as no links.
 * @param {string|undefined} text - the command's stdout
 * @returns {{links: Array<Record<string, any>>, procs: string[]}} the links and running process names
 */
function parseLinkOutput(text) {
  var s = String(text || "")
  var cut = s.indexOf("\n---\n")
  var head = cut === -1 ? s : s.substring(0, cut)
  var tail = cut === -1 ? "" : s.substring(cut + 5)
  var links = []
  try {
    var parsed = JSON.parse(head.trim() || "[]")
    if (Array.isArray(parsed)) links = parsed
  } catch (e) {
    links = []
  }
  var procs = tail.split("\n").filter(function (line) {
    return line !== ""
  })
  return { links: links, procs: procs }
}

/**
 * The first IPv4 address on interface IFNAME in `links` (`ip -j addr`).
 * @param {Array<Record<string, any>>|undefined} links - parsed `ip -j addr`
 * @param {string|undefined} ifname - the interface
 * @returns {string} the address, or "" when there is none
 */
function linkAddress(links, ifname) {
  var list = Array.isArray(links) ? links : []
  if (!ifname) return ""
  for (var i = 0; i < list.length; i++) {
    var l = list[i]
    if (!l || l.ifname !== ifname || !Array.isArray(l.addr_info)) continue
    for (var j = 0; j < l.addr_info.length; j++) {
      var a = l.addr_info[j]
      if (a && a.family === "inet" && a.local) return String(a.local)
    }
  }
  return ""
}

/**
 * The interface carrying IPv4 address IP in `links`: how a NetworkManager
 * VPN's tunnel is found (nmcli's DEVICE column names the parent link for
 * plugin VPNs, not the tunnel).
 * @param {Array<Record<string, any>>|undefined} links - parsed `ip -j addr`
 * @param {string|undefined} ip - the session's IPv4 address
 * @returns {string} the interface name, or "" when no link carries it
 */
function interfaceForAddress(links, ip) {
  var list = Array.isArray(links) ? links : []
  if (!ip) return ""
  for (var i = 0; i < list.length; i++) {
    var l = list[i]
    if (!l || typeof l.ifname !== "string" || !Array.isArray(l.addr_info)) continue
    for (var j = 0; j < l.addr_info.length; j++) {
      var a = l.addr_info[j]
      if (a && a.family === "inet" && a.local === ip) return l.ifname
    }
  }
  return ""
}

/**
 * The interface behind each connected row, for its traffic graph: a
 * NetworkManager row's tunnel (the link carrying its session IP, or a
 * WireGuard profile's own device), an app row's matched interface. Rows
 * without one are left out.
 * @param {ViewRow[]|undefined} connected - the Connected rows
 * @param {VpnConnection[]|undefined} conns - from `parseVpnConnections`
 * @param {Record<string, VpnSession>|undefined} sessions - uuid to session
 * @param {Array<Record<string, any>>|undefined} links - parsed `ip -j addr`
 * @param {Record<string, string>|undefined} appInterfaces - app name to its matched interface (`VpnApps.appInterface`)
 * @returns {Record<string, string>} row key to interface name
 */
function rowInterfaces(connected, conns, sessions, links, appInterfaces) {
  var rows = Array.isArray(connected) ? connected : []
  var connList = Array.isArray(conns) ? conns : []
  var known = sessions || {}
  var appIfaces = appInterfaces || {}
  /** @type {Record<string, string>} */
  var out = {}
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    var iface
    if (r.kind === "app") {
      iface = appIfaces[r.name] || ""
    } else {
      var s = known[r.key]
      iface = interfaceForAddress(links, s ? s.ip : "")
      if (!iface) {
        for (var j = 0; j < connList.length; j++)
          if (connList[j].uuid === r.key && connList[j].type === "wireguard")
            iface = connList[j].device || ""
      }
    }
    if (iface) out[r.key] = iface
  }
  return out
}

/**
 * The argv that reads each interface's byte counters
 * (`/sys/class/net/<iface>/statistics/{rx,tx}_bytes`) as `iface rx tx`
 * lines; the names travel as positional arguments, never interpolated.
 * @param {string[]|undefined} ifaces - the interfaces
 * @returns {string[]} the argv
 */
function countersCommand(ifaces) {
  var names = Array.isArray(ifaces) ? ifaces : []
  return [
    "bash",
    "-c",
    'for i; do d="/sys/class/net/$i/statistics"; r=$(cat "$d/rx_bytes" 2>/dev/null) || continue; t=$(cat "$d/tx_bytes" 2>/dev/null) || continue; printf \'%s %s %s\\n\' "$i" "$r" "$t"; done; exit 0',
    "_"
  ].concat(names.map(String))
}

/**
 * Parses `countersCommand`'s output.
 * @param {string|undefined} text - the command's stdout
 * @returns {Record<string, {rx: number, tx: number}>} interface to its byte counters
 */
function parseCounters(text) {
  var lines = String(text || "").split("\n")
  /** @type {Record<string, {rx: number, tx: number}>} */
  var out = {}
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length !== 3) continue
    var rx = Number(f[1])
    var tx = Number(f[2])
    if (!isFinite(rx) || !isFinite(tx)) continue
    out[f[0]] = { rx: rx, tx: tx }
  }
  return out
}

/**
 * Bytes per second per interface between two counter readings SECONDS
 * apart. An interface missing from either reading, or whose counters went
 * backwards (a recreated tunnel), is left out.
 * @param {Record<string, {rx: number, tx: number}>|null|undefined} prev - the earlier reading
 * @param {Record<string, {rx: number, tx: number}>|null|undefined} next - the later reading
 * @param {number} seconds - the time between them
 * @returns {Record<string, {rx: number, tx: number}>} interface to its rates
 */
function counterRates(prev, next, seconds) {
  /** @type {Record<string, {rx: number, tx: number}>} */
  var out = {}
  var dt = Number(seconds)
  if (!prev || !next || !(dt > 0)) return out
  for (var iface in next) {
    if (!Object.prototype.hasOwnProperty.call(next, iface)) continue
    var a = prev[iface]
    var b = next[iface]
    if (!a || b.rx < a.rx || b.tx < a.tx) continue
    out[iface] = { rx: (b.rx - a.rx) / dt, tx: (b.tx - a.tx) / dt }
  }
  return out
}

/**
 * When each connected key came up: a key keeps its time while it stays
 * connected, a newly connected one gets NOW, and one connected at the
 * panel's first read gets -1 ("since before open", as Aranea didn't see it
 * come up). Keys no longer connected are dropped, so the next connect
 * starts afresh.
 * @param {Record<string, number>|undefined} since - key to when it came up (ms), or -1
 * @param {string[]|undefined} connectedKeys - the keys connected now
 * @param {number} now - the current time (ms)
 * @param {boolean} firstRead - whether this is the panel's first read
 * @returns {Record<string, number>} the new map
 */
function trackUptime(since, connectedKeys, now, firstRead) {
  var prev = since || {}
  var keys = Array.isArray(connectedKeys) ? connectedKeys : []
  /** @type {Record<string, number>} */
  var out = {}
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    if (Object.prototype.hasOwnProperty.call(prev, k)) out[k] = prev[k]
    else out[k] = firstRead ? -1 : now
  }
  return out
}

/**
 * A connected row's uptime text.
 * @param {number|undefined} since - when it came up (ms), or -1 when it was up before the panel's first read
 * @param {number} now - the current time (ms)
 * @returns {string} "since before open", or `uptimeText`'s duration ("" when unknown)
 */
function upText(since, now) {
  if (typeof since !== "number") return ""
  if (since < 0) return "since before open"
  return uptimeText(now - since)
}

/**
 * The session details the view shows under each connected row:
 * NetworkManager rows their session's IP and server, app rows the address
 * on their interface; every row its uptime.
 * @param {ViewRow[]|undefined} connected - the Connected rows
 * @param {Record<string, VpnSession>|undefined} sessions - uuid to session
 * @param {Record<string, string>|undefined} appIps - app name to the address on its interface
 * @param {Record<string, number>|undefined} since - from `trackUptime`
 * @param {number} now - the current time (ms)
 * @returns {Record<string, {ip: string, server: string, up: string}>} row key to its details
 */
function sessionDetails(connected, sessions, appIps, since, now) {
  var rows = Array.isArray(connected) ? connected : []
  var known = sessions || {}
  var ips = appIps || {}
  var ups = since || {}
  /** @type {Record<string, {ip: string, server: string, up: string}>} */
  var out = {}
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    var s = r.kind === "nm" ? known[r.key] : null
    out[r.key] = {
      ip: r.kind === "app" ? ips[r.name] || "" : s ? s.ip : "",
      server: s ? s.server : "",
      up: upText(ups[r.key], now)
    }
  }
  return out
}

/**
 * The per-row status the view shows: the running action's row breathes
 * ("Connecting…", "Connecting… approve on phone" after 5 s,
 * "Disconnecting…"); a failed one reads urgent for its 4 s.
 * @param {{key: string, phase: string, waited: number}|null|undefined} action - the running action
 * @param {{key: string, phase: string}|null|undefined} failure - the recent failure
 * @returns {Record<string, {text: string, busy: boolean, failed: boolean}>} row key to its status
 */
function statusMap(action, failure) {
  /** @type {Record<string, {text: string, busy: boolean, failed: boolean}>} */
  var out = {}
  if (failure && failure.key)
    out[failure.key] = { text: statusText(failure.phase, 0), busy: false, failed: true }
  if (action && action.key)
    out[action.key] = { text: statusText(action.phase, action.waited), busy: true, failed: false }
  return out
}

/**
 * What a finished `nmcli connection up` means: `ok`; `prompt` when a
 * connect without secrets needs them (open the prompt); `wrong` when
 * secrets given on stdin were rejected (reopen it, "Wrong password or
 * code"); `failed` otherwise ("Couldn't connect").
 * @param {number} exitCode - nmcli's exit code
 * @param {string|undefined} stderr - its stderr
 * @param {boolean} withSecrets - whether secrets were passed on stdin
 * @returns {"ok"|"prompt"|"wrong"|"failed"} the outcome
 */
function connectOutcome(exitCode, stderr, withSecrets) {
  if (exitCode === 0) return "ok"
  if (!withSecrets && needsSecrets(stderr)) return "prompt"
  if (withSecrets && isAuthFailure(stderr)) return "wrong"
  return "failed"
}

/**
 * The keys of rows that were connected and are now listed as available
 * without being turned off here: a VPN that dropped. Rows that vanished
 * entirely (a deleted profile, an app removed from the config,
 * NetworkManager stopping) aren't drops.
 * @param {string[]|undefined} prevKeys - the keys connected at the last read
 * @param {ViewRow[]|undefined} connected - the Connected rows now
 * @param {ViewRow[]|undefined} available - the Available rows now
 * @param {string[]|undefined} exempt - keys being turned off from the dropdown
 * @returns {string[]} the dropped keys
 */
function droppedKeys(prevKeys, connected, available, exempt) {
  var prev = Array.isArray(prevKeys) ? prevKeys : []
  var up = (Array.isArray(connected) ? connected : []).map(function (r) {
    return r.key
  })
  var down = (Array.isArray(available) ? available : []).map(function (r) {
    return r.key
  })
  var skip = Array.isArray(exempt) ? exempt : []
  return prev.filter(function (k) {
    return up.indexOf(k) === -1 && down.indexOf(k) !== -1 && skip.indexOf(k) === -1
  })
}

/**
 * How often the connection list is read: every 2 s while open, every 5 s
 * while closed, and not at all (0) while closed with no NetworkManager VPN
 * profiles and no apps (a slow re-check notices a newly imported profile).
 * @param {boolean} opened - whether the dropdown is open
 * @param {boolean} hasProfiles - whether NetworkManager has VPN profiles
 * @param {boolean} hasApps - whether the apps file lists any app
 * @returns {number} the interval in ms, or 0 for no polling
 */
function pollInterval(opened, hasProfiles, hasApps) {
  if (opened) return 2000
  return hasProfiles || hasApps ? 5000 : 0
}

/**
 * The OTP mode for profile NAME from the apps file's `profiles` map.
 * @param {Record<string, {otp: string}>|undefined} profiles - the parsed profiles
 * @param {string} name - the NetworkManager profile name
 * @returns {string} "challenge" or "append"
 */
function otpMode(profiles, name) {
  var p = profiles && Object.prototype.hasOwnProperty.call(profiles, name) ? profiles[name] : null
  return p && p.otp === "challenge" ? "challenge" : "append"
}

/**
 * The empty-state text: "NetworkManager isn't running" when nmcli failed,
 * "No VPNs yet" with no rows at all, else nothing.
 * @param {boolean} nmOk - whether the last connection read succeeded
 * @param {number} rowCount - how many rows there are (profiles and apps)
 * @returns {string} the text, or ""
 */
function emptyText(nmOk, rowCount) {
  if (rowCount > 0) return ""
  return nmOk ? "No VPNs yet" : "NetworkManager isn't running"
}

/**
 * The key hint: the prompt's own keys while it's open, the cursor row's
 * Enter action (`keyHint`) while there are rows, else Tab and Esc.
 * @param {boolean} promptOpen - whether the credential prompt is open
 * @param {string} section - the cursor's section
 * @param {string} rowKind - the cursor row's kind ("nm" or "app")
 * @param {boolean} hasRows - whether any row is shown
 * @returns {string} the hint
 */
function hintFor(promptOpen, section, rowKind, hasRows) {
  if (promptOpen) return "enter connect · esc cancel"
  if (!hasRows) return "tab next · esc close"
  return keyHint(section, rowKind)
}

/**
 * Moves a flat cursor (Connected rows, then Available) by DY, clamped.
 * @param {number} flat - the current flat index
 * @param {number} dy - the move (-1 up, 1 down)
 * @param {number} total - how many rows there are
 * @returns {number} the new index, or -1 with no rows
 */
function moveFlat(flat, dy, total) {
  if (!(total > 0)) return -1
  var n = (Math.floor(Number(flat)) || 0) + (Number(dy) || 0)
  return Math.max(0, Math.min(total - 1, n))
}

/**
 * The view's cursor place for flat index FLAT.
 * @param {number} flat - the flat index (Connected rows first)
 * @param {number} nConnected - how many Connected rows there are
 * @returns {{section: string, index: number}} the section and its row
 */
function cursorPlace(flat, nConnected) {
  if (flat < nConnected) return { section: "connected", index: flat }
  return { section: "available", index: flat - nConnected }
}

/**
 * Reads the `showcaseFixture` IPC call's rows: display-only stand-ins, so a
 * README capture works on a machine without VPNs. Each entry is `{name,
 * label, kind ("nm" or "app"), connected, ip, server, upMinutes}`; keys are
 * `fixture:N`, never a real uuid.
 * @param {string|undefined} json - a JSON array of entries
 * @returns {{connected: ViewRow[], available: ViewRow[], sessions: Record<string, {ip: string, server: string, up: string}>}|null} the rows and their sessions, or null when the input isn't an array of entries with names
 */
function parseFixture(json) {
  var parsed
  try {
    parsed = JSON.parse(String(json))
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed)) return null
  /** @type {ViewRow[]} */
  var connected = []
  /** @type {ViewRow[]} */
  var available = []
  /** @type {Record<string, {ip: string, server: string, up: string}>} */
  var sessions = {}
  for (var i = 0; i < parsed.length; i++) {
    var e = parsed[i]
    if (!e || typeof e !== "object" || typeof e.name !== "string" || !e.name) return null
    var app = e.kind === "app"
    var key = "fixture:" + i
    var row = {
      key: key,
      kind: app ? "app" : "nm",
      name: e.name,
      glyph: String.fromCodePoint(app ? APP_GLYPH : VPN_GLYPH),
      label: typeof e.label === "string" && e.label ? e.label : app ? e.name : "VPN"
    }
    if (e.connected === true) {
      connected.push(row)
      sessions[key] = {
        ip: typeof e.ip === "string" ? e.ip : "",
        server: typeof e.server === "string" ? e.server : "",
        up: typeof e.upMinutes === "number" ? uptimeText(e.upMinutes * 60000) : ""
      }
    } else available.push(row)
  }
  return { connected: connected, available: available, sessions: sessions }
}

/**
 * The argv that checks an app's `open` binary is on PATH before it's run
 * detached (`command -v`); the name travels as a positional argument.
 * @param {string} bin - the binary (the app's `open[0]`)
 * @returns {string[]} the argv; exit 0 when it's found
 */
function whichCommand(bin) {
  return ["bash", "-c", 'command -v -- "$1" >/dev/null 2>&1', "_", String(bin || "")]
}

/**
 * The apps config the panel applies from a `VpnApps.parseAppsConfig`
 * result: the whole file is ignored (no apps, no profiles) when it has any
 * error, so a partly invalid file never shows a partial list.
 * @param {{apps: VpnAppEntry[], profiles: Record<string, {otp: string}>, error: string}|null} parsed - the parsed file, or null when it's missing
 * @returns {{apps: VpnAppEntry[], profiles: Record<string, {otp: string}>}} what to apply
 */
function appsToApply(parsed) {
  if (!parsed || parsed.error !== "") return { apps: [], profiles: {} }
  return { apps: parsed.apps, profiles: parsed.profiles }
}

/**
 * Whether a finished action takes the prompt's typed secrets with it: only
 * a secrets connect for the row the prompt is open on. Any other action
 * finishing leaves a half-typed password alone.
 * @param {boolean} withSecrets - whether the finished action passed secrets on stdin
 * @param {string} actionKey - the row the finished action was for
 * @param {string} promptKey - the row the prompt is open on, or ""
 * @returns {boolean} true when the prompt's password and code are cleared
 */
function finishClearsSecrets(withSecrets, actionKey, promptKey) {
  return !!withSecrets && actionKey !== "" && actionKey === promptKey
}

/**
 * Whether a secrets connect may start: only with a password that's still
 * non-empty once newlines are stripped (as `secretsStdin` strips them). A
 * started nmcli is always handed this password, so an empty one is never
 * sent to the VPN server.
 * @param {string|undefined} password - the password copied from the prompt at submit
 * @returns {boolean} true when nmcli may start
 */
function canStartSecrets(password) {
  return sanitizeSecret(password) !== ""
}

if (typeof module !== "undefined")
  module.exports = {
    splitTerse: splitTerse,
    parseVpnConnections: parseVpnConnections,
    sessionCommand: sessionCommand,
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
    keyHint: keyHint,
    parseUsername: parseUsername,
    viewRows: viewRows,
    sessionsToFetch: sessionsToFetch,
    linkCommand: linkCommand,
    parseLinkOutput: parseLinkOutput,
    linkAddress: linkAddress,
    interfaceForAddress: interfaceForAddress,
    rowInterfaces: rowInterfaces,
    countersCommand: countersCommand,
    parseCounters: parseCounters,
    counterRates: counterRates,
    trackUptime: trackUptime,
    upText: upText,
    sessionDetails: sessionDetails,
    statusMap: statusMap,
    connectOutcome: connectOutcome,
    droppedKeys: droppedKeys,
    pollInterval: pollInterval,
    otpMode: otpMode,
    emptyText: emptyText,
    hintFor: hintFor,
    moveFlat: moveFlat,
    cursorPlace: cursorPlace,
    parseFixture: parseFixture,
    whichCommand: whichCommand,
    appsToApply: appsToApply,
    finishClearsSecrets: finishClearsSecrets,
    canStartSecrets: canStartSecrets
  }
