// Pure rules for the Aranea Clock dropdown (Panel.qml): sunrise and sunset
// (the NOAA solar calculator algorithm), clock and daylight-span formatting,
// the sun's position along its day/night arc, the moon's phase from a known
// synodic reference (and its Nerd Font glyph), parsing wttr.in's
// nearest_area and the stock weather.loc file, the place caption shown in
// the header, and the once-a-day fetch gate for the wttr.in lookup. No QML,
// no I/O, no `Date.now()` (every date is passed in explicitly); tests
// /js/clock-logic.test.js runs this under Node.

/**
 * A day's sunrise and sunset, in minutes after local midnight, or the
 * polar state when the sun never crosses the horizon that day.
 * @typedef {{sunrise: number|null, sunset: number|null, polar: ""|"day"|"night"}} SunTimes
 */

/**
 * The moon's phase: which of the 8 named phases it is in, and how much of
 * its disc is lit.
 * @typedef {{index: number, name: string, illumination: number}} MoonPhase
 */

/**
 * A resolved place: its display name and coordinates.
 * @typedef {{name: string, lat: number|null, lon: number|null}} Place
 */

var DEG = Math.PI / 180

/**
 * Degrees to radians.
 * @param {number} d - degrees
 * @returns {number} radians
 */
function toRad(d) {
  return d * DEG
}

/**
 * Radians to degrees.
 * @param {number} r - radians
 * @returns {number} degrees
 */
function toDeg(r) {
  return r / DEG
}

/**
 * True for a finite number (never NaN or +/-Infinity), the baseline every
 * numeric input in this module is checked against before it is trusted.
 * @param {*} n - the value to check
 * @returns {boolean} true when it is safe to compute with
 */
function isFiniteNumber(n) {
  return typeof n === "number" && isFinite(n)
}

/**
 * Wraps a value into [0, 1440) (minutes in a day), so an out-of-range or
 * negative minute (from wall-clock arithmetic crossing midnight) still maps
 * onto a single day.
 * @param {number} minutes - minutes, any range
 * @returns {number} the equivalent minute in [0, 1440)
 */
function wrapMinutes(minutes) {
  var m = minutes % 1440
  if (m < 0) m += 1440
  return m
}

/**
 * Zero-pads a non-negative integer to at least 2 digits.
 * @param {number} n - the value
 * @returns {string} "07", "43", "123"
 */
function pad2(n) {
  var s = String(Math.round(n))
  return s.length < 2 ? "0" + s : s
}

/**
 * The Julian Day Number (an integer, conventionally the value at UT noon)
 * for a Gregorian calendar date, via the Fliegel & Van Flandern formula.
 * @param {number} y - full year
 * @param {number} m - month, 1-12
 * @param {number} d - day of month
 * @returns {number} the Julian Day Number
 */
function julianDayNumber(y, m, d) {
  var a = Math.floor((14 - m) / 12)
  var yy = y + 4800 - a
  var mm = m + 12 * a - 3
  return (
    d +
    Math.floor((153 * mm + 2) / 5) +
    365 * yy +
    Math.floor(yy / 4) -
    Math.floor(yy / 100) +
    Math.floor(yy / 400) -
    32045
  )
}

/**
 * A day's sunrise and sunset for a place and date, by the NOAA solar
 * calculator algorithm (the same formulas as NOAA's published spreadsheet),
 * evaluated at local noon (accurate to well under a minute for sunrise and
 * sunset purposes). Invalid latitude, longitude, date or timezone offset
 * give null rather than throwing or returning NaN.
 * @param {number} lat - latitude in degrees, -90..90
 * @param {number} lon - longitude in degrees, -180..180 (east positive)
 * @param {number} y - full year
 * @param {number} m - month, 1-12
 * @param {number} d - day of month
 * @param {number} tzOffsetMinutes - the local timezone's offset from UTC, in minutes
 * @returns {SunTimes|null} the day's sun times, or null for invalid input
 */
