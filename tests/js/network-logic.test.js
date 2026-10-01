// Logic contract for the Aranea network dropdown (NetworkLogic.js).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.network/NetworkLogic.js"))
const cursor = require(path.join(__dirname, "..", "..", "plugins/araneadev.shared/CursorLogic.js"))
const g = (cp) => String.fromCodePoint(cp)

// --- splitTerse ---------------------------------------------------------

test("splitTerse splits on unescaped colons", () => {
  assert.deepEqual(logic.splitTerse("a:b:c"), ["a", "b", "c"])
  assert.deepEqual(logic.splitTerse(""), [""])
  assert.deepEqual(logic.splitTerse(undefined), [""])
})

test("splitTerse unescapes \\: and \\\\ within a field", () => {
  assert.deepEqual(logic.splitTerse("My\\:Net:uuid-1:802-11-wireless::no:0"), [
    "My:Net",
    "uuid-1",
    "802-11-wireless",
    "",
    "no",
    "0"
  ])
  assert.deepEqual(logic.splitTerse("a\\\\\\:b"), ["a\\:b"])
})

// --- splitSections -------------------------------------------------------

test("splitSections splits on lines that are exactly ---", () => {
  assert.deepEqual(logic.splitSections("a\nb\n---\nc\nd"), ["a\nb", "c\nd"])
  assert.deepEqual(logic.splitSections("---\na"), ["", "a"])
  assert.deepEqual(logic.splitSections("a\n---\n"), ["a", ""])
})

test("splitSections with no divider returns the whole text as one section", () => {
  assert.deepEqual(logic.splitSections("a\nb"), ["a\nb"])
})

test("splitSections on missing text returns []", () => {
  assert.deepEqual(logic.splitSections(undefined), [])
  assert.deepEqual(logic.splitSections(""), [])
})

// --- parseDevices ----------------------------------------------------------

test("parseDevices parses the machine's real device shapes", () => {
  const text = [
    "lo:loopback:connected (externally):lo",
    "docker0:bridge:connected (externally):docker0",
    "p2p-dev-wlp2s0:wifi-p2p:disconnected:",
    "wlp2s0:wifi:connected:Interwebz24Ghz",
    "enp3s0:ethernet:unavailable:"
  ].join("\n")
  assert.deepEqual(logic.parseDevices(text), [
    { device: "lo", type: "loopback", state: "connected (externally)", connection: "lo" },
    { device: "docker0", type: "bridge", state: "connected (externally)", connection: "docker0" },
    { device: "p2p-dev-wlp2s0", type: "wifi-p2p", state: "disconnected", connection: "" },
    { device: "wlp2s0", type: "wifi", state: "connected", connection: "Interwebz24Ghz" },
    { device: "enp3s0", type: "ethernet", state: "unavailable", connection: "" }
  ])
})

test("parseDevices skips blank and short lines", () => {
  assert.deepEqual(logic.parseDevices("\nfoo:bar\nlo:loopback:connected:lo"), [
    { device: "lo", type: "loopback", state: "connected", connection: "lo" }
  ])
  assert.deepEqual(logic.parseDevices(undefined), [])
})

// --- parseConnections ------------------------------------------------------

test("parseConnections unescapes a colon in the name and keeps an empty device", () => {
  assert.deepEqual(logic.parseConnections("My\\:Net:uuid-1:802-11-wireless::no:0"), [
    {
      name: "My:Net",
      uuid: "uuid-1",
      type: "802-11-wireless",
      device: "",
      active: false,
      timestamp: 0
    }
  ])
})

test("parseConnections reads active and a numeric timestamp", () => {
  assert.deepEqual(logic.parseConnections("Home:uuid-2:802-11-wireless:wlp2s0:yes:1700000000"), [
    {
      name: "Home",
      uuid: "uuid-2",
      type: "802-11-wireless",
      device: "wlp2s0",
      active: true,
      timestamp: 1700000000
    }
  ])
})

