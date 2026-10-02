// Shared rules for the own-app VPNs config file
// (~/.config/aranea/vpn-apps.json), used by araneadev.vpn: parsing both the
// bare-array and {apps, profiles} object forms, glob matching an interface
// name, an own-app VPN's detected state and matched interface, which
// parsed config a panel applies, and the Network status line shown for
// every up VPN (NetworkManager and own-app).
// No QML, no I/O; tests/js/vpn-apps.test.js runs this under Node.

/**
 * One parsed own-app VPN entry.
 * @typedef {{name: string, label: string, detect: {interface?: string, process?: string}, open: string[]}} VpnApp
 */

/**
 * Whether NAME matches PATTERN, a shell-style glob using only `*` (any run
 * of characters, including none) and `?` (exactly one character); every
 * other character matches itself literally. Matching is case-sensitive, as
 * interface and process names are.
 * @param {string|undefined} pattern - the glob pattern
 * @param {string|undefined} name - the name to test
 * @returns {boolean} true when it matches
 */
function globMatch(pattern, name) {
  if (typeof pattern !== "string" || typeof name !== "string") return false
  var re = ""
  for (var i = 0; i < pattern.length; i++) {
    var c = pattern[i]
    if (c === "*") re += ".*"
    else if (c === "?") re += "."
    else re += c.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }
  return new RegExp("^" + re + "$").test(name)
}

/**
 * Parses ~/.config/aranea/vpn-apps.json, accepting both the bare-array form
 * (just the list of apps) and the `{apps, profiles}` object form. Each app
 * entry needs a `name` and an array `open`; anything missing either (a
 * non-object entry, no name, a missing or non-array `open`, such as a bare
 * string) is dropped and named in `error`, without aborting the rest of the
 * file; so is a later entry repeating an earlier one's `name` (row keys are
 * built from names, so they must be unique). A valid entry's `label`
 * defaults to its `name` and `detect` to `{}`.
 * Profile entries map a NetworkManager connection name to `{otp}`,
 * defaulting `otp` to `"append"` for anything other than `"challenge"`.
 * @param {string|undefined} text - the file's contents
 * @returns {{apps: VpnApp[], profiles: Record<string, {otp: string}>, error: string}} the parsed config; `error` is "" when every entry was valid
 */
function parseAppsConfig(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text))
  } catch (e) {
    return { apps: [], profiles: {}, error: "invalid JSON" }
  }

  var rawApps
  /** @type {Record<string, any>} */
  var rawProfiles = {}
  if (Array.isArray(parsed)) {
    rawApps = parsed
  } else if (parsed && typeof parsed === "object" && Array.isArray(parsed.apps)) {
    rawApps = parsed.apps
    if (parsed.profiles && typeof parsed.profiles === "object") rawProfiles = parsed.profiles
  } else {
    return { apps: [], profiles: {}, error: 'expected an array or an object with "apps"' }
  }

  var apps = []
  var dropped = []
  /** @type {string[]} */
  var seen = []
  for (var i = 0; i < rawApps.length; i++) {
    var entry = rawApps[i]
    var name =
      entry && typeof entry === "object" && typeof entry.name === "string" ? entry.name : ""
    var open = entry && typeof entry === "object" && Array.isArray(entry.open) ? entry.open : null
    if (!entry || typeof entry !== "object" || !name || !open) {
      dropped.push(name || "entry " + (i + 1))
      continue
    }
    if (seen.indexOf(name) !== -1) {
      dropped.push(name + " (duplicate name)")
      continue
    }
    seen.push(name)
    var detectRaw = entry.detect && typeof entry.detect === "object" ? entry.detect : {}
    /** @type {{interface?: string, process?: string}} */
    var detect = {}
    if (typeof detectRaw.interface === "string" && detectRaw.interface)
      detect.interface = detectRaw.interface
    if (typeof detectRaw.process === "string" && detectRaw.process)
      detect.process = detectRaw.process
    apps.push({
      name: name,
      label: typeof entry.label === "string" && entry.label ? entry.label : name,
      detect: detect,
      open: open.map(String)
    })
  }

  /** @type {Record<string, {otp: string}>} */
  var profiles = {}
  for (var key in rawProfiles) {
    if (!Object.prototype.hasOwnProperty.call(rawProfiles, key)) continue
    var p = rawProfiles[key]
    profiles[key] = { otp: p && p.otp === "challenge" ? "challenge" : "append" }
  }

  return {
    apps: apps,
    profiles: profiles,
    error: dropped.length > 0 ? "dropped: " + dropped.join(", ") : ""
  }
}

