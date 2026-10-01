/**
 * Parses the tab-separated status line the bar icon's helper prints: kind,
 * label, signal strength and frequency.
 * @param {*} raw - the raw tab-separated line, or falsy
 * @returns {{kind: string, label: string, signalStrength: number, frequency: string}} the parsed status
 */
function parseNetworkStatus(raw) {
  var parts = String(raw || "disconnected\t\t\t")
    .replace(/\r?\n+$/, "")
    .split("\t")
  return {
    kind: parts[0] || "disconnected",
    label: parts[1] || "",
    signalStrength: parts[2] ? parseInt(parts[2], 10) : -1,
    frequency: parts[3] || ""
  }
}

/**
 * Signal-strength glyph for a Wi-Fi reading, from weakest to strongest.
 * @param {*} strength - the signal strength, 0-100
 * @returns {string} the bar glyph
 */
function wifiIconFor(strength) {
  var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
  var index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))
  return icons[index]
}

/**
 * The bar icon's glyph for a connection kind and (for Wi-Fi) its signal.
 * @param {string} kind - "wifi" | "ethernet" | "disconnected"
 * @param {number} signalStrength - the Wi-Fi signal strength, 0-100, or -1
 * @returns {string} the bar glyph
 */
function connectionIcon(kind, signalStrength) {
  if (kind === "wifi") return wifiIconFor(signalStrength)
  if (kind === "ethernet") return "󰈀"
  return "󰤮"
}

/**
 * Formats a link speed in Mbps for the header detail, e.g. "2.5gbit".
 * @param {*} mbps - the link speed in Mbps
 * @returns {string} the formatted speed, or "" when mbps is not usable
 */
function formatHeaderSpeed(mbps) {
  var v = parseInt(mbps, 10)
  if (!v || v < 0) return ""
  if (v >= 1000) return (v / 1000).toFixed(v % 1000 === 0 ? 0 : 1) + "gbit"
  return v + "mbit"
}

/**
 * Formats a Wi-Fi frequency in MHz for the header detail, e.g. "5ghz".
 * @param {*} mhz - the frequency in MHz
 * @returns {string} the formatted frequency, or "" when mhz is not usable
 */
function formatHeaderFreq(mhz) {
  var v = parseFloat(mhz)
  if (!v) return ""

  if (v >= 2400 && v < 2500) return "2.4ghz"
  if (v >= 4900 && v < 5925) return "5ghz"
  if (v >= 5925 && v < 7125) return "6ghz"
  if (v >= 57000 && v < 71000) return "60ghz"

  var ghz = v / 1000
  return ghz.toFixed(ghz % 1 === 0 ? 0 : 1) + "ghz"
}

/**
 * Wi-Fi band state belongs in the selector section, not beside the hero name.
 * Ethernet has no equivalent selector, so keep its negotiated link speed here.
 * @param {*} info - the connection info ({type, speed, ...}), or falsy
 * @returns {string} the parenthetical header detail text, or ""
 */
function headerDetail(info) {
  var value = info || {}
  if (value.type === "ethernet") return formatHeaderSpeed(value.speed || "")
  return ""
}

/**
 * Display label for a Wi-Fi band value.
 * @param {*} band - "auto", a band like "5", or falsy
 * @returns {string} the display label, or "" when band is falsy
 */
function bandLabel(band) {
  if (band === "auto") return "Auto"
  if (!band) return ""
  return band + "ghz"
}

/**
 * Under Automatic the pills are hidden, so the header carries the live band
 * instead -- "WI-FI BAND: 2.4GHZ". Once a band is pinned the pills are on
 * screen and say it themselves, so the header drops back to a plain label.
 * @param {string} selected - the pinned band choice, or "auto"
 * @param {string} current - the band the radio is actually on
 * @returns {string} the band section's header text
 */
function bandSectionTitle(selected, current) {
  if (selected !== "auto") return "WI-FI BAND"

  var label = bandLabel(current)
  if (label === "") return "WI-FI BAND"

  return "WI-FI BAND: " + label.toUpperCase()
}

