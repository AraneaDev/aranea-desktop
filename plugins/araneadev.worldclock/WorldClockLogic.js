// Pure rules for the Aranea World Clock (globe, dropdown and panel): the
// subsolar point from a low-precision solar ephemeris, a place's sun
// elevation and day/dusk/night state, a zone's UTC offset, abbreviation and
// local time (via Intl.DateTimeFormat), the offset text against the home
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
 * A zone's UTC offset at an instant.
 * @param {string} zone - an IANA zone name
 * @param {number} utcMs - epoch milliseconds
 * @returns {number} the offset in minutes east of UTC
 */
function offsetMinutes(zone, utcMs) {
  var fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: zone,
    hourCycle: "h23",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    second: "numeric"
  })
  var v = {}
  var parts = fmt.formatToParts(new Date(utcMs))
  for (var i = 0; i < parts.length; i++) v[parts[i].type] = parseInt(parts[i].value, 10)
  var asUtc = Date.UTC(v.year, v.month - 1, v.day, v.hour, v.minute, v.second)
  return Math.round((asUtc - Math.floor(utcMs / 1000) * 1000) / 60000)
}

/**
 * A zone's short abbreviation at an instant (EDT, BST, GMT, ...).
 * @param {string} zone - an IANA zone name
 * @param {number} utcMs - epoch milliseconds
 * @returns {string} the abbreviation; "UTC" for UTC
 */
function zoneAbbrev(zone, utcMs) {
  if (zone === "UTC") return "UTC"
  var locales = ["en-US", "en-GB"]
  var first = ""
  for (var l = 0; l < locales.length; l++) {
    var fmt = new Intl.DateTimeFormat(locales[l], { timeZone: zone, timeZoneName: "short" })
    var parts = fmt.formatToParts(new Date(utcMs))
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].type !== "timeZoneName") continue
      // A "GMT+1" style name is the locale lacking a real abbreviation: try the next.
      if (!/^(GMT|UTC)[+\u2212-]/.test(parts[i].value)) return parts[i].value
      if (!first) first = parts[i].value
    }
  }
  return first
}

/**
 * A zone's wall-clock time at an instant.
 * @param {string} zone - an IANA zone name
 * @param {number} utcMs - epoch milliseconds
 * @returns {string} "HH:MM", 24 hour
 */
function localTime(zone, utcMs) {
  var local = wrap(utcMs / 60000 + offsetMinutes(zone, utcMs), 1440)
  var m = Math.floor(local)
  return pad2(Math.floor(m / 60)) + ":" + pad2(m % 60)
}

/**
 * A zone's offset from the home zone, as text.
 * @param {string} zone - the zone to describe
 * @param {string} homeZone - the home zone
 * @param {number} utcMs - epoch milliseconds
 * @returns {string} "home", "+7 h", "−6 h" or "+5:30 h"
 */
function offsetText(zone, homeZone, utcMs) {
  var diff = offsetMinutes(zone, utcMs) - offsetMinutes(homeZone, utcMs)
  if (diff === 0) return "home"
  var abs = Math.abs(diff)
  var h = Math.floor(abs / 60)
  var m = abs % 60
  return (diff < 0 ? "−" : "+") + h + (m ? ":" + pad2(m) : "") + " h"
}

/**
 * A place's daylight on the local day containing the instant.
 * @param {{lat: number, lon: number}} place - the place
 * @param {string} zone - the place's IANA zone
 * @param {number} utcMs - epoch milliseconds
 * @returns {DaylightWindow} rise/set in local hours; "day" or "night" in polar conditions
 */
function daylightWindow(place, zone, utcMs) {
  var p = sunParams(utcMs)
  var arg = -Math.tan(place.lat * DEG) * Math.tan(p.dec * DEG)
  if (arg <= -1) return { kind: "day", rise: 0, set: 24 }
  if (arg >= 1) return { kind: "night", rise: 0, set: 0 }
  var half = Math.acos(arg) / DEG / 15
  var noon = 12 - place.lon / 15 + offsetMinutes(zone, utcMs) / 60 - p.eot / 15
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
 * @param {string} zone - an IANA zone name
 * @param {number} utcMs - epoch milliseconds
 * @returns {number} 0-1 (local midnight to midnight)
 */
function nowFraction(zone, utcMs) {
  return wrap(utcMs / 60000 + offsetMinutes(zone, utcMs), 1440) / 1440
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
    offsetMinutes: offsetMinutes,
    zoneAbbrev: zoneAbbrev,
    localTime: localTime,
    offsetText: offsetText,
    daylightWindow: daylightWindow,
    stripStops: stripStops,
    nowFraction: nowFraction,
    placeCaption: placeCaption
  }
