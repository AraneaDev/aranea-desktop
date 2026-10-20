// Pure rules for the Aranea World Clock (globe, dropdown and panel): the
// subsolar point from a low-precision solar ephemeris, a place's sun
// elevation and day/dusk/night state, a zone's UTC offset, abbreviation and
// local time (from a `date` probe's offsets; Intl is absent in QML), the offset text against the home
// zone, a place's daylight window and the day/night gradient stops for the
// strip. No QML, no I/O, no `Date.now()` (every instant is passed in as
// epoch milliseconds); tests/js/worldclock-logic.test.js runs this under Node.

/**
 * A point on the globe, in degrees.
 * @typedef {{lat: number, lon: number}} LatLon
 */

/**
 * A place's daylight on one local day. `rise` and `set` are local hours
 * 0-24 and may wrap past midnight (set < rise).
 * @typedef {{kind: "window"|"day"|"night", rise: number, set: number}} DaylightWindow
 */

var DEG = Math.PI / 180
var DUSK_SIN = Math.sin(6 * DEG)
var TWILIGHT_HOURS = 0.75

/**
 * Wraps a value into [0, m).
 * @param {number} v - the value
 * @param {number} m - the modulus
 * @returns {number} v modulo m, never negative
 */
function wrap(v, m) {
  return ((v % m) + m) % m
}

/**
 * Left-pads a whole number to two digits.
 * @param {number} n - a non-negative integer
 * @returns {string} the two-digit text
 */
function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

/**
 * The sun's declination and the equation of time at an instant (low-precision
 * ephemeris: mean longitude and anomaly, ecliptic longitude, obliquity).
 * @param {number} utcMs - epoch milliseconds
 * @returns {{dec: number, eot: number}} declination in degrees and the equation of time in degrees of longitude
 */
function sunParams(utcMs) {
  var d = utcMs / 86400000 - 10957.5
  var L = wrap(280.46 + 0.9856474 * d, 360)
  var g = wrap(357.528 + 0.9856003 * d, 360) * DEG
  var lambda = (L + 1.915 * Math.sin(g) + 0.02 * Math.sin(2 * g)) * DEG
  var eps = (23.439 - 0.0000004 * d) * DEG
  var dec = Math.asin(Math.sin(eps) * Math.sin(lambda)) / DEG
  var ra = Math.atan2(Math.cos(eps) * Math.sin(lambda), Math.cos(lambda)) / DEG
  var eot = wrap(L - ra + 180, 360) - 180
  return { dec: dec, eot: eot }
}

/**
 * The point on Earth where the sun is directly overhead.
 * @param {number} utcMs - epoch milliseconds
 * @returns {LatLon} degrees, lon in [-180, 180)
 */
function subsolarPoint(utcMs) {
  var p = sunParams(utcMs)
  var utcHours = wrap(utcMs / 3600000, 24)
  var lon = wrap(-15 * (utcHours - 12) - p.eot + 180, 360) - 180
  return { lat: p.dec, lon: lon }
}

/**
 * The sine of the sun's elevation at a place.
 * @param {number} lat - the place's latitude, degrees
 * @param {number} lon - the place's longitude, degrees
 * @param {LatLon} sun - the subsolar point
 * @returns {number} sine of the elevation, -1..1
 */
function sunElevation(lat, lon, sun) {
  var phi = lat * DEG
  var dec = sun.lat * DEG
  return (
    Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos((lon - sun.lon) * DEG)
  )
}

/**
 * Whether a place is in day, dusk (sun within 6 degrees of the horizon) or
 * night.
 * @param {{lat?: number, lon?: number}|null} place - the place, possibly without coordinates
 * @param {LatLon} sun - the subsolar point
 * @returns {"day"|"dusk"|"night"|"none"} "none" without coordinates
 */
function nodeState(place, sun) {
  if (!place || typeof place.lat !== "number" || typeof place.lon !== "number") return "none"
  var e = sunElevation(place.lat, place.lon, sun)
  if (Math.abs(e) <= DUSK_SIN) return "dusk"
  return e > 0 ? "day" : "night"
}

