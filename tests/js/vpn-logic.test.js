// Logic contract for VpnLogic.js: parsing nmcli's VPN connection list and
// per-connection session fields, building the Connected/Available rows,
// the secrets sent to nmcli on stdin, auth-failure detection, connect/
// disconnect argv, and the small text helpers. No QML, no I/O; run with
// `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.vpn/VpnLogic.js"))

// splitTerse's own contract lives in tests/js/nmcli-terse.test.js
// (NmcliTerse.js); VpnLogic.js gets a generated copy of it
// (tools/js-facade-generator.mjs) and exercises it through
// parseVpnConnections below.

// --- parseVpnConnections ------------------------------------------------------

test("parseVpnConnections keeps only vpn and wireguard types", () => {
  const text = [
    "Office (Firebox):uuid-1:vpn:tun0:yes:activated",
    "home-wg:uuid-2:wireguard:wg0:no:",
    "Wired connection 1:uuid-3:802-3-ethernet:eth0:yes:activated",
    "Office Wi-Fi:uuid-4:802-11-wireless:wlan0:no:"
  ].join("\n")
  const result = logic.parseVpnConnections(text)
  assert.deepEqual(result, [
    {
      name: "Office (Firebox)",
      uuid: "uuid-1",
      type: "vpn",
      device: "tun0",
      active: true,
      state: "activated"
    },
    { name: "home-wg", uuid: "uuid-2", type: "wireguard", device: "wg0", active: false, state: "" }
  ])
})

test("parseVpnConnections unescapes \\: within a NAME field", () => {
  const text = "Client A\\: EU:uuid-9:vpn:tun1:no:"
  const result = logic.parseVpnConnections(text)
  assert.equal(result[0].name, "Client A: EU")
})

test("parseVpnConnections ignores blank lines and short/malformed lines", () => {
  const text = ["", "too:few:fields", "Good:uuid-5:vpn:tun2:yes:activating"].join("\n")
  const result = logic.parseVpnConnections(text)
  assert.deepEqual(result, [
    { name: "Good", uuid: "uuid-5", type: "vpn", device: "tun2", active: true, state: "activating" }
  ])
})

test("parseVpnConnections on missing/undefined text returns [] rather than throwing", () => {
  assert.deepEqual(logic.parseVpnConnections(undefined), [])
  assert.deepEqual(logic.parseVpnConnections(""), [])
})

// --- sessionCommand --------------------------------------------------------------

test("sessionCommand: the named-field nmcli argv parseSession expects", () => {
  assert.deepEqual(logic.sessionCommand("uuid-1"), [
    "nmcli",
    "-t",
    "-f",
    "IP4.ADDRESS,vpn.data,vpn.service-type,wireguard.peers",
    "connection",
    "show",
    "uuid",
    "uuid-1"
  ])
})

// --- parseSession --------------------------------------------------------------
//
// `nmcli -g` is NOT one line per requested field in request order: an
// inapplicable property (an inactive connection's IP4.ADDRESS, a non-
// WireGuard connection's wireguard.peers) is omitted entirely, silently
// shifting every later field. Verified live, read-only, against this
// machine's real (inactive) OpenVPN profile "client" with
// `nmcli -t -f IP4.ADDRESS,vpn.data,vpn.service-type,wireguard.peers
// connection show uuid <uuid>`: output was 2 lines (vpn.data,
// vpn.service-type), not 4 - IP4.ADDRESS (inactive) and wireguard.peers (not
// a WireGuard connection) were both missing, not blank. `-t -f` (named
// fields) avoids the shift since each line carries its own property name;
// `parseSession` is built on that instead. The `vpn.data` fixture below is
// that real profile's actual line, with the host and local paths redacted
// (`vpn.example.com`, `/home/user/...`) per the task's redaction rule -
// including, notably, a `remote` value with an unescaped `:` in it
// (`vpn.example.com:443`) and an internal `verify-x509-name` value with
// escaped commas, both reproduced verbatim from the real capture.
// `IP4.ADDRESS[1]` (an active connection's indexed field name) was
// confirmed live too, against an active Wi-Fi connection's IP; the
// WireGuard fixtures remain constructed (no real WireGuard profile exists
// on this machine) from the same `key = value` convention `vpn.data` uses.

const REAL_OPENVPN_VPN_DATA =
  "vpn.data:auth = SHA256, ca = /home/user/.config/openvpn/mobile-vpn/ca.crt, " +
  "cert = /home/user/.config/openvpn/mobile-vpn/client.crt, challenge-response-flags = 2, " +
  "cipher = AES-256-CBC, connection-type = password-tls, dev = tun, float = yes, " +
  "key = /home/user/.config/openvpn/mobile-vpn/client.pem, password-flags = 1, ping = 10, " +
  "ping-restart = 60, proto-tcp = yes, remote = vpn.example.com:443, reneg-seconds = 28800, " +
  "tls-version-min = 1.2, verify-x509-name = subject:O=WatchGuard_Technologies\\, OU=Fireware\\, " +
  "CN=Fireware SSLVPN Server"