/**
 * Tooltip text for a band pill.
 * @param {*} band - "auto", a band like "5", or falsy
 * @returns {string} the tooltip text, or "" when band is falsy
 */
function bandTooltip(band) {
  if (band === "auto") return "Let Wi-Fi pick the band"
  if (!band) return ""
  return "Stay on " + bandLabel(band)
}

/**
 * Parses `omarchy-network-band`'s key/value output into the current band,
 * pinned selection and available bands.
 * @param {*} raw - the raw key/value output, or falsy
 * @returns {{band: string, selected: string, available: Array<string>}} the parsed status
 */
function parseBandStatus(raw) {
  var next = parseKeyValue(raw)
  var tokens = String(next.available || "").split(" ")
  var available = []

  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "") available.push(tokens[i])
  }

  return {
    band: next.band || "",
    selected: next.selected || "auto",
    available: available
  }
}

/**
 * Decodes an SSID that may carry `iw`-style `\xHH` escapes for non-printable
 * or non-ASCII bytes, into a proper UTF-8 string.
 * @param {*} value - the raw (possibly escaped) SSID text
 * @returns {string} the decoded SSID, or the raw text when decoding fails
 */
function decodeIwSsid(value) {
  var raw = String(value || "")

  try {
    var encoded = ""

    for (var i = 0; i < raw.length; i++) {
      if (
        raw[i] === "\\" &&
        raw[i + 1] === "x" &&
        /^[0-9a-f]{2}$/i.test(raw.substring(i + 2, i + 4))
      ) {
        var hex = raw.substring(i + 2, i + 4)
        var byte = parseInt(hex, 16)
        encoded +=
          byte < 32 || byte === 127 ? encodeURIComponent(raw.substring(i, i + 4)) : "%" + hex
        i += 3
      } else {
        encoded += encodeURIComponent(raw[i])
      }
    }

    return decodeURIComponent(encoded)
  } catch (error) {
    return raw
  }
}

/**
 * Parses tab-separated `key\tvalue` lines into a plain object, decoding the
 * `ssid` key specially.
 * @param {*} raw - the raw key/value output, or falsy
 * @returns {{[key: string]: string}} the parsed key/value pairs
 */
function parseKeyValue(raw) {
  /** @type {{[key: string]: string}} */
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var idx = line.indexOf("\t")
    if (idx === -1) continue
    var key = line.substring(0, idx)
    var value = line.substring(idx + 1)
    next[key] = key === "ssid" ? decodeIwSsid(value) : value.trim()
  }
  return next
}

/**
 * Computes the next download/upload rate state from the previous sample and
 * a fresh one. Resets to zero when the interface changed or this is the
 * first sample.
 * @param {*} previous - the previous throughput state
 * @param {*} next - the freshly parsed status sample
 * @param {number} now - the current time, in seconds
 * @returns {{prevIface: string, prevRxBytes: number, prevTxBytes: number, prevSampleTime: number, downloadRate: number, uploadRate: number}} the next throughput state
 */
function throughputState(previous, next, now) {
  var prev = previous || {}
  var sample = next || {}
  var iface = sample.iface || ""
  var rx = parseFloat(sample.rx_bytes || "0")
  var tx = parseFloat(sample.tx_bytes || "0")
  var previousTime = Number(prev.prevSampleTime || 0)

  if (iface !== (prev.prevIface || "") || previousTime === 0) {
    return {
      prevIface: iface,
      prevRxBytes: rx,
      prevTxBytes: tx,
      prevSampleTime: now,
      downloadRate: 0,
      uploadRate: 0
    }
  }

  var downloadRate = Number(prev.downloadRate || 0)
  var uploadRate = Number(prev.uploadRate || 0)
  var dt = now - previousTime
  if (dt > 0) {
    downloadRate = Math.max(0, (rx - Number(prev.prevRxBytes || 0)) / dt)
    uploadRate = Math.max(0, (tx - Number(prev.prevTxBytes || 0)) / dt)
  }

  return {
    prevIface: iface,
    prevRxBytes: rx,
    prevTxBytes: tx,
    prevSampleTime: now,
    downloadRate: downloadRate,
    uploadRate: uploadRate
  }
}