test("parseConnections treats a non-numeric timestamp as 0 and skips blank/short lines", () => {
  assert.deepEqual(logic.parseConnections("Home:uuid-2:802-11-wireless:wlp2s0:no:never"), [
    {
      name: "Home",
      uuid: "uuid-2",
      type: "802-11-wireless",
      device: "wlp2s0",
      active: false,
      timestamp: 0
    }
  ])
  assert.deepEqual(logic.parseConnections("\nonly:two"), [])
  assert.deepEqual(logic.parseConnections(undefined), [])
})

// --- parseAddrs --------------------------------------------------------

const ipJson = JSON.stringify([
  { ifname: "lo", addr_info: [{ local: "127.0.0.1" }] },
  { ifname: "wlp2s0", addr_info: [{ local: "192.168.0.126" }] },
  { ifname: "docker0", addr_info: [] }
])

test("parseAddrs reads each interface's first IPv4 address", () => {
  assert.deepEqual(logic.parseAddrs(ipJson), { lo: "127.0.0.1", wlp2s0: "192.168.0.126" })
})

test("parseAddrs returns {} for garbage, non-array or missing JSON", () => {
  assert.deepEqual(logic.parseAddrs("not json"), {})
  assert.deepEqual(logic.parseAddrs(JSON.stringify({ not: "an array" })), {})
  assert.deepEqual(logic.parseAddrs(undefined), {})
  assert.deepEqual(logic.parseAddrs(JSON.stringify([{ ifname: "lo" }])), {})
})

// --- parseSsids --------------------------------------------------------

test("parseSsids maps uuid to an unescaped SSID, skipping lines without a tab", () => {
  const text = "uuid-1\tHome Net\nuuid-2\tOff\\:ice\nno-tab-here\n\nuuid-3\ta\\\\\\:b"
  assert.deepEqual(logic.parseSsids(text), {
    "uuid-1": "Home Net",
    "uuid-2": "Off:ice",
    "uuid-3": "a\\:b"
  })
})

test("parseSsids on missing text returns {}", () => {
  assert.deepEqual(logic.parseSsids(undefined), {})
})

// --- interfaceRows -------------------------------------------------------

test("interfaceRows drops loopback/bridge/p2p types, builds Wi-Fi and Ethernet detail", () => {
  const devices = logic.parseDevices(
    [
      "lo:loopback:connected (externally):lo",
      "docker0:bridge:connected (externally):docker0",
      "p2p-dev-wlp2s0:wifi-p2p:disconnected:",
      "wlp2s0:wifi:connected:Interwebz24Ghz",
      "enp3s0:ethernet:unavailable:"
    ].join("\n")
  )
  const addrs = { wlp2s0: "192.168.0.126" }
  assert.deepEqual(logic.interfaceRows(devices, addrs), [
    {
      key: "wlp2s0",
      glyph: g(0xf05a9),
      label: "wlp2s0",
      detail: "Wi-Fi · connected · 192.168.0.126",
      active: true
    },
    {
      key: "enp3s0",
      glyph: g(0xf0200),
      label: "enp3s0",
      detail: "Ethernet · cable unplugged",
      active: false
    }
  ])
})

test("interfaceRows drops unmanaged state and virtual device names", () => {
  const devices = [
    { device: "wlp2s0", type: "wifi", state: "unmanaged", connection: "" },
    { device: "veth1234", type: "ethernet", state: "connected", connection: "" },
    { device: "br-abc123", type: "ethernet", state: "connected", connection: "" },
    { device: "virbr0", type: "ethernet", state: "connected", connection: "" }
  ]
  assert.deepEqual(logic.interfaceRows(devices, {}), [])
})

test("interfaceRows labels mobile, WireGuard and tunnel types and glyphs them", () => {
  const devices = [
    { device: "wwan0", type: "gsm", state: "connected", connection: "" },
    { device: "wwan1", type: "cdma", state: "disconnected", connection: "" },
    { device: "wg0", type: "wireguard", state: "connected", connection: "" },
    { device: "tun0", type: "tun", state: "connected", connection: "" }
  ]
  const rows = logic.interfaceRows(devices, {})
  assert.deepEqual(
    rows.map((r) => r.label),
    ["tun0", "wg0", "wwan0", "wwan1"]
  )
  assert.deepEqual(
    rows.map((r) => r.detail),
    ["Tunnel · connected", "WireGuard · connected", "Mobile · connected", "Mobile · disconnected"]
  )
  assert.equal(rows.find((r) => r.label === "wg0").glyph, g(0xf0582))
  assert.equal(rows.find((r) => r.label === "tun0").glyph, g(0xf0582))
  assert.equal(rows.find((r) => r.label === "wwan0").glyph, g(0xf08bc))
})