function sunTimes(lat, lon, y, m, d, tzOffsetMinutes) {
  if (!isFiniteNumber(lat) || !isFiniteNumber(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180)
    return null
  if (!isFiniteNumber(y) || !isFiniteNumber(m) || !isFiniteNumber(d)) return null
  if (!isFiniteNumber(tzOffsetMinutes)) return null

  var tzHours = tzOffsetMinutes / 60
  var jdn = julianDayNumber(y, m, d)
  var jd = jdn - tzHours / 24
  var T = (jd - 2451545.0) / 36525

  var geomMeanLongSun = (280.46646 + T * (36000.76983 + T * 0.0003032)) % 360
  if (geomMeanLongSun < 0) geomMeanLongSun += 360
  var geomMeanAnomSun = 357.52911 + T * (35999.05029 - 0.0001537 * T)
  var eccentEarthOrbit = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
  var mRad = toRad(geomMeanAnomSun)
  var sunEqOfCtr =
    Math.sin(mRad) * (1.914602 - T * (0.004817 + 0.000014 * T)) +
    Math.sin(2 * mRad) * (0.019993 - 0.000101 * T) +
    Math.sin(3 * mRad) * 0.000289
  var sunTrueLong = geomMeanLongSun + sunEqOfCtr
  var sunAppLong = sunTrueLong - 0.00569 - 0.00478 * Math.sin(toRad(125.04 - 1934.136 * T))
  var meanObliqEcliptic =
    23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60
  var obliqCorr = meanObliqEcliptic + 0.00256 * Math.cos(toRad(125.04 - 1934.136 * T))
  var sunDeclin = toDeg(Math.asin(Math.sin(toRad(obliqCorr)) * Math.sin(toRad(sunAppLong))))
  var varY = Math.pow(Math.tan(toRad(obliqCorr / 2)), 2)
  var eqOfTime =
    4 *
    toDeg(
      varY * Math.sin(2 * toRad(geomMeanLongSun)) -
        2 * eccentEarthOrbit * Math.sin(mRad) +
        4 * eccentEarthOrbit * varY * Math.sin(mRad) * Math.cos(2 * toRad(geomMeanLongSun)) -
        0.5 * varY * varY * Math.sin(4 * toRad(geomMeanLongSun)) -
        1.25 * eccentEarthOrbit * eccentEarthOrbit * Math.sin(2 * mRad)
    )

  var latRad = toRad(lat)
  var declRad = toRad(sunDeclin)
  var cosHA =
    Math.cos(toRad(90.833)) / (Math.cos(latRad) * Math.cos(declRad)) -
    Math.tan(latRad) * Math.tan(declRad)

  if (cosHA > 1) return { sunrise: null, sunset: null, polar: "night" }
  if (cosHA < -1) return { sunrise: null, sunset: null, polar: "day" }

  var haSunrise = toDeg(Math.acos(cosHA))
  var solarNoonMinutes = 720 - 4 * lon - eqOfTime + tzHours * 60
  return {
    sunrise: solarNoonMinutes - haSunrise * 4,
    sunset: solarNoonMinutes + haSunrise * 4,
    polar: ""
  }
}

/**
 * Formats minutes after local midnight as a 24-hour clock string, wrapping
 * into a single day and rounding to the nearest minute. Invalid input never
 * throws; it reads as midnight.
 * @param {number} minutes - minutes after local midnight
 * @returns {string} "07:43"
 */
function formatClock(minutes) {
  var m = isFiniteNumber(minutes) ? wrapMinutes(Math.round(minutes)) : 0
  var h = Math.floor(m / 60)
  var mm = m % 60
  return pad2(h) + ":" + pad2(mm)
}

/**
 * The daylight span between sunrise and sunset as "H h MM" (hours
 * unpadded, minutes zero-padded), wrapping when sunset's minute is earlier
 * than sunrise's (both are minutes-after-midnight, not full timestamps).
 * Invalid input never throws; it reads "".
 * @param {number} sunrise - minutes after local midnight
 * @param {number} sunset - minutes after local midnight
 * @returns {string} "11 h 32", or "" for invalid input
 */
function daylightText(sunrise, sunset) {
  if (!isFiniteNumber(sunrise) || !isFiniteNumber(sunset)) return ""
  var span = wrapMinutes(Math.round(sunset) - Math.round(sunrise))
  var h = Math.floor(span / 60)
  var m = span % 60
  return h + " h " + pad2(m)
}

/**
 * Where "now" sits along the sun's arc: a fraction of the way from sunrise
 * to sunset while it is day, or from sunset to the next sunrise while it is
 * night. With no valid sun times for the day (polar day/night, or any
 * non-finite input), there is no arc to place a point on, so this reads the
 * night-arc start rather than throwing.
 * @param {number} nowMinutes - the current time, minutes after local midnight (any range; wrapped)
 * @param {number} sunrise - minutes after local midnight
 * @param {number} sunset - minutes after local midnight
 * @returns {{t: number, night: boolean}} t in 0..1 along the relevant arc
 */
function sunArcPosition(nowMinutes, sunrise, sunset) {
  var now = isFiniteNumber(nowMinutes) ? wrapMinutes(nowMinutes) : 0
  if (!isFiniteNumber(sunrise) || !isFiniteNumber(sunset) || sunset <= sunrise)
    return { t: 0, night: true }

  if (now >= sunrise && now <= sunset) {
    var dayT = (now - sunrise) / (sunset - sunrise)
    return { t: Math.min(1, Math.max(0, dayT)), night: false }
  }

  var nightSpan = 1440 - sunset + sunrise
  var pos = now > sunset ? now - sunset : now + (1440 - sunset)
  var nightT = nightSpan > 0 ? pos / nightSpan : 0
  return { t: Math.min(1, Math.max(0, nightT)), night: true }
}

var SYNODIC_MONTH_MS = 29.530588853 * 86400000
var REFERENCE_NEW_MOON_MS = Date.UTC(2000, 0, 6, 18, 14, 0)
var MOON_PHASE_NAMES = [
  "New moon",
  "Waxing crescent",
  "First quarter",
  "Waxing gibbous",
  "Full moon",
  "Waning gibbous",
  "Last quarter",
  "Waning crescent"
]

/**
 * The moon's phase at an instant, from its age since a known new moon
 * (2000-01-06 18:14 UTC) against the synodic month (29.530588853 days): one
 * of 8 named phases and the percentage of the disc lit. Invalid input never
 * throws; it falls back to the Unix epoch.
 * @param {number} utcMillis - milliseconds since the Unix epoch, UTC
 * @returns {MoonPhase} the phase index (0-7), its name and illumination (0-100)
 */
function moonPhase(utcMillis) {
  var millis = isFiniteNumber(utcMillis) ? utcMillis : 0
  var age = (millis - REFERENCE_NEW_MOON_MS) % SYNODIC_MONTH_MS
  if (age < 0) age += SYNODIC_MONTH_MS
  var frac = age / SYNODIC_MONTH_MS
  var index = Math.floor(frac * 8) % 8
  var illumination = Math.round(((1 - Math.cos(2 * Math.PI * frac)) / 2) * 100)
  return { index: index, name: MOON_PHASE_NAMES[index], illumination: illumination }
}

var MOON_GLYPH_CODEPOINTS = [
  0xf0f64, // New moon
  0xf0f67, // Waxing crescent
  0xf0f61, // First quarter
  0xf0f68, // Waxing gibbous
  0xf0f62, // Full moon
  0xf0f66, // Waning gibbous
  0xf0f63, // Last quarter
  0xf0f65 // Waning crescent
]

/**
 * The Nerd Font (Material Design Icons) glyph for a moon phase index. An
 * out-of-range or non-finite index wraps into 0..7 rather than throwing.
 * @param {number} index - a `moonPhase` index, 0-7 (wrapped if outside)
 * @returns {string} the glyph, a single code point
 */
function moonGlyph(index) {
  var i = isFiniteNumber(index) ? Math.trunc(index) : 0
  i = ((i % 8) + 8) % 8
  return String.fromCodePoint(MOON_GLYPH_CODEPOINTS[i])
}

/**
 * Parses wttr.in's `nearest_area[0]` (its resolved place for a coordinate
 * or IP-based query): the place name (`areaName[0].value`) and its
 * coordinates. Invalid JSON, a missing/empty `nearest_area`, or an
 * unparseable name or coordinate pair give null rather than throwing.
 * @param {string|undefined} json - wttr.in's `?format=j1` response body
 * @returns {Place|null} the resolved place, or null
 */
function parseWttrArea(json) {
  var data
  try {
    data = JSON.parse(String(json))
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object") return null
  var areas = data.nearest_area
  if (!Array.isArray(areas) || areas.length === 0) return null
  var area = areas[0]
  if (!area || typeof area !== "object") return null
  var nameArr = area.areaName
  var name =
    Array.isArray(nameArr) && nameArr[0] && typeof nameArr[0].value === "string"
      ? nameArr[0].value
      : ""
  var lat = parseFloat(area.latitude)
  var lon = parseFloat(area.longitude)
  if (!name || !isFinite(lat) || !isFinite(lon)) return null
  return { name: name, lat: lat, lon: lon }
}

/**
 * Parses the stock weather plugin's `weather.loc` file: `{name, latitude,
 * longitude}` (mirrors `Model.parseLocationFile`'s field names on the way
 * in). A configured name with no coordinates (a hand-edited file) is kept
 * with null coordinates; nothing configured at all (no name and no
 * coordinates, including invalid JSON) gives null, meaning "auto-detect by
 * IP" the way stock's unset location does.
 * @param {string|undefined} text - the file's contents
 * @returns {Place|null} the configured place, or null when none is set
 */
function parseWeatherLocation(text) {
  var data
  try {
    data = JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object") return null
  var name = typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : ""
  var lat = parseFloat(data.latitude)
  var lon = parseFloat(data.longitude)
  var hasCoordinates = !isNaN(lat) && !isNaN(lon)
  if (!name && !hasCoordinates) return null
  return { name: name, lat: hasCoordinates ? lat : null, lon: hasCoordinates ? lon : null }
}

/**
 * The header's place caption: the configured location's name, else the
 * name wttr.in resolved, else "Here" (no location known at all).
 * @param {{name?: string}|null|undefined} configured - from `parseWeatherLocation`
 * @param {{name?: string}|null|undefined} wttr - from `parseWttrArea`
 * @returns {string} the caption to show
 */
function placeCaption(configured, wttr) {
  var configuredName =
    configured && typeof configured.name === "string"
      ? configured.name.replace(/^\s+|\s+$/g, "")
      : ""
  if (configuredName) return configuredName
  var wttrName = wttr && typeof wttr.name === "string" ? wttr.name.replace(/^\s+|\s+$/g, "") : ""
  if (wttrName) return wttrName
  return "Here"
}

/**
 * Whether the wttr.in area lookup should run now: only while the dropdown
 * is open, only when no weather location is configured (a configured
 * location needs no lookup), and at most once per calendar day (no retry
 * loop even after a failed fetch, once the day key is recorded).
 * @param {Place|null|undefined} configured - from `parseWeatherLocation`
 * @param {string|null|undefined} lastFetchDayKey - the day key of the last attempt, "" for none
 * @param {string} todayKey - today's day key, e.g. "2026-10-02"
 * @param {boolean} opened - whether the dropdown is open
 * @returns {boolean} true when the lookup should run
 */
function shouldFetchArea(configured, lastFetchDayKey, todayKey, opened) {
  if (!opened) return false
  if (configured) return false
  if ((lastFetchDayKey || "") === todayKey) return false
  return true
}

/**
 * The answer to the `showcase` IPC call: a display-only stand-in place for
 * README screenshots, in the weather location file's shape
 * (`{"name", "latitude", "longitude"}`). It is taken only while the
 * dropdown is open (the dropdown clears it on open and on close) and only
 * with coordinates, so the sun row draws from it and never from the real
 * location.
 * @param {boolean} opened - the dropdown is open
 * @param {string|undefined} json - the call's JSON object
 * @returns {{answer: string, place: Place|null}} "ok" with the place, or
 *   "closed" / "invalid" with null
 */
function showcaseCall(opened, json) {
  if (!opened) return { answer: "closed", place: null }
  var place = parseWeatherLocation(json)
  if (!place || place.lat === null || !place.name) return { answer: "invalid", place: null }
  if (Math.abs(place.lat) > 90 || Math.abs(/** @type {number} */ (place.lon)) > 180)
    return { answer: "invalid", place: null }
  return { answer: "ok", place: place }
}

if (typeof module !== "undefined")
  module.exports = {
    sunTimes: sunTimes,
    formatClock: formatClock,
    daylightText: daylightText,
    sunArcPosition: sunArcPosition,
    moonPhase: moonPhase,
    moonGlyph: moonGlyph,
    parseWttrArea: parseWttrArea,
    parseWeatherLocation: parseWeatherLocation,
    placeCaption: placeCaption,
    shouldFetchArea: shouldFetchArea,
    showcaseCall: showcaseCall
  }