test("parseSession reads the real (redacted) inactive OpenVPN profile: no IP4.ADDRESS line at all, remote survives its own unescaped colon", () => {
  const text = [
    REAL_OPENVPN_VPN_DATA,
    "vpn.service-type:org.freedesktop.NetworkManager.openvpn"
  ].join("\n")
  assert.deepEqual(logic.parseSession(text), {
    ip: "",
    server: "vpn.example.com:443",
    vpnType: "OpenVPN"
  })
})

test("parseSession reads IP4.ADDRESS[1] (the real indexed field name for an active connection) and strips its prefix", () => {
  const text = [
    "IP4.ADDRESS[1]:192.168.0.126/24",
    REAL_OPENVPN_VPN_DATA,
    "vpn.service-type:org.freedesktop.NetworkManager.openvpn"
  ].join("\n")
  assert.equal(logic.parseSession(text).ip, "192.168.0.126")
})

test("parseSession reads an OpenConnect session: gateway as server, OpenConnect as type", () => {
  const text = [
    "vpn.data:gateway = gp.example.com, gateway-flags = 0",
    "vpn.service-type:org.freedesktop.NetworkManager.openconnect"
  ].join("\n")
  assert.deepEqual(logic.parseSession(text), {
    ip: "",
    server: "gp.example.com",
    vpnType: "OpenConnect"
  })
})

test("parseSession reads a WireGuard session: no vpn.service-type line at all, wireguard.peers[1]'s endpoint host as server", () => {
  const text = [
    "IP4.ADDRESS[1]:10.10.0.5/32",
    "wireguard.peers[1]:public-key = abc123, endpoint = 203.0.113.5:51820, allowed-ips = 0.0.0.0/0",
    "wireguard.peers[2]:public-key = def456, endpoint = 203.0.113.6:51820, allowed-ips = 0.0.0.0/0"
  ].join("\n")
  assert.deepEqual(logic.parseSession(text), {
    ip: "10.10.0.5",
    server: "203.0.113.5",
    vpnType: "WireGuard"
  })
})

test("parseSession falls back to VPN when neither vpn.service-type nor wireguard.peers is present", () => {
  const result = logic.parseSession("IP4.ADDRESS[1]:10.11.0.1/24")
  assert.equal(result.vpnType, "VPN")
  assert.equal(result.server, "")
  assert.equal(result.ip, "10.11.0.1")
})

test("parseSession on missing/empty text never throws", () => {
  assert.deepEqual(logic.parseSession(undefined), { ip: "", server: "", vpnType: "VPN" })
  assert.deepEqual(logic.parseSession(""), { ip: "", server: "", vpnType: "VPN" })
})

test("parseSession ignores a line with no unescaped colon at all, rather than throwing", () => {
  const text = [
    "garbage with no colon",
    "vpn.service-type:org.freedesktop.NetworkManager.openvpn"
  ].join("\n")
  assert.equal(logic.parseSession(text).vpnType, "OpenVPN")
})

test("parseSession's field-name split treats an escaped colon in a field name as part of the name, not a separator", () => {
  // Real nmcli field names never contain a colon, escaped or not; this only
  // exercises splitNamedField's defensive escape handling (shared with
  // splitTerse's), not a real nmcli shape.
  const text = "weird\\:name:org.freedesktop.NetworkManager.openvpn"
  const result = logic.parseSession(text)
  assert.equal(
    result.vpnType,
    "VPN",
    "the whole line is dropped: its base name is not vpn.service-type"
  )
})

// --- typeLabel -------------------------------------------------------------

test("typeLabel: a wireguard connection is always WireGuard, session or not", () => {
  assert.equal(logic.typeLabel({ type: "wireguard" }, null), "WireGuard")
  assert.equal(logic.typeLabel({ type: "wireguard" }, { vpnType: "OpenVPN" }), "WireGuard")
})

test("typeLabel: a vpn connection with a known session type uses it", () => {
  assert.equal(logic.typeLabel({ type: "vpn" }, { vpnType: "OpenVPN" }), "OpenVPN")
  assert.equal(logic.typeLabel({ type: "vpn" }, { vpnType: "OpenConnect" }), "OpenConnect")
})

test("typeLabel: a vpn connection with no session (or an unknown one) falls back to VPN", () => {
  assert.equal(logic.typeLabel({ type: "vpn" }, null), "VPN")
  assert.equal(logic.typeLabel({ type: "vpn" }, undefined), "VPN")
  assert.equal(logic.typeLabel({ type: "vpn" }, { vpnType: "VPN" }), "VPN")
  assert.equal(logic.typeLabel(null, null), "VPN")
})

// --- vpnRows -----------------------------------------------------------------

