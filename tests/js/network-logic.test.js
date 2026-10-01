// Logic contract for the Aranea network dropdown (NetworkLogic.js).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.network/NetworkLogic.js"))
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

// --- pushSample ------------------------------------------------------------

test("pushSample starts fresh, appends, trims at max, and never mutates its input", () => {
  const empty = []
  const first = logic.pushSample(empty, { iface: "wlp2s0", rx: 1, tx: 2 }, 3)
  assert.deepEqual(first, [{ iface: "wlp2s0", rx: 1, tx: 2 }])
  assert.deepEqual(empty, [])

  const second = logic.pushSample(first, { iface: "wlp2s0", rx: 2, tx: 3 }, 3)
  assert.deepEqual(second, [
    { iface: "wlp2s0", rx: 1, tx: 2 },
    { iface: "wlp2s0", rx: 2, tx: 3 }
  ])
  assert.deepEqual(first, [{ iface: "wlp2s0", rx: 1, tx: 2 }])

  const third = logic.pushSample(second, { iface: "wlp2s0", rx: 3, tx: 4 }, 2)
  assert.deepEqual(third, [
    { iface: "wlp2s0", rx: 2, tx: 3 },
    { iface: "wlp2s0", rx: 3, tx: 4 }
  ])
  assert.deepEqual(second.length, 2)

  const switched = logic.pushSample(third, { iface: "enp3s0", rx: 9, tx: 9 }, 2)
  assert.deepEqual(switched, [{ iface: "enp3s0", rx: 9, tx: 9 }])
})

// --- graphPoints -----------------------------------------------------------

test("graphPoints at idle sits on the baseline", () => {
  const samples = [
    { iface: "wlp2s0", rx: 0, tx: 0 },
    { iface: "wlp2s0", rx: 0, tx: 0 }
  ]
  const points = logic.graphPoints(samples, 2, 100, 50, 10)
  assert.equal(points.scale, 10)
  assert.ok(points.rx.every((p) => p.y === 50))
  assert.ok(points.tx.every((p) => p.y === 50))
})

test("graphPoints at a peak touches the top", () => {
  const samples = [
    { iface: "wlp2s0", rx: 0, tx: 0 },
    { iface: "wlp2s0", rx: 100, tx: 0 }
  ]
  const points = logic.graphPoints(samples, 2, 100, 50, 10)
  assert.equal(points.scale, 100)
  assert.equal(points.rx[1].y, 0)
  assert.equal(points.rx[0].y, 50)
})

test("graphPoints uses the floor when every sample is below it", () => {
  const samples = [{ iface: "wlp2s0", rx: 1, tx: 1 }]
  const points = logic.graphPoints(samples, 4, 100, 50, 1000)
  assert.equal(points.scale, 1000)
})

test("graphPoints treats negative values as 0 and places the newest sample at x === width", () => {
  const samples = [
    { iface: "wlp2s0", rx: -5, tx: -5 },
    { iface: "wlp2s0", rx: 5, tx: 5 },
    { iface: "wlp2s0", rx: 10, tx: 0 }
  ]
  const points = logic.graphPoints(samples, 3, 90, 50, 1)
  assert.equal(points.rx[0].y, 50)
  assert.equal(points.rx[2].x, 90)
  assert.equal(points.rx[0].x, 90 - 2 * (90 / 2))
})

test("graphPoints treats slots below 2 as 2", () => {
  const samples = [
    { iface: "wlp2s0", rx: 1, tx: 1 },
    { iface: "wlp2s0", rx: 2, tx: 2 }
  ]
  const points = logic.graphPoints(samples, 1, 10, 10, 1)
  assert.equal(points.rx[1].x, 10)
  assert.equal(points.rx[0].x, 0)
})

test("graphPoints on empty samples returns {rx: [], tx: [], scale: floor}", () => {
  assert.deepEqual(logic.graphPoints([], 4, 100, 50, 7), { rx: [], tx: [], scale: 7 })
  assert.deepEqual(logic.graphPoints(undefined, 4, 100, 50, 7), { rx: [], tx: [], scale: 7 })
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