test("interfaceRows orders active rows first, then alphabetically", () => {
  const devices = [
    { device: "zeta", type: "ethernet", state: "connected", connection: "" },
    { device: "alpha", type: "ethernet", state: "disconnected", connection: "" },
    { device: "beta", type: "ethernet", state: "connected", connection: "" }
  ]
  assert.deepEqual(
    logic.interfaceRows(devices, {}).map((r) => r.label),
    ["beta", "zeta", "alpha"]
  )
})

test("interfaceRows never throws on a null or undefined array element", () => {
  const devices = [
    null,
    { device: "wlp2s0", type: "wifi", state: "connected", connection: "Interwebz24Ghz" }
  ]
  assert.deepEqual(logic.interfaceRows(devices, {}), [
    { key: "wlp2s0", glyph: g(0xf05a9), label: "wlp2s0", detail: "Wi-Fi · connected", active: true }
  ])
  assert.deepEqual(logic.interfaceRows([undefined], {}), [])
})

// --- vpnRows -------------------------------------------------------------

test("vpnRows keeps only vpn and wireguard types, labels and glyphs them", () => {
  const connections = [
    { name: "Office VPN", uuid: "u1", type: "vpn", device: "", active: false, timestamp: 0 },
    { name: "Home WG", uuid: "u2", type: "wireguard", device: "wg0", active: true, timestamp: 0 },
    {
      name: "Home Net",
      uuid: "u3",
      type: "802-11-wireless",
      device: "wlp2s0",
      active: true,
      timestamp: 0
    }
  ]
  const addrs = { wg0: "10.0.0.2" }
  assert.deepEqual(logic.vpnRows(connections, addrs), [
    {
      key: "u2",
      glyph: g(0xf0582),
      label: "Home WG",
      detail: "WireGuard · 10.0.0.2",
      active: true
    },
    { key: "u1", glyph: g(0xf0582), label: "Office VPN", detail: "VPN", active: false }
  ])
})

test("vpnRows omits the address when inactive or unknown", () => {
  const connections = [
    { name: "Idle WG", uuid: "u1", type: "wireguard", device: "wg0", active: false, timestamp: 0 },
    { name: "No Addr", uuid: "u2", type: "vpn", device: "tun0", active: true, timestamp: 0 }
  ]
  assert.deepEqual(logic.vpnRows(connections, {}), [
    { key: "u2", glyph: g(0xf0582), label: "No Addr", detail: "VPN", active: true },
    { key: "u1", glyph: g(0xf0582), label: "Idle WG", detail: "WireGuard", active: false }
  ])
})

test("vpnRows never throws on a null or undefined array element", () => {
  assert.deepEqual(logic.vpnRows([undefined], {}), [])
  const connections = [
    null,
    { name: "Office VPN", uuid: "u1", type: "vpn", device: "", active: false, timestamp: 0 }
  ]
  assert.deepEqual(logic.vpnRows(connections, {}), [
    { key: "u1", glyph: g(0xf0582), label: "Office VPN", detail: "VPN", active: false }
  ])
})

// --- savedRows / lastUsedText ---------------------------------------------

test("savedRows excludes a scanned SSID, falls back to the name, and sorts by timestamp", () => {
  const now = 1700000000
  const connections = [
    {
      name: "fallback-name",
      uuid: "u1",
      type: "802-11-wireless",
      device: "",
      active: false,
      timestamp: now - 86400
    },
    {
      name: "Home",
      uuid: "u2",
      type: "802-11-wireless",
      device: "",
      active: false,
      timestamp: now
    },
    {
      name: "Scanned",
      uuid: "u3",
      type: "802-11-wireless",
      device: "",
      active: false,
      timestamp: now - 1
    },
    { name: "Ignore", uuid: "u4", type: "vpn", device: "", active: false, timestamp: now }
  ]
  const ssidByUuid = { u2: "Home Net", u3: "Scanned Net" }
  const scanned = ["Scanned Net"]
  assert.deepEqual(logic.savedRows(connections, ssidByUuid, scanned, now), [
    { key: "u2", label: "Home Net", detail: "last used today" },
    { key: "u1", label: "fallback-name", detail: "last used yesterday" }
  ])
})