/**
 * argv for a `date` probe printing "<zone>|<abbr>|<+hhmm>" per zone (Intl is
 * absent in the QML engine, so zone data comes from the system). Zones are
 * trailing arguments, never script text. `withLocal` prepends
 * "LOCAL|<timedatectl zone>" and that zone's own line.
 * @param {string[]} zones - IANA zone names
 * @param {boolean} withLocal - also report the machine's own zone
 * @returns {string[]} the argv
 */
function probeCommand(zones, withLocal) {
  var script = 'for z in "$@"; do TZ="$z" date "+$z|%Z|%z"; done'
  if (withLocal)
    script =
      "tz=$(timedatectl show -p Timezone --value); " +
      'printf \'LOCAL|%s\\n\' "$tz"; TZ="$tz" date "+$tz|%Z|%z"; ' +
      script
  return ["bash", "-c", script, "bash"].concat(zones || [])
}

/**
 * Parses a "+hhmm" / "-hhmm" offset.
 * @param {string} text - the offset text
 * @returns {number|null} minutes east of UTC, or null when malformed
 */
function parseOffset(text) {
  var m = /^([+-])(\d{2})(\d{2})$/.exec(String(text || "").trim())
  if (!m) return null
  var minutes = parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
  return m[1] === "-" ? -minutes : minutes
}

/**
 * Parses the output of probeCommand's script.
 * @param {string} text - the probe's stdout
 * @returns {{local: string, zones: Object<string, {abbr: string, offsetMinutes: number}>}} the machine's zone and each probed zone; malformed lines are ignored
 */
function parseProbe(text) {
  var out = { local: "", zones: {} }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("|")
    var id = f[0].trim()
    if (f.length === 2 && id === "LOCAL") {
      out.local = f[1].trim()
      continue
    }
    if (f.length < 3 || id === "") continue
    var off = parseOffset(f[2])
    if (off === null) continue
    out.zones[id] = { abbr: f[1].trim(), offsetMinutes: off }
  }
  return out
}

/**
 * A zone's display abbreviation.
 * @param {{abbr: string}|undefined} info - the zone's probe entry
 * @param {string} zone - the IANA zone name
 * @returns {string} "UTC" for UTC, "GMT+7" for a numeric "+07" name, else the abbreviation
 */
function abbrevText(info, zone) {
  if (zone === "UTC") return "UTC"
  var abbr = info && info.abbr ? info.abbr : ""
  var m = /^([+-])(\d{2})(\d{2})?$/.exec(abbr)
  if (!m) return abbr
  var h = parseInt(m[2], 10)
  var min = m[3] ? parseInt(m[3], 10) : 0
  return "GMT" + m[1] + h + (min ? ":" + pad2(min) : "")
}

/**
 * A zone's wall-clock time at an instant.
 * @param {number} offsetMinutes - the zone's UTC offset
 * @param {number} utcMs - epoch milliseconds
 * @returns {string} "HH:MM", 24 hour
 */
function localTime(offsetMinutes, utcMs) {
  var m = Math.floor(wrap(utcMs / 60000 + offsetMinutes, 1440))
  return pad2(Math.floor(m / 60)) + ":" + pad2(m % 60)
}

/**
 * A zone's offset from the home zone, as text.
 * @param {number} offsetMinutes - the zone's UTC offset
 * @param {number} homeOffsetMinutes - the home zone's UTC offset
 * @returns {string} "home", "+7 h", "−6 h" or "+5:30 h"
 */
function offsetText(offsetMinutes, homeOffsetMinutes) {
  var diff = offsetMinutes - homeOffsetMinutes
  if (diff === 0) return "home"
  var abs = Math.abs(diff)
  var h = Math.floor(abs / 60)
  var m = abs % 60
  return (diff < 0 ? "−" : "+") + h + (m ? ":" + pad2(m) : "") + " h"
}