/**
 * Parses one ping sample into a finite, non-negative latency, or null when
 * it is missing or invalid (a dropped ping).
 * @param {*} raw - the raw latency value
 * @returns {?number} the latency in ms, or null
 */
function pingSampleValue(raw) {
  var value = parseFloat(raw)
  if (!isFinite(value) || value < 0) return null
  return value
}

/**
 * Appends a parsed ping sample to a window of samples, trimmed to limit.
 * @param {*} samples - the existing samples
 * @param {*} raw - the raw latency value to append
 * @param {number} limit - the maximum window size
 * @returns {Array<?number>} the updated window
 */
function appendPingSample(samples, raw, limit) {
  var values = Array.isArray(samples) ? samples.slice() : []

  values.push(pingSampleValue(raw))
  while (values.length > limit) values.shift()

  return values
}

/**
 * The average of the most recent limit samples, ignoring dropped pings.
 * @param {*} samples - the ping samples
 * @param {*} limit - how many of the most recent samples to average
 * @returns {number} the average latency in ms, or -1 when there are none
 */
function averagePingLatency(samples, limit) {
  var values = Array.isArray(samples) ? samples : []
  var sampleLimit = Math.max(1, parseInt(limit, 10) || values.length || 1)
  var total = 0
  var count = 0

  for (var i = Math.max(0, values.length - sampleLimit); i < values.length; i++) {
    var value = values[i]
    if (typeof value !== "number" || !isFinite(value) || value < 0) continue
    total += value
    count++
  }

  return count > 0 ? total / count : -1
}

/**
 * The percentage of samples that were dropped (null).
 * @param {*} samples - the ping samples
 * @returns {number} the packet loss percentage, 0-100
 */
function pingPacketLossPercent(samples) {
  var values = Array.isArray(samples) ? samples : []
  if (values.length === 0) return 0

  var lost = 0
  for (var i = 0; i < values.length; i++) {
    if (values[i] === null) lost++
  }

  return Math.round((lost / values.length) * 100)
}

/**
 * Formats a packet-loss percentage for display.
 * @param {*} percent - the packet loss percentage
 * @param {*} hasSamples - whether a probe has returned a sample yet
 * @returns {string} the formatted percentage, or "--" when hasSamples is false
 */
function formatPacketLoss(percent, hasSamples) {
  if (hasSamples === false) return "--"

  var value = parseInt(percent, 10)
  if (!value || value < 0) return "0%"
  return value + "%"
}

/**
 * Computes the next ping-latency state from the previous state and a fresh
 * sample. Resets the sample windows when the interface changed.
 * @param {*} previous - the previous ping-latency state
 * @param {*} next - the freshly parsed status sample
 * @param {*} limit - the sample window size
 * @param {*} averageLimit - how many of the most recent samples to average
 * @returns {{pingIface: string, routerPingSamples: Array<?number>, internetPingSamples: Array<?number>, routerPingLatency: number, internetPingLatency: number, internetPingPacketLoss: number}} the next ping-latency state
 */
function pingLatencyState(previous, next, limit, averageLimit) {
  var prev = previous || {}
  var sample = next || {}
  var iface = sample.iface || ""
  var window = Math.max(1, parseInt(limit, 10) || 5)
  var averageWindow = Math.max(1, parseInt(averageLimit, 10) || window)
  var reset = iface === "" || iface !== (prev.pingIface || "")
  var routerSamples = reset ? [] : prev.routerPingSamples
  var internetSamples = reset ? [] : prev.internetPingSamples

  routerSamples =
    sample.router_ping_ms === undefined
      ? []
      : appendPingSample(routerSamples, sample.router_ping_ms, window)
  internetSamples =
    sample.internet_ping_ms === undefined
      ? []
      : appendPingSample(internetSamples, sample.internet_ping_ms, window)

  return {
    pingIface: iface,
    routerPingSamples: routerSamples,
    internetPingSamples: internetSamples,
    routerPingLatency: averagePingLatency(routerSamples, averageWindow),
    internetPingLatency: averagePingLatency(internetSamples, averageWindow),
    internetPingPacketLoss: pingPacketLossPercent(internetSamples)
  }
}

