// Logic contract for VpnApps.js: parsing ~/.config/aranea/vpn-apps.json
// (both the bare-array and {apps, profiles} object forms), glob matching
// an interface name, an own-app VPN's detected state, its matched
// interface, and the Network status line. No QML, no I/O; run with
// `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.shared/VpnApps.js"))

// --- parseAppsConfig: bare-array form ---------------------------------------

test("parseAppsConfig accepts the bare-array form", () => {
  const text = JSON.stringify([
    {
      name: "Azure (Contoso)",
      label: "Azure VPN Client",
      detect: { interface: "tun*", process: "microsoft-azurevpnclient" },
      open: ["microsoft-azurevpnclient"]
    },
    {
      name: "GlobalProtect (HQ)",
      label: "GlobalProtect",
      detect: { interface: "gpd0" },
      open: ["globalprotect", "launch-ui"]
    }
  ])
  const result = logic.parseAppsConfig(text)
  assert.equal(result.error, "")
  assert.deepEqual(result.profiles, {})
  assert.deepEqual(result.apps, [
    {
      name: "Azure (Contoso)",
      label: "Azure VPN Client",
      detect: { interface: "tun*", process: "microsoft-azurevpnclient" },
      open: ["microsoft-azurevpnclient"]
    },
    {
      name: "GlobalProtect (HQ)",
      label: "GlobalProtect",
      detect: { interface: "gpd0" },
      open: ["globalprotect", "launch-ui"]
    }
  ])
})

// --- parseAppsConfig: object form with profiles -----------------------------

test("parseAppsConfig accepts the object form with apps and profiles", () => {
  const text = JSON.stringify({
    apps: [{ name: "GlobalProtect (HQ)", detect: { interface: "gpd0" }, open: ["globalprotect"] }],
    profiles: {
      "Office (Firebox)": { otp: "append" },
      "Client A": { otp: "challenge" }
    }
  })
  const result = logic.parseAppsConfig(text)
  assert.equal(result.error, "")
  assert.equal(result.apps.length, 1)
  assert.deepEqual(result.profiles, {
    "Office (Firebox)": { otp: "append" },
    "Client A": { otp: "challenge" }
  })
})

test("parseAppsConfig defaults an unrecognized or missing otp to append", () => {
  const text = JSON.stringify({
    apps: [],
    profiles: { A: { otp: "challenge" }, B: { otp: "bogus" }, C: {} }
  })
  const result = logic.parseAppsConfig(text)
  assert.deepEqual(result.profiles, {
    A: { otp: "challenge" },
    B: { otp: "append" },
    C: { otp: "append" }
  })
})

// --- parseAppsConfig: defaults -----------------------------------------------

test("parseAppsConfig defaults label to name and detect to {}", () => {
  const result = logic.parseAppsConfig(JSON.stringify([{ name: "Plain", open: ["plain-vpn"] }]))
  assert.equal(result.error, "")
  assert.deepEqual(result.apps, [
    { name: "Plain", label: "Plain", detect: {}, open: ["plain-vpn"] }
  ])
})

// --- parseAppsConfig: invalid input ------------------------------------------

test("parseAppsConfig on unparsable JSON returns no apps and an error", () => {
  const result = logic.parseAppsConfig("{not json")
  assert.deepEqual(result.apps, [])
  assert.deepEqual(result.profiles, {})
  assert.notEqual(result.error, "")
})

test("parseAppsConfig on the wrong shape (not an array, no apps field) errors", () => {
  const result = logic.parseAppsConfig(JSON.stringify({ foo: "bar" }))
  assert.deepEqual(result.apps, [])
  assert.notEqual(result.error, "")
})

test("parseAppsConfig on undefined/empty text errors rather than throwing", () => {
  assert.deepEqual(logic.parseAppsConfig(undefined).apps, [])
  assert.notEqual(logic.parseAppsConfig(undefined).error, "")
  assert.deepEqual(logic.parseAppsConfig("").apps, [])
})

// --- parseAppsConfig: dropped entries -----------------------------------------

test("parseAppsConfig drops an entry missing name, names it in error, keeps the rest", () => {
  const result = logic.parseAppsConfig(
    JSON.stringify([
      { label: "No name", open: ["x"] },
      { name: "Good", open: ["y"] }
    ])
  )
  assert.deepEqual(result.apps, [{ name: "Good", label: "Good", detect: {}, open: ["y"] }])
  assert.notEqual(result.error, "")
})