const ACTIVATED = {
  name: "Office (Firebox)",
  uuid: "uuid-1",
  type: "vpn",
  device: "tun0",
  active: true,
  state: "activated"
}
const ACTIVATING = {
  name: "Client A",
  uuid: "uuid-2",
  type: "vpn",
  device: "tun1",
  active: true,
  state: "activating"
}
const INACTIVE_WG = {
  name: "home-wg",
  uuid: "uuid-3",
  type: "wireguard",
  device: "wg0",
  active: false,
  state: ""
}

test("vpnRows: NetworkManager row shape, keyed by uuid", () => {
  const { available } = logic.vpnRows([INACTIVE_WG], [], {})
  assert.deepEqual(available, [
    {
      key: "uuid-3",
      kind: "nm",
      name: "home-wg",
      glyph: available[0].glyph,
      label: "home-wg",
      detail: "WireGuard"
    }
  ])
  assert.equal(available[0].glyph, String.fromCodePoint(0xf0582))
})

test("vpnRows: active+activated NetworkManager row is Connected", () => {
  const { connected, available } = logic.vpnRows([ACTIVATED], [], {})
  assert.equal(connected.length, 1)
  assert.equal(connected[0].key, "uuid-1")
  assert.equal(available.length, 0)
})

test("vpnRows: an activating row (active but not yet activated) stays in Available", () => {
  const { connected, available } = logic.vpnRows([ACTIVATING], [], {})
  assert.equal(connected.length, 0)
  assert.equal(available.length, 1)
  assert.equal(available[0].key, "uuid-2")
})

test('vpnRows: an own-app row is keyed "app:" + name, with no detail field', () => {
  const apps = [{ name: "Azure (Contoso)", label: "Azure VPN Client", detect: {}, open: ["x"] }]
  const { available } = logic.vpnRows([], apps, {})
  assert.deepEqual(available, [
    {
      key: "app:Azure (Contoso)",
      kind: "app",
      name: "Azure (Contoso)",
      glyph: available[0].glyph,
      label: "Azure VPN Client"
    }
  ])
  assert.ok(!Object.prototype.hasOwnProperty.call(available[0], "detail"))
})

test("vpnRows: an own-app row whose state is connected lands in Connected", () => {
  const apps = [{ name: "Azure (Contoso)", label: "Azure VPN Client", detect: {}, open: ["x"] }]
  const { connected, available } = logic.vpnRows([], apps, { "Azure (Contoso)": "connected" })
  assert.equal(connected.length, 1)
  assert.equal(connected[0].key, "app:Azure (Contoso)")
  assert.equal(available.length, 0)
})

test("vpnRows: present/absent app states stay in Available", () => {
  const apps = [{ name: "A", label: "A", detect: {}, open: ["x"] }]
  assert.equal(logic.vpnRows([], apps, { A: "present" }).available.length, 1)
  assert.equal(logic.vpnRows([], apps, { A: "absent" }).available.length, 1)
  assert.equal(logic.vpnRows([], apps, {}).available.length, 1)
})

test("vpnRows: order is NetworkManager first, then apps, then by name within each group", () => {
  const conns = [
    { name: "Zeta VPN", uuid: "z", type: "vpn", device: "", active: false, state: "" },
    { name: "Alpha VPN", uuid: "a", type: "vpn", device: "", active: false, state: "" }
  ]
  const apps = [
    { name: "Zeta App", label: "Zeta App", detect: {}, open: ["x"] },
    { name: "Alpha App", label: "Alpha App", detect: {}, open: ["x"] }
  ]
  const { available } = logic.vpnRows(conns, apps, {})
  assert.deepEqual(
    available.map((r) => r.name),
    ["Alpha VPN", "Zeta VPN", "Alpha App", "Zeta App"]
  )
})

test("vpnRows: connected rows are also ordered NetworkManager first, then apps, by name", () => {
  const conns = [
    { name: "Zeta VPN", uuid: "z", type: "vpn", device: "", active: true, state: "activated" },
    { name: "Alpha VPN", uuid: "a", type: "vpn", device: "", active: true, state: "activated" }
  ]
  const apps = [
    { name: "Zeta App", label: "Zeta App", detect: {}, open: ["x"] },
    { name: "Alpha App", label: "Alpha App", detect: {}, open: ["x"] }
  ]
  const states = { "Zeta App": "connected", "Alpha App": "connected" }
  const { connected } = logic.vpnRows(conns, apps, states)
  assert.deepEqual(
    connected.map((r) => r.name),
    ["Alpha VPN", "Zeta VPN", "Alpha App", "Zeta App"]
  )
})

test("vpnRows ignores null/malformed entries in conns and apps without throwing", () => {
  const result = logic.vpnRows(
    [null, { type: "802-11-wireless", uuid: "x", name: "n", active: false, state: "" }],
    [null, { label: "no name", detect: {}, open: [] }],
    {}
  )
  assert.deepEqual(result, { connected: [], available: [] })
})

test("vpnRows on missing conns/apps/appStates returns empty lists rather than throwing", () => {
  assert.deepEqual(logic.vpnRows(undefined, undefined, undefined), { connected: [], available: [] })
})