/**
 * Whether a parsed `ip -j addr` link counts as up: `operstate` is "UP" or
 * "UNKNOWN" (tun devices report UNKNOWN) and it has at least one
 * `addr_info` entry.
 * @param {{operstate?: string, addr_info?: any[]}|null|undefined} link - one `ip -j addr` entry
 * @returns {boolean} true when up
 */
function linkIsUp(link) {
  if (!link) return false
  if (link.operstate !== "UP" && link.operstate !== "UNKNOWN") return false
  return Array.isArray(link.addr_info) && link.addr_info.length > 0
}

/**
 * The parsed `ip -j addr` links whose `ifname` matches PATTERN.
 * @param {Array<{ifname?: string, operstate?: string, addr_info?: any[]}>|null|undefined} links - parsed `ip -j addr`
 * @param {string} pattern - a name or glob
 * @returns {Array<{ifname?: string, operstate?: string, addr_info?: any[]}>} the matching links, in their given order
 */
function matchingLinks(links, pattern) {
  var list = Array.isArray(links) ? links : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var l = list[i]
    if (l && typeof l.ifname === "string" && globMatch(pattern, l.ifname)) out.push(l)
  }
  return out
}

/**
 * Whether NAME is in PROCS, accepted as a `Set`, a plain array, or a plain
 * object keyed by name (any other value reads as nothing running).
 * @param {Set<string>|string[]|Record<string, any>|null|undefined} procs - the running process names
 * @param {string} name - the process name to look for
 * @returns {boolean} true when it's running
 */
function procIsRunning(procs, name) {
  if (!procs) return false
  if (procs instanceof Set) return procs.has(name)
  if (Array.isArray(procs)) return procs.indexOf(name) !== -1
  if (typeof procs === "object") return Object.prototype.hasOwnProperty.call(procs, name)
  return false
}

/**
 * An own-app VPN's state from its `detect` rule, against the current
 * `links` (parsed `ip -j addr`) and `procs` (running process names). An
 * interface alone needs an up, addressed link for "connected"; a matching
 * link that isn't up is "present"; no match is "absent". A process alone is
 * binary (no partial state): running is "connected", else "absent". Both
 * given: "connected" needs both to match; either alone matching is
 * "present"; neither is "absent". An empty `detect` is always "absent".
 * @param {{detect?: {interface?: string, process?: string}}|null|undefined} app - the app entry
 * @param {Array<{ifname?: string, operstate?: string, addr_info?: any[]}>|null|undefined} links - parsed `ip -j addr`
 * @param {Set<string>|string[]|Record<string, any>|null|undefined} procs - running process names
 * @returns {"connected"|"present"|"absent"} the app's state
 */
function appState(app, links, procs) {
  var detect = (app && app.detect) || {}
  var ifacePattern = typeof detect.interface === "string" ? detect.interface : ""
  var processName = typeof detect.process === "string" ? detect.process : ""
  var hasIface = ifacePattern !== ""
  var hasProc = processName !== ""
  var matches = hasIface ? matchingLinks(links, ifacePattern) : []
  var ifaceExists = matches.length > 0
  var ifaceUp = matches.some(linkIsUp)
  var procRunning = hasProc && procIsRunning(procs, processName)

  if (hasIface && hasProc) {
    if (ifaceUp && procRunning) return "connected"
    if (ifaceExists || procRunning) return "present"
    return "absent"
  }
  if (hasIface) return ifaceUp ? "connected" : ifaceExists ? "present" : "absent"
  if (hasProc) return procRunning ? "connected" : "absent"
  return "absent"
}