test("parseAppsConfig drops an entry with a non-array open, names it in error", () => {
  const result = logic.parseAppsConfig(JSON.stringify([{ name: "Bad", open: "not-an-array" }]))
  assert.deepEqual(result.apps, [])
  assert.notEqual(result.error, "", "a string open is rejected, not treated as a one-item argv")
})

test("parseAppsConfig drops an entry with a missing open", () => {
  const result = logic.parseAppsConfig(JSON.stringify([{ name: "Bad" }]))
  assert.deepEqual(result.apps, [])
  assert.notEqual(result.error, "")
})

test("parseAppsConfig drops a null or non-object entry without throwing", () => {
  const result = logic.parseAppsConfig(JSON.stringify([null, 5, { name: "Good", open: ["y"] }]))
  assert.deepEqual(result.apps, [{ name: "Good", label: "Good", detect: {}, open: ["y"] }])
  assert.notEqual(result.error, "")
})

test("parseAppsConfig with no invalid entries carries no error", () => {
  const result = logic.parseAppsConfig(JSON.stringify([{ name: "Good", open: ["y"] }]))
  assert.equal(result.error, "")
})

// --- globMatch ---------------------------------------------------------------

test("globMatch matches a literal name exactly, case-sensitively", () => {
  assert.equal(logic.globMatch("gpd0", "gpd0"), true)
  assert.equal(logic.globMatch("gpd0", "gpd1"), false)
  assert.equal(logic.globMatch("gpd0", "GPD0"), false)
})

test("globMatch: * matches any run of characters, including none", () => {
  assert.equal(logic.globMatch("tun*", "tun0"), true)
  assert.equal(logic.globMatch("tun*", "tun"), true)
  assert.equal(logic.globMatch("tun*", "tunnel99"), true)
  assert.equal(logic.globMatch("tun*", "wgtun0"), false)
  assert.equal(logic.globMatch("*vpn*", "my-vpn-0"), true)
})

test("globMatch: ? matches exactly one character", () => {
  assert.equal(logic.globMatch("tun?", "tun0"), true)
  assert.equal(logic.globMatch("tun?", "tun"), false)
  assert.equal(logic.globMatch("tun?", "tun00"), false)
})

test("globMatch escapes regex-special characters in the pattern", () => {
  assert.equal(logic.globMatch("wg+0", "wg+0"), true)
  assert.equal(logic.globMatch("wg.0", "wgX0"), false)
  assert.equal(logic.globMatch("wg.0", "wg.0"), true)
})

test("globMatch on missing input never throws", () => {
  assert.equal(logic.globMatch(undefined, "x"), false)
  assert.equal(logic.globMatch("x", undefined), false)
})

// --- appState ------------------------------------------------------------------

const UP_WITH_ADDR = { ifname: "gpd0", operstate: "UP", addr_info: [{ local: "10.0.0.2" }] }
const UP_NO_ADDR = { ifname: "gpd0", operstate: "UP", addr_info: [] }
const DOWN = { ifname: "gpd0", operstate: "DOWN", addr_info: [] }
const UNKNOWN_WITH_ADDR = {
  ifname: "tun0",
  operstate: "UNKNOWN",
  addr_info: [{ local: "10.0.0.3" }]
}

test("appState: interface only, up with an address is connected", () => {
  const app = { detect: { interface: "gpd0" } }
  assert.equal(logic.appState(app, [UP_WITH_ADDR], new Set()), "connected")
})

test("appState: a tun device reporting UNKNOWN with an address counts as connected", () => {
  const app = { detect: { interface: "tun*" } }
  assert.equal(logic.appState(app, [UNKNOWN_WITH_ADDR], new Set()), "connected")
})

test("appState: interface only, matching but down or addressless is present", () => {
  const app = { detect: { interface: "gpd0" } }
  assert.equal(logic.appState(app, [DOWN], new Set()), "present")
  assert.equal(logic.appState(app, [UP_NO_ADDR], new Set()), "present")
})

