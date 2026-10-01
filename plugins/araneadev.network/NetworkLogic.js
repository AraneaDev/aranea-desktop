// Pure rules for the Aranea network dropdown (Panel.qml): parsing nmcli and
// `ip -j` output, building the interface/VPN/saved-network rows, the
// throughput graph's points and vertical keyboard navigation. No QML, no
// I/O; tests/js/network-logic.test.js runs this under Node.

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
 * Parses `nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,TIMESTAMP connection show` output.
 * @param {string|undefined} text - the command's stdout
 * @returns {Array<{name: string, uuid: string, type: string, device: string, active: boolean, timestamp: number}>} the connections
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
      timestamp: isFinite(ts) ? ts : 0
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
 * as `splitTerse` does.
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
    out[line.substring(0, tab)] = unescapeTerse(line.substring(tab + 1))
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
 * Builds the interface rows (Wi-Fi, Ethernet, mobile, WireGuard, tunnel)
 * shown above the VPN section.
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
 * Builds the VPN rows (VPN and WireGuard connections) shown below the
 * interface section.
 * @param {Array<{name: string, uuid: string, type: string, device: string, active: boolean, timestamp: number}>|undefined} connections - from `parseConnections`
 * @param {Record<string, string>|undefined} addrs - from `parseAddrs`
 * @returns {Array<{key: string, glyph: string, label: string, detail: string, active: boolean}>} the rows
 */
function vpnRows(connections, addrs) {
  var list = Array.isArray(connections) ? connections : []
  var addrMap = addrs || {}
  var rows = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (c.type !== "vpn" && c.type !== "wireguard") continue
    var detail = c.type === "wireguard" ? "WireGuard" : "VPN"
    var ip = c.active ? addrMap[c.device] : undefined
    if (ip) detail += " · " + ip
    rows.push({
      key: c.uuid,
      glyph: String.fromCodePoint(0xf0582),
      label: c.name,
      detail: detail,
      active: !!c.active
    })
  }
  rows.sort(compareActiveThenLabel)
  return rows
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
 * as a scanned network.
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
 * Appends a throughput sample to the rolling history kept for the graph,
 * resetting it when the sampled interface changes.
 * @param {Array<{iface: string, rx: number, tx: number}>|undefined} history - the samples kept so far
 * @param {{iface: string, rx: number, tx: number}} sample - the new sample
 * @param {number} max - the most samples to keep
 * @returns {Array<{iface: string, rx: number, tx: number}>} a new array; `history` is never mutated
 */
function pushSample(history, sample, max) {
  var hist = Array.isArray(history) ? history : []
  var s = sample
  var last = hist[hist.length - 1]
  if (!last || last.iface !== s.iface) return [s]
  var next = hist.concat([s])
  var limit = Math.max(1, Number(max) || 1)
  if (next.length > limit) next = next.slice(next.length - limit)
  return next
}

/**
 * Turns throughput samples into plot points for the rx/tx graph.
 * @param {Array<{iface: string, rx: number, tx: number}>|undefined} samples - the rolling history, oldest first
 * @param {number} slots - the graph's time slots (at least 2)
 * @param {number} width - the plot width, in pixels
 * @param {number} height - the plot height, in pixels
 * @param {number} floor - the minimum scale, so a near-idle graph doesn't look noisy
 * @returns {{rx: Array<{x: number, y: number}>, tx: Array<{x: number, y: number}>, scale: number}} the points and the scale used
 */
function graphPoints(samples, slots, width, height, floor) {
  var list = Array.isArray(samples) ? samples : []
  var f = Number(floor) || 0
  if (list.length === 0) return { rx: [], tx: [], scale: f }

  var scale = f
  for (var i = 0; i < list.length; i++) {
    var rxValue = Math.max(0, Number(list[i].rx) || 0)
    var txValue = Math.max(0, Number(list[i].tx) || 0)
    if (rxValue > scale) scale = rxValue
    if (txValue > scale) scale = txValue
  }

  var n = list.length
  var w = Number(width) || 0
  var h = Number(height) || 0
  var effectiveSlots = Number(slots) < 2 ? 2 : Number(slots)
  var step = w / (effectiveSlots - 1)

  var rx = []
  var tx = []
  for (var j = 0; j < n; j++) {
    var x = w - (n - 1 - j) * step
    var rxV = Math.max(0, Number(list[j].rx) || 0)
    var txV = Math.max(0, Number(list[j].tx) || 0)
    rx.push({ x: x, y: h - (rxV / scale) * h })
    tx.push({ x: x, y: h - (txV / scale) * h })
  }

  return { rx: rx, tx: tx, scale: scale }
}

/**
 * The next keyboard-navigation state after moving vertically, following the
 * dropdown's header/VPN/band/DNS/wifi/saved section order and skipping any
 * section with nothing in it.
 * @param {{section: string, index: number, bandAuto: boolean}} state - the current navigation state
 * @param {number} dy - the direction: negative for up, positive for down
 * @param {{header: number, vpn: number, band: boolean, bandPills: boolean, wifi: number, saved: number}} avail - what's available to land on
 * @returns {{section: string, index: number, bandAuto: boolean}} the next state
 */
function moveVertical(state, dy, avail) {
  var s = state
  var a = avail
  var section = s.section
  var index = Number(s.index) || 0
  var bandAuto = !!s.bandAuto
  var header = Number(a.header) || 0
  var vpn = Number(a.vpn) || 0
  var band = !!a.band
  var bandPills = !!a.bandPills
  var wifi = Number(a.wifi) || 0
  var saved = Number(a.saved) || 0
  var here = { section: section, index: index, bandAuto: bandAuto }

  if (section === "header") {
    if (dy < 0) return here
    if (vpn > 0) return { section: "vpn", index: 0, bandAuto: bandAuto }
    if (band) return { section: "band", index: 0, bandAuto: true }
    return { section: "dns", index: 0, bandAuto: bandAuto }
  }

  if (section === "vpn") {
    var vpnNext = index + dy
    if (vpnNext < 0) {
      if (header > 0) return { section: "header", index: 0, bandAuto: bandAuto }
      return here
    }
    if (vpnNext > vpn - 1) {
      if (band) return { section: "band", index: 0, bandAuto: true }
      return { section: "dns", index: 0, bandAuto: bandAuto }
    }
    return { section: "vpn", index: vpnNext, bandAuto: bandAuto }
  }

  if (section === "band") {
    if (dy < 0) {
      if (!bandAuto) return { section: "band", index: 0, bandAuto: true }
      if (vpn > 0) return { section: "vpn", index: vpn - 1, bandAuto: bandAuto }
      if (header > 0) return { section: "header", index: 0, bandAuto: bandAuto }
      return here
    }
    if (bandAuto && bandPills) return { section: "band", index: 0, bandAuto: false }
    return { section: "dns", index: 0, bandAuto: bandAuto }
  }

  if (section === "dns") {
    if (dy < 0) {
      if (band) return { section: "band", index: 0, bandAuto: !bandPills }
      if (vpn > 0) return { section: "vpn", index: vpn - 1, bandAuto: bandAuto }
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

if (typeof module !== "undefined")
  module.exports = {
    splitTerse: splitTerse,
    splitSections: splitSections,
    parseDevices: parseDevices,
    parseConnections: parseConnections,
    parseAddrs: parseAddrs,
    parseSsids: parseSsids,
    interfaceRows: interfaceRows,
    vpnRows: vpnRows,
    savedRows: savedRows,
    lastUsedText: lastUsedText,
    pushSample: pushSample,
    graphPoints: graphPoints,
    moveVertical: moveVertical
  }