test("vpnRows: an app row's label falls back to its name when label is missing", () => {
  const apps = [{ name: "Plain", detect: {}, open: ["x"] }]
  const { available } = logic.vpnRows([], apps, {})
  assert.equal(available[0].label, "Plain")
})

// --- uptimeText ----------------------------------------------------------------

test('uptimeText: under a minute reads "under a minute"', () => {
  assert.equal(logic.uptimeText(0), "under a minute")
  assert.equal(logic.uptimeText(59999), "under a minute")
})

test("uptimeText: minutes only", () => {
  assert.equal(logic.uptimeText(60000), "1 min")
  assert.equal(logic.uptimeText(23 * 60000), "23 min")
  assert.equal(logic.uptimeText(59 * 60000), "59 min")
})

test("uptimeText: hours and minutes", () => {
  assert.equal(logic.uptimeText(60 * 60000), "1 h 0 min")
  assert.equal(logic.uptimeText(72 * 60000), "1 h 12 min")
})

test("uptimeText on missing/non-finite input reads as under a minute", () => {
  assert.equal(logic.uptimeText(undefined), "under a minute")
  assert.equal(logic.uptimeText(NaN), "under a minute")
  assert.equal(logic.uptimeText(-5), "under a minute")
})

// --- secretsStdin --------------------------------------------------------------

test('secretsStdin: "append" mode appends the code to the password', () => {
  assert.equal(
    logic.secretsStdin("hunter2", "123456", "append"),
    "vpn.secrets.password:hunter2123456\n"
  )
})

test('secretsStdin: "append" mode with no code is just the password', () => {
  assert.equal(logic.secretsStdin("hunter2", "", "append"), "vpn.secrets.password:hunter2\n")
})

test("secretsStdin: an unrecognized mode defaults to append", () => {
  assert.equal(logic.secretsStdin("hunter2", "9", undefined), "vpn.secrets.password:hunter29\n")
})

test('secretsStdin: "challenge" mode sends the code as a separate challenge-response secret', () => {
  assert.equal(
    logic.secretsStdin("hunter2", "123456", "challenge"),
    "vpn.secrets.password:hunter2\nvpn.secrets.challenge-response:123456\n"
  )
})

test('secretsStdin: "challenge" mode with no code omits the challenge-response line', () => {
  assert.equal(logic.secretsStdin("hunter2", "", "challenge"), "vpn.secrets.password:hunter2\n")
})

test("secretsStdin strips embedded newlines from the password and the code, never passing them", () => {
  const out = logic.secretsStdin("pa\nss", "12\n34", "append")
  assert.equal(out, "vpn.secrets.password:pass1234\n")
  assert.equal(out.split("\n").length, 2)
})

test("secretsStdin strips embedded newlines in challenge mode too", () => {
  const out = logic.secretsStdin("pa\nss", "12\r\n34", "challenge")
  assert.equal(out, "vpn.secrets.password:pass\nvpn.secrets.challenge-response:1234\n")
})

test("secretsStdin on missing password/code never throws", () => {
  assert.equal(logic.secretsStdin(undefined, undefined, "append"), "vpn.secrets.password:\n")
})

// --- needsSecrets --------------------------------------------------------------

test("needsSecrets matches the documented nmcli phrases, case-insensitively", () => {
  assert.equal(logic.needsSecrets("Error: Secrets were required, but not provided."), true)
  assert.equal(logic.needsSecrets("no secrets available"), true)
  assert.equal(
    logic.needsSecrets("Passwords or encryption keys are required to access the VPN."),
    true
  )
  assert.equal(logic.needsSecrets("PASSWORDS OR ENCRYPTION KEYS ARE REQUIRED"), true)
})

test("needsSecrets is false on unrelated stderr, and never throws on missing input", () => {
  assert.equal(logic.needsSecrets("connection activation failed: timeout"), false)
  assert.equal(logic.needsSecrets(undefined), false)
  assert.equal(logic.needsSecrets(""), false)
})

// --- isAuthFailure ---------------------------------------------------------------

test("isAuthFailure is true for anything needsSecrets matches", () => {
  assert.equal(logic.isAuthFailure("secrets were required"), true)
})

test("isAuthFailure is true on the full authentication-failed phrase, case-insensitively", () => {
  assert.equal(logic.isAuthFailure("Authentication failed."), true)
  assert.equal(logic.isAuthFailure("AUTHENTICATION FAILED"), true)
})

test("isAuthFailure is false on an unrelated failure", () => {
  assert.equal(logic.isAuthFailure("connection activation failed: timeout"), false)
  assert.equal(logic.isAuthFailure(undefined), false)
})

test('isAuthFailure requires the full phrase, not a bare "auth": real nmcli/NM noise that only contains "auth" is not an auth failure', () => {
  assert.equal(logic.isAuthFailure("Auth dialog failed to open"), false)
  assert.equal(logic.isAuthFailure("HTTP proxy auth file"), false)
  assert.equal(logic.isAuthFailure("PolicyKit Authentication Agent"), false)
})