/**
 * Formats a byte count for display, choosing B/KB/MB/GB.
 * @param {*} bytes - the byte count
 * @returns {string} the formatted size
 */
function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 1024) return Math.round(n) + " B"
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
  if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB"
  return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB"
}

/**
 * Formats a bytes/sec rate for display.
 * @param {*} bytesPerSec - the rate in bytes/sec
 * @returns {string} the formatted rate
 */
function formatRate(bytesPerSec) {
  return formatBytes(bytesPerSec) + "/s"
}

/**
 * `hasSamples` false means no probe has come back yet, which is different
 * from a probe that timed out. The rows stay mounted through that gap and
 * read "--" so the grid doesn't reflow a second after the panel opens.
 * @param {*} ms - the ping latency in ms
 * @param {*} hasSamples - whether a probe has returned a sample yet
 * @returns {string} the formatted latency, "--", or "Timeout"
 */
function formatPingLatency(ms, hasSamples) {
  if (hasSamples === false) return "--"

  var value = parseFloat(ms)
  if (!isFinite(value) || value < 0) return "Timeout"
  return value.toFixed(value > 0 && value < 10 ? 1 : 0) + " ms"
}

/**
 * The primitives-only row for a live WifiNetwork (see the comment inside
 * on why the object itself is never put in model data).
 * @param {*} network - the live WifiNetwork object, or falsy
 * @returns {?object} the primitives-only row, or null when network is falsy
 */
function wifiRow(network) {
  if (!network) return null
  // Primitives only: rows become list-model data, so a WifiNetwork here puts a
  // live QObject wrapper in every delegate's var property. NetworkManager churn
  // (scans, AP removals) can destroy the object while a delegate is still
  // incubating, which segfaults quickshell in wrap_slowPath on the dangling
  // wrapper. Callers that need the object resolve it via networkForSsid().
  return {
    connected: !!network.connected,
    known: !!network.known,
    ssid: network.name || "",
    signal: Math.round((network.signalStrength || 0) * 100),
    security: network.security
  }
}

/**
 * Sorts Wi-Fi rows: connected first, then known, then by signal strength.
 * @param {*} rows - the Wi-Fi rows
 * @returns {Array<*>} a new, sorted array
 */
function sortWifiRows(rows) {
  var nets = Array.isArray(rows) ? rows.slice() : []
  nets.sort(function (a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    if (a.known !== b.known) return a.known ? -1 : 1
    return b.signal - a.signal
  })
  return nets
}

/**
 * The section header text ("KNOWN NETWORKS"/"OTHER NETWORKS") for a row,
 * shown only on the first row of each section.
 * @param {*} wifiNetworks - the sorted Wi-Fi rows
 * @param {number} index - the row's index
 * @returns {string} the section header text, or "" mid-section
 */
function wifiSectionTitle(wifiNetworks, index) {
  var networks = Array.isArray(wifiNetworks) ? wifiNetworks : []
  if (index < 0 || index >= networks.length) return ""

  var net = networks[index]
  if (!net) return ""

  if (net.known && index === 0) return "KNOWN NETWORKS"
  if (!net.known && (index === 0 || (networks[index - 1] && networks[index - 1].known)))
    return "OTHER NETWORKS"
  return ""
}

/**
 * OWE (Enhanced Open) encrypts traffic without authenticating the user, so
 * it has no credentials to collect. The panel's lock is a
 * credentials-required affordance, so OWE should neither show it nor open
 * its attached prompt. Only explicit passwordless types bypass the prompt;
 * unknown security stays credentialed as the conservative fallback.
 * @param {*} security - the network's security type
 * @param {*} openSecurity - the WifiSecurityType.Open value
 * @param {*} oweSecurity - the WifiSecurityType.Owe value
 * @returns {boolean} true when the network requires a passphrase
 */
function requiresCredentials(security, openSecurity, oweSecurity) {
  // Only explicit passwordless types bypass the prompt. Unknown security
  // stays credentialed as the conservative fallback.
  return security !== openSecurity && security !== oweSecurity
}

