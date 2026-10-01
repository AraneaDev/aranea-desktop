// Logic contract for VpnLogic.js: parsing nmcli's VPN connection list and
// per-connection session fields, building the Connected/Available rows,
// the secrets sent to nmcli on stdin, auth-failure detection, connect/
// disconnect argv, and the small text helpers. No QML, no I/O; run with
// `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.vpn/VpnLogic.js"))

// --- splitTerse --------------------------------------------------------------

test("splitTerse splits on unescaped colons and unescapes \\: and \\\\", () => {
  assert.deepEqual(logic.splitTerse("a:b:c"), ["a", "b", "c"])
  assert.deepEqual(logic.splitTerse("Office (Firebox)\\: HQ:uuid-1"), [
    "Office (Firebox): HQ",
    "uuid-1"
  ])
  assert.deepEqual(logic.splitTerse("back\\\\slash:next"), ["back\\slash", "next"])
})

test("splitTerse on missing input returns one empty field, never throws", () => {
  assert.deepEqual(logic.splitTerse(undefined), [""])
})

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

// --- parseSession --------------------------------------------------------------
//
// There are no real VPN profiles on this machine to capture `nmcli -t -g`
// output from. These fixtures are constructed from nmcli's documented
// behaviour: `-g` with several properties on a single `connection show`
// target prints one requested property per line, in the order asked; a
// complex property such as `vpn.data` renders as `key = value, key = value`
// (the task brief's own example). `wireguard.peers`'s shape isn't specified
// anywhere the brief points to, so its `key = value` / `" | "`-separated-peers
// format here is this task's own construction (see task-2-report.md).

test("parseSession reads an OpenVPN session: ip, remote as server, OpenVPN as type", () => {
  const text = [
    "10.8.0.2/24",
    "remote = vpn.example.com:1194, cipher = AES-256-GCM, username = tschipper",
    "org.freedesktop.NetworkManager.openvpn",
    ""
  ].join("\n")
  assert.deepEqual(logic.parseSession(text), {
    ip: "10.8.0.2",
    server: "vpn.example.com:1194",
    vpnType: "OpenVPN"
  })
})

test("parseSession reads an OpenConnect session: gateway as server, OpenConnect as type", () => {
  const text = [
    "10.9.0.4/24",
    "gateway = gp.example.com, gateway-flags = 0",
    "org.freedesktop.NetworkManager.openconnect",
    ""
  ].join("\n")
  assert.deepEqual(logic.parseSession(text), {
    ip: "10.9.0.4",
    server: "gp.example.com",
    vpnType: "OpenConnect"
  })
})

test("parseSession reads a WireGuard session: first peer endpoint host as server, WireGuard as type", () => {
  const text = [
    "10.10.0.5/32",
    "",
    "",
    "endpoint = 203.0.113.5:51820, allowed-ips = 0.0.0.0/0 | endpoint = 203.0.113.6:51820, allowed-ips = 0.0.0.0/0"
  ].join("\n")
  assert.deepEqual(logic.parseSession(text), {
    ip: "10.10.0.5",
    server: "203.0.113.5",
    vpnType: "WireGuard"
  })
})

test("parseSession falls back to VPN with an unrecognized service type and no peers", () => {
  const text = ["10.11.0.1/24", "", "org.freedesktop.NetworkManager.something-else", ""].join("\n")
  const result = logic.parseSession(text)
  assert.equal(result.vpnType, "VPN")
  assert.equal(result.server, "")
})

test("parseSession takes the first address and drops its prefix when several are listed", () => {
  const text = [
    "10.8.0.2/24,10.8.0.3/24",
    "remote = vpn.example.com",
    "org.freedesktop.NetworkManager.openvpn",
    ""
  ].join("\n")
  assert.equal(logic.parseSession(text).ip, "10.8.0.2")
})

test("parseSession on missing/short text never throws", () => {
  assert.deepEqual(logic.parseSession(undefined), { ip: "", server: "", vpnType: "VPN" })
  assert.deepEqual(logic.parseSession("10.0.0.1/24"), {
    ip: "10.0.0.1",
    server: "",
    vpnType: "VPN"
  })
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

test("isAuthFailure is true on auth/authentication-failed text", () => {
  assert.equal(logic.isAuthFailure("Authentication failed."), true)
  assert.equal(logic.isAuthFailure("auth error"), true)
})

test("isAuthFailure is false on an unrelated failure", () => {
  assert.equal(logic.isAuthFailure("connection activation failed: timeout"), false)
  assert.equal(logic.isAuthFailure(undefined), false)
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