// --- connectCommand / disconnectCommand -----------------------------------------

test("connectCommand without secrets: --wait 30, no passwd-file", () => {
  assert.deepEqual(logic.connectCommand("uuid-1", false), [
    "nmcli",
    "--wait",
    "30",
    "connection",
    "up",
    "uuid",
    "uuid-1"
  ])
})

test("connectCommand with secrets: --wait 60, passwd-file /dev/stdin, no secret text anywhere in argv", () => {
  const argv = logic.connectCommand("uuid-1", true)
  assert.deepEqual(argv, [
    "nmcli",
    "--wait",
    "60",
    "connection",
    "up",
    "uuid",
    "uuid-1",
    "passwd-file",
    "/dev/stdin"
  ])
  assert.ok(
    !argv.join(" ").match(/vpn\.secrets|hunter2|password:/i),
    "argv never carries the secret"
  )
})

test("disconnectCommand: --wait 20", () => {
  assert.deepEqual(logic.disconnectCommand("uuid-1"), [
    "nmcli",
    "--wait",
    "20",
    "connection",
    "down",
    "uuid",
    "uuid-1"
  ])
})

// --- statusText ------------------------------------------------------------------

test("statusText: connecting reads Connecting… before 5s", () => {
  assert.equal(logic.statusText("connecting", 0), "Connecting…")
  assert.equal(logic.statusText("connecting", 4999), "Connecting…")
})

test("statusText: connecting switches to the push-2FA text at/after 5s", () => {
  assert.equal(logic.statusText("connecting", 5000), "Connecting… approve on phone")
  assert.equal(logic.statusText("connecting", 9000), "Connecting… approve on phone")
})

test("statusText: the other phases", () => {
  assert.equal(logic.statusText("disconnecting", 0), "Disconnecting…")
  assert.equal(logic.statusText("failedUp", 0), "Couldn't connect")
  assert.equal(logic.statusText("failedDown", 0), "Couldn't disconnect")
  assert.equal(logic.statusText("failedOpen", 0), "Couldn't open")
})

test("statusText on an unknown phase is empty, not a throw", () => {
  assert.equal(logic.statusText("bogus", 0), "")
  assert.equal(logic.statusText(undefined, undefined), "")
})

// --- iconState --------------------------------------------------------------------

test("iconState: idle with nothing up and no recent failure", () => {
  assert.equal(logic.iconState(false, false), "idle")
})

test("iconState: up when anything is up and there's no recent failure", () => {
  assert.equal(logic.iconState(true, false), "up")
})

test("iconState: alert on a recent failure, even while something stays up", () => {
  assert.equal(logic.iconState(false, true), "alert")
  assert.equal(logic.iconState(true, true), "alert")
})

// --- headerCaption -----------------------------------------------------------------

test('headerCaption: "Not connected" when nothing is up', () => {
  assert.equal(logic.headerCaption(0, 5), "Not connected")
  assert.equal(logic.headerCaption(0, 0), "Not connected")
})

test("headerCaption: N of M connected", () => {
  assert.equal(logic.headerCaption(2, 5), "2 of 5 connected")
  assert.equal(logic.headerCaption(1, 1), "1 of 1 connected")
})

test("headerCaption on missing/negative input never throws", () => {
  assert.equal(logic.headerCaption(undefined, undefined), "Not connected")
  assert.equal(logic.headerCaption(-1, 3), "Not connected")
})

// --- keyHint -----------------------------------------------------------------------

test("keyHint: an app row always says open app", () => {
  assert.equal(logic.keyHint("available", "app"), "↑↓ move · enter open app · tab next")
  assert.equal(logic.keyHint("connected", "app"), "↑↓ move · enter open app · tab next")
})

test("keyHint: a NetworkManager row says connect from available, disconnect from connected", () => {
  assert.equal(logic.keyHint("available", "nm"), "↑↓ move · enter connect · tab next")
  assert.equal(logic.keyHint("connected", "nm"), "↑↓ move · enter disconnect · tab next")
})

// --- Panel wiring rules -------------------------------------------------------

const REAL_VPN_DATA =
  "vpn.data:auth = SHA256, ca = /home/user/ca.pem, connection-type = password-tls, remote = vpn.example.com:443, username = jdoe"

test("parseUsername reads vpn.data's username, or empty", () => {
  assert.equal(
    logic.parseUsername(
      REAL_VPN_DATA + "\nvpn.service-type:org.freedesktop.NetworkManager.openvpn"
    ),
    "jdoe"
  )
  assert.equal(logic.parseUsername("vpn.data:remote = a:1"), "")
  assert.equal(logic.parseUsername(""), "")
})