/**
 * Whether network can be forgotten: known (saved) and not connected.
 * @param {*} network - the Wi-Fi row or live network object
 * @returns {boolean} true when the network can be forgotten
 */
function canForgetNetwork(network) {
  return !!(network && network.known && !network.connected)
}

// The password arrives on stdin and reaches nmcli through the scriptable
// `connection edit` editor -- argv is world-readable in /proc, so the secret
// must never be an argument (printf is a bash builtin, so no process spawns
// with it either).
var enterpriseConnectScript =
  "u=$(uuidgen); IFS= read -r pw;" +
  ' nmcli connection add type wifi con-name "$1" ssid "$1" connection.uuid "$u"' +
  " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" +
  ' 802-1x.identity "$2" 802-1x.auth-timeout 8 >/dev/null' +
  ' && printf \'set 802-1x.password %s\\nsave\\nquit\\n\' "$pw" | nmcli connection edit uuid "$u" >/dev/null' +
  ' && nmcli connection up uuid "$u"' +
  ' || { nmcli connection delete uuid "$u" >/dev/null 2>&1; false; }'

/**
 * Human-readable reason a connection attempt failed.
 * @param {*} reason - the ConnectionFailReason value
 * @param {*} needsCredentials - whether the network requires a passphrase
 * @param {*} reasons - the ConnectionFailReason values, keyed by name
 * @returns {string} the human-readable failure reason
 */
function networkFailureReason(reason, needsCredentials, reasons) {
  var r = reasons || {}
  if (needsCredentials && reason === r.NoSecrets) return "Passphrase required"
  if (needsCredentials && reason === r.WifiAuthTimeout) return "Wrong password"
  if (reason === r.WifiNetworkLost) return "Network lost"
  if (reason === r.WifiClientDisconnected) return "Disconnected"
  if (reason === r.WifiClientFailed) return "Connection failed"
  return "Failed to connect"
}

/**
 * Whether a failed connect should reopen the passphrase prompt. NoSecrets
 * means credentials are missing only for a network that actually uses them.
 * An auth timeout on such a network means the saved passphrase is wrong (the
 * same profile a first failed attempt leaves behind as "known"), so the user
 * needs a chance to re-enter it -- connectWithPsk overwrites the stored PSK
 * on submit.
 * @param {*} reason - the ConnectionFailReason value
 * @param {*} needsCredentials - whether the network requires a passphrase
 * @param {*} reasons - the ConnectionFailReason values, keyed by name
 * @returns {boolean} true when the prompt should reopen
 */
function shouldRepromptPassphrase(reason, needsCredentials, reasons) {
  var r = reasons || {}
  if (!needsCredentials) return false
  return reason === r.NoSecrets || reason === r.WifiAuthTimeout
}

if (typeof module !== "undefined") {
  module.exports = {
    parseNetworkStatus: parseNetworkStatus,
    wifiIconFor: wifiIconFor,
    connectionIcon: connectionIcon,
    formatHeaderSpeed: formatHeaderSpeed,
    formatHeaderFreq: formatHeaderFreq,
    headerDetail: headerDetail,
    bandLabel: bandLabel,
    bandSectionTitle: bandSectionTitle,
    bandTooltip: bandTooltip,
    parseBandStatus: parseBandStatus,
    decodeIwSsid: decodeIwSsid,
    parseKeyValue: parseKeyValue,
    throughputState: throughputState,
    pingLatencyState: pingLatencyState,
    pingPacketLossPercent: pingPacketLossPercent,
    formatPacketLoss: formatPacketLoss,
    formatBytes: formatBytes,
    formatRate: formatRate,
    formatPingLatency: formatPingLatency,
    wifiRow: wifiRow,
    sortWifiRows: sortWifiRows,
    wifiSectionTitle: wifiSectionTitle,
    requiresCredentials: requiresCredentials,
    canForgetNetwork: canForgetNetwork,
    enterpriseConnectScript: enterpriseConnectScript,
    networkFailureReason: networkFailureReason,
    shouldRepromptPassphrase: shouldRepromptPassphrase
  }
}