test("appState: interface only, no matching link is absent", () => {
  const app = { detect: { interface: "gpd0" } }
  assert.equal(logic.appState(app, [], new Set()), "absent")
  assert.equal(
    logic.appState(
      app,
      [{ ifname: "eth0", operstate: "UP", addr_info: [{ local: "x" }] }],
      new Set()
    ),
    "absent"
  )
})

test("appState: process only, running is connected, not running is absent (no partial state)", () => {
  const app = { detect: { process: "globalprotect" } }
  assert.equal(logic.appState(app, [], new Set(["globalprotect"])), "connected")
  assert.equal(logic.appState(app, [], new Set()), "absent")
  assert.equal(logic.appState(app, [], new Set(["other"])), "absent")
})

test("appState: both given, both matching is connected", () => {
  const app = { detect: { interface: "tun*", process: "microsoft-azurevpnclient" } }
  assert.equal(
    logic.appState(app, [UNKNOWN_WITH_ADDR], new Set(["microsoft-azurevpnclient"])),
    "connected"
  )
})

test("appState: both given, only one matching is present (not connected)", () => {
  const app = { detect: { interface: "tun*", process: "microsoft-azurevpnclient" } }
  assert.equal(
    logic.appState(app, [UNKNOWN_WITH_ADDR], new Set()),
    "present",
    "interface up, process not running"
  )
  assert.equal(
    logic.appState(app, [], new Set(["microsoft-azurevpnclient"])),
    "present",
    "process running, interface not up"
  )
})

test("appState: both given, neither matching is absent", () => {
  const app = { detect: { interface: "tun*", process: "microsoft-azurevpnclient" } }
  assert.equal(logic.appState(app, [], new Set()), "absent")
})

test("appState: an empty detect is always absent", () => {
  assert.equal(logic.appState({ detect: {} }, [UP_WITH_ADDR], new Set(["anything"])), "absent")
  assert.equal(logic.appState({}, [], new Set()), "absent")
})

test("appState accepts procs as a Set, an array or a plain object", () => {
  const app = { detect: { process: "foo" } }
  assert.equal(logic.appState(app, [], ["foo"]), "connected")
  assert.equal(logic.appState(app, [], { foo: true }), "connected")
  assert.equal(logic.appState(app, [], null), "absent")
})

// --- appInterface --------------------------------------------------------------

test("appInterface returns the matched interface name regardless of up state", () => {
  const app = { detect: { interface: "gpd0" } }
  assert.equal(logic.appInterface(app, [DOWN]), "gpd0")
  assert.equal(logic.appInterface(app, [UP_WITH_ADDR]), "gpd0")
})

test("appInterface matches a glob pattern against ifname", () => {
  const app = { detect: { interface: "tun*" } }
  assert.equal(logic.appInterface(app, [UNKNOWN_WITH_ADDR]), "tun0")
})

test('appInterface returns "" with no interface detect or no match', () => {
  assert.equal(logic.appInterface({ detect: { process: "x" } }, [UP_WITH_ADDR]), "")
  assert.equal(logic.appInterface({ detect: { interface: "gpd0" } }, []), "")
  assert.equal(logic.appInterface({ detect: { interface: "gpd0" } }, undefined), "")
})

// --- statusLine ------------------------------------------------------------------

test("statusLine is empty with nothing up", () => {
  assert.equal(logic.statusLine([]), "")
  assert.equal(logic.statusLine(undefined), "")
})

test("statusLine names the one VPN that's up", () => {
  assert.equal(logic.statusLine(["Office (Firebox)"]), "VPN · Office (Firebox) up")
})

test("statusLine counts several VPNs that are up", () => {
  assert.equal(logic.statusLine(["Office (Firebox)", "Azure (Contoso)"]), "VPN · 2 up")
  assert.equal(logic.statusLine(["A", "B", "C"]), "VPN · 3 up")
})

test("parseAppsConfig drops a later entry repeating a name and says so", () => {
  const out = logic.parseAppsConfig(
    JSON.stringify([
      { name: "A", open: ["a"] },
      { name: "A", open: ["b"] },
      { name: "B", open: ["c"] }
    ])
  )
  assert.deepEqual(
    out.apps.map((a) => a.open[0]),
    ["a", "c"]
  )
  assert.equal(out.error, "dropped: A (duplicate name)")
})