test("viewRows labels NetworkManager rows with their type and keeps app labels", () => {
  const conns = [
    { name: "Office", uuid: "u1", type: "vpn", device: "", active: false, state: "" },
    { name: "Home", uuid: "u2", type: "wireguard", device: "wg0", active: true, state: "activated" }
  ]
  const built = logic.vpnRows(
    conns,
    [{ name: "Azure", label: "Azure VPN Client", detect: {}, open: ["x"] }],
    {}
  )
  const rows = logic.viewRows(built.available, conns, {
    u1: { ip: "", server: "", vpnType: "OpenVPN" }
  })
  assert.deepEqual(
    rows.map((r) => [r.key, r.label]),
    [
      ["u1", "OpenVPN"],
      ["app:Azure", "Azure VPN Client"]
    ]
  )
  assert.equal(logic.viewRows(built.connected, conns, undefined)[0].label, "WireGuard")
  assert.deepEqual(Object.keys(rows[0]).sort(), ["glyph", "key", "kind", "label", "name"])
  // An unknown session (or a row whose profile vanished) reads as the generic type.
  assert.equal(logic.viewRows(built.available, [], {})[0].label, "VPN")
  assert.deepEqual(logic.viewRows(undefined, undefined, undefined), [])
})

test("sessionsToFetch reads new profiles and connected-state changes only", () => {
  const conns = [
    { name: "A", uuid: "a", type: "vpn", device: "", active: false, state: "" },
    { name: "B", uuid: "b", type: "vpn", device: "", active: true, state: "activated" }
  ]
  const first = logic.sessionsToFetch(undefined, conns)
  assert.deepEqual(first.fetch, ["a", "b"])
  assert.deepEqual(first.seen, { a: false, b: true })
  assert.deepEqual(logic.sessionsToFetch(first.seen, conns).fetch, [])
  const changed = conns.map((c) =>
    c.uuid === "a" ? { ...c, active: true, state: "activated" } : c
  )
  assert.deepEqual(logic.sessionsToFetch(first.seen, changed).fetch, ["a"])
  // Activating isn't connected yet.
  const activating = conns.map((c) =>
    c.uuid === "a" ? { ...c, active: true, state: "activating" } : c
  )
  assert.deepEqual(logic.sessionsToFetch(first.seen, activating).fetch, [])
  assert.deepEqual(logic.sessionsToFetch(first.seen, undefined), { fetch: [], seen: {} })
})

test("linkCommand passes process names as positional args, never in the script", () => {
  const argv = logic.linkCommand(["evil; rm -rf ~", "gpd"])
  assert.equal(argv[0], "bash")
  assert.equal(argv[1], "-c")
  assert.equal(argv[2].includes("evil"), false)
  assert.deepEqual(argv.slice(3), ["_", "evil; rm -rf ~", "gpd"])
  assert.deepEqual(logic.linkCommand(undefined).slice(3), ["_"])
})

test("parseLinkOutput splits links and running processes, tolerating junk", () => {
  const text =
    '[{"ifname":"tun0","operstate":"UNKNOWN","addr_info":[{"family":"inet","local":"10.8.0.2"}]}]\n\n---\ngpd\n'
  const out = logic.parseLinkOutput(text)
  assert.equal(out.links[0].ifname, "tun0")
  assert.deepEqual(out.procs, ["gpd"])
  assert.deepEqual(logic.parseLinkOutput("not json\n---\n"), { links: [], procs: [] })
  assert.deepEqual(logic.parseLinkOutput('{"a":1}'), { links: [], procs: [] })
  assert.deepEqual(logic.parseLinkOutput(undefined), { links: [], procs: [] })
})

const LINKS = [
  {
    ifname: "wlp2s0",
    operstate: "UP",
    addr_info: [
      { family: "inet6", local: "fe80::1" },
      { family: "inet", local: "192.168.0.2" }
    ]
  },
  { ifname: "tun0", operstate: "UNKNOWN", addr_info: [{ family: "inet", local: "10.8.0.2" }] },
  { ifname: "bare" },
  null
]

test("linkAddress and interfaceForAddress map between interfaces and IPv4", () => {
  assert.equal(logic.linkAddress(LINKS, "wlp2s0"), "192.168.0.2")
  assert.equal(logic.linkAddress(LINKS, "bare"), "")
  assert.equal(logic.linkAddress(LINKS, ""), "")
  assert.equal(logic.linkAddress(undefined, "tun0"), "")
  assert.equal(logic.interfaceForAddress(LINKS, "10.8.0.2"), "tun0")
  assert.equal(logic.interfaceForAddress(LINKS, "fe80::1"), "")
  assert.equal(logic.interfaceForAddress(LINKS, ""), "")
  assert.equal(logic.interfaceForAddress(undefined, "10.8.0.2"), "")
})