/**
 * A place's daylight on the local calendar day containing the instant (sun
 * declination and equation of time are taken at that day's local noon, so
 * the window is stable across the day).
 * @param {{lat: number, lon: number}} place - the place
 * @param {number} offsetMinutes - the place's zone UTC offset
 * @param {number} utcMs - epoch milliseconds
 * @returns {DaylightWindow} rise/set in local hours; "day" or "night" in polar conditions
 */
function daylightWindow(place, offsetMinutes, utcMs) {
  var localDay = Math.floor((utcMs + offsetMinutes * 60000) / 86400000)
  var p = sunParams(localDay * 86400000 + 43200000 - offsetMinutes * 60000)
  var arg = -Math.tan(place.lat * DEG) * Math.tan(p.dec * DEG)
  if (arg <= -1) return { kind: "day", rise: 0, set: 24 }
  if (arg >= 1) return { kind: "night", rise: 0, set: 0 }
  var half = Math.acos(arg) / DEG / 15
  var noon = 12 - place.lon / 15 + offsetMinutes / 60 - p.eot / 15
  return { kind: "window", rise: wrap(noon - half, 24), set: wrap(noon + half, 24) }
}

/**
 * The tone at a local hour for a daylight window: day inside it, dusk within
 * the twilight band outside it, night elsewhere.
 * @param {DaylightWindow} w - a "window" daylight window
 * @param {number} h - local hour 0-24
 * @returns {"night"|"dusk"|"day"} the tone
 */
function toneAt(w, h) {
  var span = wrap(w.set - w.rise, 24)
  var into = wrap(h - w.rise, 24)
  if (into <= span) return "day"
  var before = 24 - into
  var after = into - span
  return Math.min(before, after) <= TWILIGHT_HOURS ? "dusk" : "night"
}

/**
 * Gradient stops for a day/night strip across a local day.
 * @param {DaylightWindow} window - the place's daylight window
 * @returns {Array<{at: number, tone: "night"|"dusk"|"day"}>} stops, ascending, `at` in 0-1
 */
function stripStops(window) {
  if (window.kind === "day")
    return [
      { at: 0, tone: "day" },
      { at: 1, tone: "day" }
    ]
  if (window.kind === "night")
    return [
      { at: 0, tone: "night" },
      { at: 1, tone: "night" }
    ]
  var w = TWILIGHT_HOURS
  var raw = [
    [window.rise - w, "night"],
    [window.rise, "dusk"],
    [window.rise + w, "day"],
    [window.set - w, "day"],
    [window.set, "dusk"],
    [window.set + w, "night"]
  ]
  var stops = [
    { at: 0, tone: toneAt(window, 0) },
    { at: 1, tone: toneAt(window, 24) }
  ]
  for (var i = 0; i < raw.length; i++) stops.push({ at: wrap(raw[i][0], 24) / 24, tone: raw[i][1] })
  stops.sort(function (a, b) {
    return a.at - b.at
  })
  return stops
}

/**
 * How far through its local day a zone is.
 * @param {number} offsetMinutes - the zone's UTC offset
 * @param {number} utcMs - epoch milliseconds
 * @returns {number} 0-1 (local midnight to midnight)
 */
function nowFraction(offsetMinutes, utcMs) {
  return wrap(utcMs / 60000 + offsetMinutes, 1440) / 1440
}

/**
 * A coordinate caption for a point.
 * @param {LatLon} sun - the point (a place or the subsolar point)
 * @returns {string} e.g. "10°S 20°E"
 */
function placeCaption(sun) {
  var la = Math.round(Math.abs(sun.lat))
  var lo = Math.round(Math.abs(sun.lon))
  return la + "°" + (sun.lat < 0 ? "S" : "N") + " " + lo + "°" + (sun.lon < 0 ? "W" : "E")
}

if (typeof module !== "undefined")
  module.exports = {
    subsolarPoint: subsolarPoint,
    sunElevation: sunElevation,
    nodeState: nodeState,
    probeCommand: probeCommand,
    parseProbe: parseProbe,
    abbrevText: abbrevText,
    localTime: localTime,
    offsetText: offsetText,
    daylightWindow: daylightWindow,
    stripStops: stripStops,
    nowFraction: nowFraction,
    placeCaption: placeCaption
  }