/**
 * The interface name an own-app VPN's `detect.interface` matches in
 * `links`, for its session IP and traffic graph: the first match that is
 * up with an address (`linkIsUp`), so a glob such as `tun*` skips another
 * VPN's idle tunnel.
 * @param {{detect?: {interface?: string}}|null|undefined} app - the app entry
 * @param {Array<{ifname?: string, operstate?: string, addr_info?: any[]}>|null|undefined} links - parsed `ip -j addr`
 * @returns {string} the matched interface name, or "" with no interface detect or no match
 */
function appInterface(app, links) {
  var detect = (app && app.detect) || {}
  var pattern = typeof detect.interface === "string" ? detect.interface : ""
  if (!pattern) return ""
  var up = matchingLinks(links, pattern).filter(linkIsUp)
  return up.length > 0 && typeof up[0].ifname === "string" ? up[0].ifname : ""
}

/**
 * The apps config a panel applies from a `parseAppsConfig` result: the
 * whole file is ignored (no apps, no profiles) when it has any error, so a
 * partly invalid file never shows a partial list. Shared by the VPN panel
 * and Network's status line, so both read the file the same way.
 * @param {{apps: VpnApp[], profiles: Record<string, {otp: string}>, error: string}|null|undefined} parsed - the parsed file, or null when it's missing
 * @returns {{apps: VpnApp[], profiles: Record<string, {otp: string}>}} what to apply
 */
function appsToApply(parsed) {
  if (!parsed || parsed.error !== "") return { apps: [], profiles: {} }
  return { apps: parsed.apps, profiles: parsed.profiles }
}

/**
 * The names of the VPNs up now, for Network's status line: NetworkManager
 * VPN and WireGuard connections that are active and fully "activated" (not
 * still activating), then own-app VPNs whose `detect.interface` matches an
 * up, addressed link (`appState` without process polling, so a process-only
 * or dual-detect app never shows as up here), by their `name`.
 * @param {Array<{name: string, type: string, active: boolean, state?: string}|null>|null|undefined} connections - NetworkManager connections (`NetworkLogic.parseConnections`)
 * @param {VpnApp[]|null|undefined} apps - the applied own-app VPNs
 * @param {Array<{ifname?: string, operstate?: string, addr_info?: any[]}>|null|undefined} links - parsed `ip -j addr`
 * @returns {string[]} the names, NetworkManager ones first
 */
function upNames(connections, apps, links) {
  var names = []
  var conns = Array.isArray(connections) ? connections : []
  for (var i = 0; i < conns.length; i++) {
    var c = conns[i]
    if (c && (c.type === "vpn" || c.type === "wireguard") && c.active && c.state === "activated")
      names.push(c.name)
  }
  var list = Array.isArray(apps) ? apps : []
  for (var j = 0; j < list.length; j++)
    if (appState(list[j], links, []) === "connected") names.push(list[j].name)
  return names
}

/**
 * The Network dropdown's VPN status line: hidden entirely when nothing is
 * up, the VPN's name when exactly one is, else the count.
 * @param {string[]|undefined} upNames - the names of VPNs currently up (NetworkManager and own-app)
 * @returns {string} "" with none up, "VPN · <name> up" with one, else "VPN · <n> up"
 */
function statusLine(upNames) {
  var names = Array.isArray(upNames) ? upNames : []
  if (names.length === 0) return ""
  if (names.length === 1) return "VPN · " + names[0] + " up"
  return "VPN · " + names.length + " up"
}

if (typeof module !== "undefined")
  module.exports = {
    parseAppsConfig: parseAppsConfig,
    globMatch: globMatch,
    appState: appState,
    appInterface: appInterface,
    appsToApply: appsToApply,
    upNames: upNames,
    statusLine: statusLine
  }