test("rowInterfaces finds each connected row's tunnel", () => {
  const rows = [
    { key: "u1", kind: "nm", name: "Office", glyph: "", label: "" },
    { key: "u2", kind: "nm", name: "Home", glyph: "", label: "" },
    { key: "u3", kind: "nm", name: "Lost", glyph: "", label: "" },
    { key: "app:Azure", kind: "app", name: "Azure", glyph: "", label: "" },
    { key: "app:GP", kind: "app", name: "GP", glyph: "", label: "" }
  ]
  const conns = [
    { name: "Office", uuid: "u1", type: "vpn", device: "wlp2s0", active: true, state: "activated" },
    {
      name: "Home",
      uuid: "u2",
      type: "wireguard",
      device: "wg0",
      active: true,
      state: "activated"
    },
    { name: "Lost", uuid: "u3", type: "vpn", device: "wlp2s0", active: true, state: "activated" }
  ]
  const out = logic.rowInterfaces(
    rows,
    conns,
    { u1: { ip: "10.8.0.2", server: "", vpnType: "OpenVPN" } },
    LINKS,
    {
      Azure: "tun9"
    }
  )
  // Never the parent device nmcli names for a plugin VPN.
  assert.deepEqual(out, { u1: "tun0", u2: "wg0", "app:Azure": "tun9" })
  assert.deepEqual(logic.rowInterfaces(undefined, undefined, undefined, undefined, undefined), {})
})

test("countersCommand passes interface names as positional args", () => {
  const argv = logic.countersCommand(["tun0", "$(x)"])
  assert.equal(argv[2].includes("tun0"), false)
  assert.deepEqual(argv.slice(3), ["_", "tun0", "$(x)"])
  assert.deepEqual(logic.countersCommand(undefined).slice(3), ["_"])
})

test("parseCounters and counterRates turn byte counters into rates", () => {
  const a = logic.parseCounters("tun0 100 200\nbad line\nwg0 x 1\n")
  assert.deepEqual(a, { tun0: { rx: 100, tx: 200 } })
  const b = logic.parseCounters("tun0 400 260\nwg0 5 5\n")
  assert.deepEqual(logic.counterRates(a, b, 1.5), { tun0: { rx: 200, tx: 40 } })
  // Counters going backwards (a recreated tunnel) give no rate.
  assert.deepEqual(logic.counterRates(b, a, 1), {})
  assert.deepEqual(logic.counterRates(null, b, 1), {})
  assert.deepEqual(logic.counterRates(a, b, 0), {})
  assert.deepEqual(logic.parseCounters(undefined), {})
})

test("trackUptime keeps, starts and forgets keys; the first read says before open", () => {
  const first = logic.trackUptime(undefined, ["a"], 1000, true)
  assert.deepEqual(first, { a: -1 })
  const next = logic.trackUptime(first, ["a", "b"], 5000, false)
  assert.deepEqual(next, { a: -1, b: 5000 })
  const dropped = logic.trackUptime(next, ["b"], 9000, false)
  assert.deepEqual(dropped, { b: 5000 })
  // Back up after a transition: a fresh time, not "before open".
  assert.deepEqual(logic.trackUptime(dropped, ["a", "b"], 9500, false), { a: 9500, b: 5000 })
  assert.deepEqual(logic.trackUptime(undefined, undefined, 0, false), {})
})

test("upText and sessionDetails format the connected rows' details", () => {
  assert.equal(logic.upText(-1, 0), "since before open")
  assert.equal(logic.upText(0, 72 * 60000), "1 h 12 min")
  assert.equal(logic.upText(undefined, 0), "")
  const rows = [
    { key: "u1", kind: "nm", name: "Office", glyph: "", label: "" },
    { key: "u2", kind: "nm", name: "NoSession", glyph: "", label: "" },
    { key: "app:Azure", kind: "app", name: "Azure", glyph: "", label: "" },
    { key: "app:GP", kind: "app", name: "GP", glyph: "", label: "" }
  ]
  const out = logic.sessionDetails(
    rows,
    { u1: { ip: "10.8.0.2", server: "vpn.example.com:443", vpnType: "OpenVPN" } },
    { Azure: "10.9.0.3" },
    { u1: -1, "app:Azure": 0 },
    120000
  )
  assert.deepEqual(out, {
    u1: { ip: "10.8.0.2", server: "vpn.example.com:443", up: "since before open" },
    u2: { ip: "", server: "", up: "" },
    "app:Azure": { ip: "10.9.0.3", server: "", up: "2 min" },
    "app:GP": { ip: "", server: "", up: "" }
  })
  assert.deepEqual(logic.sessionDetails(undefined, undefined, undefined, undefined, 0), {})
})

test("statusMap shows the running action and a recent failure", () => {
  assert.deepEqual(logic.statusMap(null, null), {})
  assert.deepEqual(
    logic.statusMap(
      { key: "a", phase: "connecting", waited: 6000 },
      { key: "b", phase: "failedUp" }
    ),
    {
      a: { text: "Connecting… approve on phone", busy: true, failed: false },
      b: { text: "Couldn't connect", busy: false, failed: true }
    }
  )
  // A new action on the failed row wins.
  assert.deepEqual(
    logic.statusMap(
      { key: "a", phase: "disconnecting", waited: 0 },
      { key: "a", phase: "failedOpen" }
    ),
    {
      a: { text: "Disconnecting…", busy: true, failed: false }
    }
  )
})