test("savedRows skips an empty SSID", () => {
  const connections = [
    { name: "", uuid: "u1", type: "802-11-wireless", device: "", active: false, timestamp: 1 }
  ]
  assert.deepEqual(logic.savedRows(connections, {}, [], 100), [])
})

test("savedRows never throws on a null array element", () => {
  assert.deepEqual(logic.savedRows([null], {}, [], 100), [])
})

test("lastUsedText boundaries", () => {
  const now = 1700000000
  assert.equal(logic.lastUsedText(0, now), "never used")
  assert.equal(logic.lastUsedText(-5, now), "never used")
  assert.equal(logic.lastUsedText(now - 86399, now), "last used today")
  assert.equal(logic.lastUsedText(now - 86400, now), "last used yesterday")
  assert.equal(logic.lastUsedText(now - 172799, now), "last used yesterday")
  assert.equal(logic.lastUsedText(now - 172800, now), "last used 2 days ago")
  assert.equal(logic.lastUsedText(now - 259200, now), "last used 3 days ago")
})

// --- moveVertical ------------------------------------------------------

test("moveVertical: header stays on up, and goes to vpn/band/dns on down", () => {
  const avail = { header: 1, vpn: 2, band: true, bandPills: true, wifi: 1, saved: 1 }
  assert.deepEqual(
    logic.moveVertical({ section: "header", index: 0, bandAuto: false }, -1, avail),
    { section: "header", index: 0, bandAuto: false }
  )
  assert.deepEqual(logic.moveVertical({ section: "header", index: 0, bandAuto: false }, 1, avail), {
    section: "vpn",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(
    logic.moveVertical({ section: "header", index: 0, bandAuto: false }, 1, { ...avail, vpn: 0 }),
    { section: "band", index: 0, bandAuto: true }
  )
  assert.deepEqual(
    logic.moveVertical({ section: "header", index: 0, bandAuto: false }, 1, {
      ...avail,
      vpn: 0,
      band: false
    }),
    { section: "dns", index: 0, bandAuto: false }
  )
})

test("moveVertical: vpn moves within its rows and at both edges", () => {
  const avail = { header: 1, vpn: 3, band: true, bandPills: true, wifi: 1, saved: 1 }
  assert.deepEqual(logic.moveVertical({ section: "vpn", index: 1, bandAuto: false }, 1, avail), {
    section: "vpn",
    index: 2,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical({ section: "vpn", index: 1, bandAuto: false }, -1, avail), {
    section: "vpn",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical({ section: "vpn", index: 0, bandAuto: false }, -1, avail), {
    section: "header",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(
    logic.moveVertical({ section: "vpn", index: 0, bandAuto: false }, -1, { ...avail, header: 0 }),
    { section: "vpn", index: 0, bandAuto: false }
  )
  assert.deepEqual(logic.moveVertical({ section: "vpn", index: 2, bandAuto: false }, 1, avail), {
    section: "band",
    index: 0,
    bandAuto: true
  })
  assert.deepEqual(
    logic.moveVertical({ section: "vpn", index: 2, bandAuto: false }, 1, { ...avail, band: false }),
    { section: "dns", index: 0, bandAuto: false }
  )
})

test("moveVertical: band toggles bandAuto on up, chains to vpn/header/stay", () => {
  const avail = { header: 1, vpn: 2, band: true, bandPills: true, wifi: 1, saved: 1 }
  assert.deepEqual(logic.moveVertical({ section: "band", index: 0, bandAuto: false }, -1, avail), {
    section: "band",
    index: 0,
    bandAuto: true
  })
  assert.deepEqual(logic.moveVertical({ section: "band", index: 0, bandAuto: true }, -1, avail), {
    section: "vpn",
    index: 1,
    bandAuto: true
  })
  assert.deepEqual(
    logic.moveVertical({ section: "band", index: 0, bandAuto: true }, -1, { ...avail, vpn: 0 }),
    { section: "header", index: 0, bandAuto: true }
  )
  assert.deepEqual(
    logic.moveVertical({ section: "band", index: 0, bandAuto: true }, -1, {
      ...avail,
      vpn: 0,
      header: 0
    }),
    { section: "band", index: 0, bandAuto: true }
  )
})

test("moveVertical: band on down toggles the pills or falls to dns", () => {
  const avail = { header: 1, vpn: 2, band: true, bandPills: true, wifi: 1, saved: 1 }
  assert.deepEqual(logic.moveVertical({ section: "band", index: 0, bandAuto: true }, 1, avail), {
    section: "band",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical({ section: "band", index: 0, bandAuto: false }, 1, avail), {
    section: "dns",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(
    logic.moveVertical({ section: "band", index: 0, bandAuto: true }, 1, {
      ...avail,
      bandPills: false
    }),
    { section: "dns", index: 0, bandAuto: true }
  )
})

test("moveVertical: dns on up lands on the band, vpn, header or stays", () => {
  const avail = { header: 1, vpn: 2, band: true, bandPills: true, wifi: 1, saved: 1 }
  assert.deepEqual(logic.moveVertical({ section: "dns", index: 0, bandAuto: false }, -1, avail), {
    section: "band",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(
    logic.moveVertical({ section: "dns", index: 0, bandAuto: false }, -1, {
      ...avail,
      bandPills: false
    }),
    { section: "band", index: 0, bandAuto: true }
  )
  assert.deepEqual(
    logic.moveVertical({ section: "dns", index: 0, bandAuto: false }, -1, {
      ...avail,
      band: false
    }),
    { section: "vpn", index: 1, bandAuto: false }
  )
  assert.deepEqual(
    logic.moveVertical({ section: "dns", index: 0, bandAuto: false }, -1, {
      ...avail,
      band: false,
      vpn: 0
    }),
    { section: "header", index: 0, bandAuto: false }
  )
  assert.deepEqual(
    logic.moveVertical({ section: "dns", index: 0, bandAuto: false }, -1, {
      ...avail,
      band: false,
      vpn: 0,
      header: 0
    }),
    { section: "dns", index: 0, bandAuto: false }
  )
})

test("moveVertical: dns on down lands on wifi, saved or stays", () => {
  const avail = { header: 1, vpn: 2, band: true, bandPills: true, wifi: 2, saved: 1 }
  assert.deepEqual(logic.moveVertical({ section: "dns", index: 0, bandAuto: false }, 1, avail), {
    section: "wifi",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(
    logic.moveVertical({ section: "dns", index: 0, bandAuto: false }, 1, { ...avail, wifi: 0 }),
    { section: "saved", index: 0, bandAuto: false }
  )
  assert.deepEqual(
    logic.moveVertical({ section: "dns", index: 0, bandAuto: false }, 1, {
      ...avail,
      wifi: 0,
      saved: 0
    }),
    { section: "dns", index: 0, bandAuto: false }
  )
})

test("moveVertical: wifi moves within its rows, up goes to dns, down to saved or stays", () => {
  const avail = { header: 1, vpn: 1, band: true, bandPills: true, wifi: 2, saved: 1 }
  assert.deepEqual(logic.moveVertical({ section: "wifi", index: 0, bandAuto: false }, 1, avail), {
    section: "wifi",
    index: 1,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical({ section: "wifi", index: 0, bandAuto: false }, -1, avail), {
    section: "dns",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical({ section: "wifi", index: 1, bandAuto: false }, 1, avail), {
    section: "saved",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(
    logic.moveVertical({ section: "wifi", index: 1, bandAuto: false }, 1, { ...avail, saved: 0 }),
    { section: "wifi", index: 1, bandAuto: false }
  )
})

test("moveVertical: an unrecognized section stays put", () => {
  const avail = { header: 1, vpn: 1, band: true, bandPills: true, wifi: 1, saved: 1 }
  assert.deepEqual(logic.moveVertical({ section: "bogus", index: 0, bandAuto: false }, 1, avail), {
    section: "bogus",
    index: 0,
    bandAuto: false
  })
})

test("moveVertical: a null or undefined state never throws and lands on dns/auto", () => {
  const avail = { header: 1, vpn: 1, band: true, bandPills: true, wifi: 1, saved: 1 }
  assert.deepEqual(logic.moveVertical(null, 1, avail), { section: "dns", index: 0, bandAuto: true })
  assert.deepEqual(logic.moveVertical(undefined, -1, avail), {
    section: "dns",
    index: 0,
    bandAuto: true
  })
})

test("moveVertical: a null or undefined avail never throws and reads as nothing available", () => {
  const state = { section: "wifi", index: 0, bandAuto: false }
  assert.deepEqual(logic.moveVertical(state, 1, null), {
    section: "wifi",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical(state, 1, undefined), {
    section: "wifi",
    index: 0,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical({ section: "header", index: 0, bandAuto: false }, 1, null), {
    section: "dns",
    index: 0,
    bandAuto: false
  })
})

test("moveVertical: saved moves within its rows, up goes to wifi or dns, down stays", () => {
  const avail = { header: 1, vpn: 1, band: true, bandPills: true, wifi: 2, saved: 2 }
  assert.deepEqual(logic.moveVertical({ section: "saved", index: 0, bandAuto: false }, 1, avail), {
    section: "saved",
    index: 1,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical({ section: "saved", index: 1, bandAuto: false }, 1, avail), {
    section: "saved",
    index: 1,
    bandAuto: false
  })
  assert.deepEqual(logic.moveVertical({ section: "saved", index: 0, bandAuto: false }, -1, avail), {
    section: "wifi",
    index: 1,
    bandAuto: false
  })
  assert.deepEqual(
    logic.moveVertical({ section: "saved", index: 0, bandAuto: false }, -1, { ...avail, wifi: 0 }),
    { section: "dns", index: 0, bandAuto: false }
  )
})

test("parseSsids treats an empty SSID as no mapping", () => {
  // A uuid whose lookup failed prints "uuid<TAB>" and an empty field; it
  // must not map to "" (nor swallow the next profile's line).
  assert.deepEqual(logic.parseSsids("uuid-1\t\nuuid-2\tHome\n"), { "uuid-2": "Home" })
})

// --- a reveal never chooses (fix wave 2, R1) ------------------------------
// followCursor/cursorConfirmed moved to shared CursorLogic.js (their own
// contract lives in tests/js/cursor-logic.test.js); these pressOutcome
// scenarios still drive them as setup, since pressOutcome's job is to
// respect exactly this cursor-follow safety invariant.

test("pressOutcome: Enter, Enter after Saved empties under the pointer never connects", () => {
  // Mouse-forget the last Saved row: Saved empties and the cursor drops to
  // the last Wi-Fi row with no key, still marked as chosen in Saved.
  const wifi = [{ key: "Home" }, { key: "Cafe" }, { key: "OpenStranger" }]
  const drop = logic.savedEmptyFallback(wifi.length)
  const target = {
    section: drop.section,
    chosen: "saved",
    rows: wifi,
    key: drop.key,
    index: drop.index
  }
  // The first Enter only reveals the outline (the pointer had the cursor)...
  assert.equal(logic.pressOutcome(target, true, false), "reveal")
  // ...and choosing nothing, so the second Enter is refused.
  assert.equal(logic.pressOutcome(target, true, true), "refuse")
  // Even had the section been chosen, the lost key still refuses.
  assert.equal(logic.pressOutcome({ ...target, chosen: "wifi" }, true, true), "refuse")
})

test("pressOutcome: Enter, Enter after a hovered network vanished never hits the one that slid in", () => {
  // The pointer hovered A (a deliberate choice); A drops out of the scan
  // and B slides into its index.
  const before = [{ key: "Home" }, { key: "A" }, { key: "B" }]
  assert.equal(cursor.cursorConfirmed(before, "A", 1), true)
  const after = [{ key: "Home" }, { key: "B" }]
  const next = cursor.followCursor(after, "A", 1)
  const target = { section: "wifi", chosen: "wifi", rows: after, key: next.key, index: next.index }
  assert.equal(logic.pressOutcome(target, true, false), "reveal")
  assert.equal(logic.pressOutcome(target, true, true), "refuse", "B was never chosen")
  // A deliberate pick of B (an arrow move, hover or click) makes it act.
  assert.equal(logic.pressOutcome({ ...target, key: "B" }, true, true), "act")
})

test("pressOutcome ignores a press before any cursor exists and acts on a confirmed row", () => {
  const rows = [{ key: "a" }]
  const target = { section: "wifi", chosen: "wifi", rows: rows, key: "a", index: 0 }
  assert.equal(logic.pressOutcome(target, false, false), "ignore")
  assert.equal(logic.pressOutcome(target, false, true), "ignore")
  assert.equal(logic.pressOutcome(target, true, true), "act")
  assert.equal(
    logic.pressOutcome({ section: "dns", chosen: "dns", fixed: true }, true, true),
    "act"
  )
  assert.equal(logic.pressOutcome(null, true, true), "refuse")
})

test("openChoice preselects Wi-Fi row 0 as the open's deliberate placement", () => {
  assert.deepEqual(logic.openChoice([{ key: "Home" }, { key: "Cafe" }]), {
    chosen: "wifi",
    key: "Home"
  })
  // Then Down reveals and Enter acts on row 0, following it across a re-sort.
  const rows = [{ key: "Cafe" }, { key: "Home" }]
  const next = cursor.followCursor(rows, "Home", 0)
  assert.equal(
    logic.pressOutcome(
      { section: "wifi", chosen: "wifi", rows: rows, key: next.key, index: next.index },
      true,
      true
    ),
    "act"
  )
  // No rows (or a hidden first SSID): nothing is chosen.
  assert.deepEqual(logic.openChoice([]), { chosen: "", key: "" })
  assert.deepEqual(logic.openChoice(undefined), { chosen: "", key: "" })
  assert.deepEqual(logic.openChoice([null]), { chosen: "wifi", key: "" })
})

// --- sidewaysChooses (R3) ---------------------------------------------------

test("sidewaysChooses: a left/right pick in header, band pills and DNS is a deliberate choice", () => {
  assert.equal(logic.sidewaysChooses("header", false), true)
  assert.equal(logic.sidewaysChooses("dns", false), true, "DNS after an automatic evacuation")
  assert.equal(logic.sidewaysChooses("band", false), true)
  assert.equal(logic.sidewaysChooses("band", true), false, "left/right does nothing on Automatic")
  assert.equal(
    logic.sidewaysChooses("wifi", false),
    false,
    "Wi-Fi left/right only moves onto forget"
  )
  assert.equal(logic.sidewaysChooses("saved", false), false)
  assert.equal(logic.sidewaysChooses("vpn", false), false)
})

test("savedEmptyFallback lands on the last Wi-Fi row without choosing it", () => {
  // Forget the last Saved row: the cursor drops into the Wi-Fi list, often
  // onto a weak open network. Enter must not connect to it.
  assert.deepEqual(logic.savedEmptyFallback(4), { section: "wifi", index: 3, key: "" })
  assert.deepEqual(logic.savedEmptyFallback(0), { section: "dns", index: -1, key: "" })
  assert.deepEqual(logic.savedEmptyFallback(undefined), { section: "dns", index: -1, key: "" })
})

// --- enterDecision ---------------------------------------------

test("enterDecision: Saved Enter focuses forget first; Wi-Fi forget never turns into disconnect", () => {
  assert.equal(logic.enterDecision("saved", false, true), "focusForget")
  assert.equal(logic.enterDecision("saved", true, true), "forget")
  assert.equal(logic.enterDecision("wifi", true, true), "forget")
  assert.equal(logic.enterDecision("wifi", true, false), "none")
  assert.equal(logic.enterDecision("wifi", false, false), "activate")
  assert.equal(logic.enterDecision("vpn", false, false), "activate")
})

// --- extrasFollowUp ---------------------------------------------------------------

test("extrasExitFollowUp re-reads when a forget landed after the output but before the exit", () => {
  // updateExtras already ran (not dirty then); the forget's runExtras saw
  // the process still running and only marked it dirty.
  assert.equal(logic.extrasExitFollowUp(true), true)
  assert.equal(logic.extrasExitFollowUp(false), false)
})

test("savedStatusMap: a forget breathes, a failed one reads Couldn't forget", () => {
  assert.deepEqual(logic.savedStatusMap("", ""), {})
  assert.deepEqual(logic.savedStatusMap("u-1", ""), {
    "u-1": { busy: true, failed: false, text: "Forgetting…" }
  })
  assert.deepEqual(logic.savedStatusMap("", "u-2"), {
    "u-2": { busy: false, failed: true, text: "Couldn't forget" }
  })
  // A new forget of the failed row shows as running, not failed.
  assert.deepEqual(logic.savedStatusMap("u-2", "u-2"), {
    "u-2": { busy: true, failed: false, text: "Forgetting…" }
  })
  assert.deepEqual(logic.savedStatusMap(undefined, null), {})
})

test("extrasFollowUp re-reads after a forget that landed mid-poll, and settles only on a fresh read", () => {
  assert.deepEqual(logic.extrasFollowUp(true, false), { rerun: true, settle: false })
  assert.deepEqual(logic.extrasFollowUp(false, true), { rerun: false, settle: false })
  assert.deepEqual(logic.extrasFollowUp(true, true), { rerun: true, settle: false })
  assert.deepEqual(logic.extrasFollowUp(false, false), { rerun: false, settle: true })
})

// --- VPN ----------------------------------------------------------------------------

test("vpnCommand waits up to 20 s and targets the uuid", () => {
  assert.deepEqual(logic.vpnCommand("uuid-1", false), [
    "nmcli",
    "--wait",
    "20",
    "connection",
    "up",
    "uuid",
    "uuid-1"
  ])
  assert.deepEqual(logic.vpnCommand("uuid-1", true), [
    "nmcli",
    "--wait",
    "20",
    "connection",
    "down",
    "uuid",
    "uuid-1"
  ])
})

test("vpnFailureText names what failed", () => {
  assert.equal(logic.vpnFailureText(true), "Couldn't disconnect")
  assert.equal(logic.vpnFailureText(false), "Couldn't connect")
})

// --- keyHint ----------------------------------------------------------------------------

test("keyHint says what Enter does in each section", () => {
  assert.equal(logic.keyHint("wifi"), "↑↓ move · ←→ pick · enter connect · x forget · tab next")
  assert.equal(logic.keyHint("saved"), "↑↓ move · enter/→ select forget · x forget · tab next")
  assert.equal(logic.keyHint("vpn"), "↑↓ move · enter toggle VPN · tab next")
  assert.equal(logic.keyHint("dns"), "↑↓ move · ←→ pick · enter apply · tab next")
  assert.equal(logic.keyHint("band"), "↑↓ move · ←→ pick · enter apply · tab next")
  assert.equal(logic.keyHint("header"), "↑↓ move · ←→ pick · enter apply · tab next")
  assert.equal(logic.keyHint(""), "↑↓ move · ←→ pick · enter connect · x forget · tab next")
})

// --- keyTargetConfirmed ------------------------------------------------------------

test("keyTargetConfirmed refuses a section the cursor was moved into automatically", () => {
  const rows = [{ key: "Home" }, { key: "OpenCafe" }]
  // The user chose Saved; Saved emptied and the cursor fell into Wi-Fi.
  assert.equal(
    logic.keyTargetConfirmed({
      section: "wifi",
      chosen: "saved",
      rows: rows,
      key: "OpenCafe",
      index: 1
    }),
    false
  )
  // The band hid under the cursor and stock sent it to DNS.
  assert.equal(logic.keyTargetConfirmed({ section: "dns", chosen: "band", fixed: true }), false)
  assert.equal(logic.keyTargetConfirmed({ section: "dns", chosen: "dns", fixed: true }), true)
  assert.equal(
    logic.keyTargetConfirmed({
      section: "wifi",
      chosen: "wifi",
      rows: rows,
      key: "OpenCafe",
      index: 1
    }),
    true
  )
  assert.equal(
    logic.keyTargetConfirmed({
      section: "wifi",
      chosen: "wifi",
      rows: rows,
      key: "Home",
      index: 1
    }),
    false
  )
  assert.equal(
    logic.keyTargetConfirmed({ section: "", chosen: "", fixed: true }),
    false,
    "no choice at all"
  )
  assert.equal(logic.keyTargetConfirmed(null), false)
})