test("connectOutcome sorts nmcli exits into ok, prompt, wrong and failed", () => {
  assert.equal(logic.connectOutcome(0, "", false), "ok")
  assert.equal(
    logic.connectOutcome(4, "Error: Secrets were required, but not provided", false),
    "prompt"
  )
  assert.equal(
    logic.connectOutcome(4, "Error: Secrets were required, but not provided", true),
    "wrong"
  )
  assert.equal(logic.connectOutcome(4, "VPN authentication failed", true), "wrong")
  assert.equal(logic.connectOutcome(4, "Error: timeout", true), "failed")
  assert.equal(logic.connectOutcome(4, "VPN authentication failed", false), "failed")
})

test("droppedKeys flags only rows that went from Connected to Available unbidden", () => {
  const row = (key) => ({ key, kind: "nm", name: key, glyph: "", label: "" })
  assert.deepEqual(
    logic.droppedKeys(["a", "b", "c", "d"], [row("d")], [row("a"), row("b")], ["b"]),
    ["a"]
  )
  assert.deepEqual(logic.droppedKeys(undefined, undefined, undefined, undefined), [])
})

test("pollInterval polls fast open, slowly closed, and not at all with nothing to watch", () => {
  assert.equal(logic.pollInterval(true, false, false), 2000)
  assert.equal(logic.pollInterval(false, true, false), 5000)
  assert.equal(logic.pollInterval(false, false, true), 5000)
  assert.equal(logic.pollInterval(false, false, false), 0)
})

test("otpMode reads the profile's mode, defaulting to append", () => {
  assert.equal(logic.otpMode({ A: { otp: "challenge" } }, "A"), "challenge")
  assert.equal(logic.otpMode({ A: { otp: "append" } }, "A"), "append")
  assert.equal(logic.otpMode({}, "A"), "append")
  assert.equal(logic.otpMode(undefined, "A"), "append")
})

test("emptyText and hintFor", () => {
  assert.equal(logic.emptyText(true, 0), "No VPNs yet")
  assert.equal(logic.emptyText(false, 0), "NetworkManager isn't running")
  assert.equal(logic.emptyText(false, 2), "")
  assert.equal(logic.hintFor(true, "available", "nm", true), "enter connect · esc cancel")
  assert.equal(logic.hintFor(false, "", "", false), "tab next · esc close")
  assert.equal(logic.hintFor(false, "connected", "nm", true), logic.keyHint("connected", "nm"))
})

test("moveFlat and cursorPlace walk Connected then Available", () => {
  assert.equal(logic.moveFlat(0, 1, 3), 1)
  assert.equal(logic.moveFlat(2, 1, 3), 2)
  assert.equal(logic.moveFlat(0, -1, 3), 0)
  assert.equal(logic.moveFlat(0, 1, 0), -1)
  assert.equal(logic.moveFlat(undefined, 1, 2), 1)
  assert.deepEqual(logic.cursorPlace(1, 2), { section: "connected", index: 1 })
  assert.deepEqual(logic.cursorPlace(2, 2), { section: "available", index: 0 })
})

test("parseFixture builds display-only rows and sessions keyed fixture:N", () => {
  const out = logic.parseFixture(
    JSON.stringify([
      {
        name: "Office",
        label: "OpenVPN",
        kind: "nm",
        connected: true,
        ip: "10.8.0.2",
        server: "vpn.example.com",
        upMinutes: 72
      },
      { name: "Azure", label: "Azure VPN Client", kind: "app", connected: false },
      { name: "Lab", kind: "nm", connected: true },
      { name: "GP", kind: "app" }
    ])
  )
  assert.deepEqual(
    out.connected.map((r) => [r.key, r.kind, r.label]),
    [
      ["fixture:0", "nm", "OpenVPN"],
      ["fixture:2", "nm", "VPN"]
    ]
  )
  assert.deepEqual(
    out.available.map((r) => [r.key, r.kind, r.label]),
    [
      ["fixture:1", "app", "Azure VPN Client"],
      ["fixture:3", "app", "GP"]
    ]
  )
  assert.deepEqual(out.sessions["fixture:0"], {
    ip: "10.8.0.2",
    server: "vpn.example.com",
    up: "1 h 12 min"
  })
  assert.deepEqual(out.sessions["fixture:2"], { ip: "", server: "", up: "" })
  assert.equal(logic.parseFixture("nope"), null)
  assert.equal(logic.parseFixture("{}"), null)
  assert.equal(logic.parseFixture('[{"label":"x"}]'), null)
})

test("whichCommand passes the binary as a positional arg", () => {
  assert.deepEqual(logic.whichCommand("a b").slice(3), ["_", "a b"])
  assert.equal(logic.whichCommand(undefined)[4], "")
})
