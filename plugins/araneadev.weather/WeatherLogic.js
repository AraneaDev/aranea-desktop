// Pure rules for the Aranea Weather dropdown (Panel.qml): the open-meteo
// forecast and air-quality request URLs (stock's fields plus the extras),
// parsing both responses, "rain soon" from the minutely trace, the wind
// compass (label plus the arrow's rotation to where the wind blows to), the
// 3-hour pressure trend arrow, the European AQI and WHO UV bands, the
// next-24h temperature/rain-chance points for the hourly trace (normalised
// 0..1), unit conversions and their formatted strings, the shared-report
// freshness check across per-monitor instances (the Clock lesson) and
// parsing wttr.in's nearest_area down to coordinates only. No QML, no I/O,
// no `Date.now()` (every "now" is passed in explicitly, as an open-meteo
// `timezone=auto` local ISO string, and compared by its wall-clock digits
// rather than through the host's timezone); tests/js/weather-logic.test.js
// runs this under Node.

/**
 * An hourly series, as `parseOpenMeteo` extracts it from open-meteo's
 * `hourly` block: local ISO time strings, temperature (deg C),
 * precipitation probability (percent) and surface pressure (hPa), all
 * index-aligned.
 * @typedef {{time: string[], temp: number[], rain: number[], pressure: number[]}} HourlySeries
 */

/**
 * A minutely-15 series, as `parseOpenMeteo` extracts it: local ISO time
 * strings and precipitation (mm), index-aligned.
 * @typedef {{time: string[], precip: number[]}} MinutelySeries
 */

/**
 * A parsed open-meteo forecast response.
 * @typedef {{current: object|null, hourly: HourlySeries, minutely: MinutelySeries}} ParsedForecast
 */

/**
 * A parsed air-quality response.
 * @typedef {{aqi: number|null, uv: number|null}} ParsedAir
 */

/**
 * A wind compass reading: its 8-point label (the direction the wind is
 * coming from, matching the convention "wind from the SW") and the
 * rotation, in degrees, an arrow should be turned to so it points where the
 * wind blows to.
 * @typedef {{label: string, rotation: number}} Compass
 */

/**
 * A banded chip's label and tone.
 * @typedef {{label: string, tone: "good"|"plain"|"bad"}} Band
 */

/**
 * A banded chip with no tone (UV has only one visual treatment).
 * @typedef {{label: string}} UvBand
 */

/**
 * The next-24h trace: normalised (0..1) temperature points and rain-chance
 * bars, plus the actual min/max/now temperatures for the caption.
 * @typedef {{temp: Array<{x: number, y: number}>, rain: Array<{x: number, h: number}>, min: number|null, max: number|null, now: number|null}} HourlyPoints
 */

/**
 * A peer instance's last-fetched report, as kept per bar widget for
 * `sharedReport` (the Clock lesson: one fetch per refresh across monitors).
 * @typedef {{fetchedAt: number, report: object}|null} PeerReport
 */

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
 * Builds the open-meteo forecast request: stock's `daily` and `current`
 * fields (weather code, temperature, apparent temperature, humidity, wind
 * speed, is_day) plus the extras this dropdown adds to `current`, a 3h/24h
 * `hourly` window, and a 3h `minutely_15` window.
 * @param {number} lat - latitude in degrees
 * @param {number} lon - longitude in degrees
 * @returns {string} the request URL
 */
function buildForecastUrl(lat, lon) {
  return (
    "https://api.open-meteo.com/v1/forecast" +
    "?latitude=" +
    encodeURIComponent(String(lat)) +
    "&longitude=" +
    encodeURIComponent(String(lon)) +
    "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
    "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day,wind_direction_10m,wind_gusts_10m,surface_pressure,visibility" +
    "&hourly=temperature_2m,precipitation_probability,surface_pressure&past_hours=3&forecast_hours=24" +
    "&minutely_15=precipitation&forecast_minutely_15=12" +
    "&forecast_days=4&timezone=auto"
  )
}

/**
 * Builds the open-meteo air-quality request: current European AQI and UV
 * index, one extra request per refresh alongside the forecast.
 * @param {number} lat - latitude in degrees
 * @param {number} lon - longitude in degrees
 * @returns {string} the request URL
 */
function buildAirUrl(lat, lon) {
  return (
    "https://air-quality-api.open-meteo.com/v1/air-quality" +
    "?latitude=" +
    encodeURIComponent(String(lat)) +
    "&longitude=" +
    encodeURIComponent(String(lon)) +
    "&current=european_aqi,uv_index&timezone=auto"
  )
}

/**
 * Parses open-meteo's forecast response body into the current reading and
 * the index-aligned hourly/minutely series this dropdown reads. Invalid
 * JSON or a non-object body gives null; a valid body missing `hourly` or
 * `minutely_15` gives empty series rather than throwing, so a response that
 * only has `current` still parses.
 * @param {string|undefined} json - the response body
 * @returns {ParsedForecast|null} the parsed report, or null
 */
function parseOpenMeteo(json) {
  var data
  try {
    data = JSON.parse(String(json))
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object") return null

  var current = data.current && typeof data.current === "object" ? data.current : null

  var h = data.hourly && typeof data.hourly === "object" ? data.hourly : {}
  var hourly = {
    time: Array.isArray(h.time) ? h.time : [],
    temp: Array.isArray(h.temperature_2m) ? h.temperature_2m : [],
    rain: Array.isArray(h.precipitation_probability) ? h.precipitation_probability : [],
    pressure: Array.isArray(h.surface_pressure) ? h.surface_pressure : []
  }

  var m = data.minutely_15 && typeof data.minutely_15 === "object" ? data.minutely_15 : {}
  var minutely = {
    time: Array.isArray(m.time) ? m.time : [],
    precip: Array.isArray(m.precipitation) ? m.precipitation : []
  }

  return { current: current, hourly: hourly, minutely: minutely }
}

/**
 * Parses the air-quality response body into `{aqi, uv}`. Invalid JSON, a
 * non-object body or a missing `current` block gives null (read as "the air
 * request failed", hiding the chips); a present `current` with a missing or
 * non-numeric field gives null for that field only.
 * @param {string|undefined} json - the response body
 * @returns {ParsedAir|null} the parsed reading, or null
 */
function parseAir(json) {
  var data
  try {
    data = JSON.parse(String(json))
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object") return null
  var current = data.current
  if (!current || typeof current !== "object") return null
  var aqi = isFiniteNumber(current.european_aqi) ? current.european_aqi : null
  var uv = isFiniteNumber(current.uv_index) ? current.uv_index : null
  return { aqi: aqi, uv: uv }
}

/**
 * Parses an open-meteo `timezone=auto` local ISO time string
 * ("2026-10-02T20:15", seconds optional) into a sortable number, by reading
 * its wall-clock digits directly rather than through the host's timezone
 * (so this module never depends on where it runs). Only values from this
 * module's own local-time strings should ever be compared against each
 * other.
 * @param {*} s - the ISO string
 * @returns {number} a sortable value, or NaN when it doesn't parse
 */
function parseLocalIso(s) {
  if (typeof s !== "string") return NaN
  var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/.exec(s)
  if (!m) return NaN
  return Date.UTC(
    Number(m[1]),
    Number(m[2]) - 1,
    Number(m[3]),
    Number(m[4]),
    Number(m[5]),
    m[6] ? Number(m[6]) : 0
  )
}

/**
 * The index of the latest entry in a local-ISO time series at or before a
 * given instant, assuming ascending order (as open-meteo returns them).
 * @param {string[]} times - local ISO time strings, ascending
 * @param {number} ms - the instant, from `parseLocalIso`
 * @returns {number} the index, or -1 when every entry is after `ms`
 */
function latestIndexAtOrBefore(times, ms) {
  var idx = -1
  for (var i = 0; i < times.length; i++) {
    var t = parseLocalIso(times[i])
    if (!isFiniteNumber(t)) continue
    if (t <= ms) idx = i
    else break
  }
  return idx
}

/**
 * The "rain soon" line from the minutely-15 precipitation trace: "Raining
 * now" when the slot containing `nowIso` already exceeds the 0.1mm
 * threshold, else the first later slot that does ("Rain in ~N min", N
 * rounded to the nearest 5 minutes, floored at 5), else "Dry for the next
 * 3 h". Missing or empty minutely data, or an unparseable `nowIso`, reads
 * "" (hides the row) rather than throwing.
 * @param {MinutelySeries|null|undefined} minutely - from `parseOpenMeteo`
 * @param {string} nowIso - the current instant, as a local ISO string
 * @returns {string} the line to show, or ""
 */
function rainSoon(minutely, nowIso) {
  if (!minutely || !Array.isArray(minutely.time) || !Array.isArray(minutely.precip)) return ""
  var times = minutely.time
  var precip = minutely.precip
  if (times.length === 0) return ""
  var nowMs = parseLocalIso(nowIso)
  if (!isFiniteNumber(nowMs)) return ""

  var currentIdx = latestIndexAtOrBefore(times, nowMs)
  if (currentIdx >= 0) {
    var currentPrecip = Number(precip[currentIdx])
    if (isFiniteNumber(currentPrecip) && currentPrecip > 0.1) return "Raining now"
  }

  for (var j = currentIdx + 1; j < times.length; j++) {
    var p = Number(precip[j])
    if (!isFiniteNumber(p) || p <= 0.1) continue
    var slotMs = parseLocalIso(times[j])
    if (!isFiniteNumber(slotMs)) continue
    var minutes = Math.round((slotMs - nowMs) / 60000)
    var rounded = Math.round(minutes / 5) * 5
    if (rounded < 5) rounded = 5
    return "Rain in ~" + rounded + " min"
  }

  return "Dry for the next 3 h"
}

var COMPASS_LABELS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

/**
 * The wind compass for a meteorological direction: the 8-point label for
 * where the wind is coming FROM (`deg`, as open-meteo's
 * `wind_direction_10m` reports it), and `rotation` (`deg + 180`), the angle
 * an arrow should be turned to so it points where the wind blows TO. An
 * invalid `deg` reads a blank label and a zero rotation rather than
 * throwing.
 * @param {number} deg - the meteorological wind direction, degrees, 0-360 (wraps)
 * @returns {Compass} the label and the arrow's rotation
 */
function compass(deg) {
  if (!isFiniteNumber(deg)) return { label: "", rotation: 0 }
  var normalized = ((deg % 360) + 360) % 360
  var index = Math.round(normalized / 45) % 8
  return { label: COMPASS_LABELS[index], rotation: deg + 180 }
}

/**
 * The pressure trend arrow from the 3-hour change: up for a rise above
 * +1hPa, down for a fall below -1hPa, otherwise flat. Missing hourly data,
 * an unparseable `nowIso`, or no slot 3 hours before `nowIso` within the
 * series reads "" (hides the row) rather than throwing.
 * @param {HourlySeries|null|undefined} hourly - from `parseOpenMeteo`
 * @param {string} nowIso - the current instant, as a local ISO string
 * @returns {"↑"|"↓"|"→"|""} the trend arrow, or ""
 */
function pressureTrend(hourly, nowIso) {
  if (!hourly || !Array.isArray(hourly.time) || !Array.isArray(hourly.pressure)) return ""
  var times = hourly.time
  var pressure = hourly.pressure
  if (times.length === 0) return ""
  var nowMs = parseLocalIso(nowIso)
  if (!isFiniteNumber(nowMs)) return ""

  var nowIdx = latestIndexAtOrBefore(times, nowMs)
  if (nowIdx < 0) return ""
  var pastIdx = latestIndexAtOrBefore(times, nowMs - 3 * 3600000)
  if (pastIdx < 0) return ""

  var nowP = Number(pressure[nowIdx])
  var pastP = Number(pressure[pastIdx])
  if (!isFiniteNumber(nowP) || !isFiniteNumber(pastP)) return ""

  var diff = nowP - pastP
  if (diff > 1) return "↑"
  if (diff < -1) return "↓"
  return "→"
}

/**
 * The European AQI band for a value: Good (<20), Fair (<40), Moderate
 * (<60), Poor (<80), Very poor (<=100) or Extremely poor (>100). The chip's
 * tone is accent ("good") for Good/Fair, plain for Moderate, urgent ("bad")
 * for Poor and worse. A missing or non-finite value gives null (hides the
 * chip).
 * @param {number} n - the European AQI value
 * @returns {Band|null} the band, or null
 */
function aqiBand(n) {
  if (!isFiniteNumber(n)) return null
  if (n < 20) return { label: "Good", tone: "good" }
  if (n < 40) return { label: "Fair", tone: "good" }
  if (n < 60) return { label: "Moderate", tone: "plain" }
  if (n < 80) return { label: "Poor", tone: "bad" }
  if (n <= 100) return { label: "Very poor", tone: "bad" }
  return { label: "Extremely poor", tone: "bad" }
}

/**
 * The WHO UV index band for a value: Low (<3), Moderate (<6), High (<8),
 * Very high (<11) or Extreme (>=11). A missing or non-finite value gives
 * null (hides the chip).
 * @param {number} n - the UV index value
 * @returns {UvBand|null} the band, or null
 */
function uvBand(n) {
  if (!isFiniteNumber(n)) return null
  if (n < 3) return { label: "Low" }
  if (n < 6) return { label: "Moderate" }
  if (n < 8) return { label: "High" }
  if (n < 11) return { label: "Very high" }
  return { label: "Extreme" }
}

/**
 * The next-24h temperature trace and rain-chance bars, starting at the
 * hourly slot containing `nowIso` and running for up to `slots` hours:
 * temperature points normalised 0..1 against the selected window's own
 * min/max (a flat window reads 0.5 throughout), and rain-chance bars
 * normalised from the 0-100 percent probability. `min`/`max`/`now` carry
 * the actual degree values for the caption. Missing hourly data, an
 * unparseable `nowIso`, or no slot at or before it gives the empty shape
 * (hides the section) rather than throwing.
 * @param {HourlySeries|null|undefined} hourly - from `parseOpenMeteo`
 * @param {string} nowIso - the current instant, as a local ISO string
 * @param {number} slots - how many hourly points to take, from now onward (at least 1)
 * @returns {HourlyPoints} the trace, or the empty shape
 */
function hourlyPoints(hourly, nowIso, slots) {
  /** @type {HourlyPoints} */
  var empty = { temp: [], rain: [], min: null, max: null, now: null }
  if (!hourly || !Array.isArray(hourly.time) || !Array.isArray(hourly.temp)) return empty
  var times = hourly.time
  var temps = hourly.temp
  var rainProb = Array.isArray(hourly.rain) ? hourly.rain : []
  if (times.length === 0) return empty
  var nowMs = parseLocalIso(nowIso)
  if (!isFiniteNumber(nowMs)) return empty

  var nowIdx = latestIndexAtOrBefore(times, nowMs)
  if (nowIdx < 0) return empty

  var count = Math.max(1, Math.floor(Number(slots)) || 1)
  var endIdx = Math.min(times.length, nowIdx + count)
  var n = endIdx - nowIdx

  var selected = []
  for (var i = 0; i < n; i++) {
    var tv = Number(temps[nowIdx + i])
    if (isFiniteNumber(tv)) selected.push(tv)
  }
  if (selected.length === 0) return empty

  var min = Math.min.apply(null, selected)
  var max = Math.max.apply(null, selected)
  var span = max - min

  var temp = []
  var rain = []
  for (var j = 0; j < n; j++) {
    var idx = nowIdx + j
    var x = n > 1 ? j / (n - 1) : 0
    var t = Number(temps[idx])
    if (isFiniteNumber(t)) temp.push({ x: x, y: span > 0 ? (t - min) / span : 0.5 })
    var r = Number(rainProb[idx])
    var h = isFiniteNumber(r) ? Math.max(0, Math.min(1, r / 100)) : 0
    rain.push({ x: x, h: h })
  }

  var nowTemp = Number(temps[nowIdx])
  return {
    temp: temp,
    rain: rain,
    min: min,
    max: max,
    now: isFiniteNumber(nowTemp) ? nowTemp : null
  }
}

var KMH_TO_MPH = 0.621371
var HPA_TO_INHG = 0.0295299830714

/**
 * Converts km/h to mph.
 * @param {number} kmh - speed in km/h
 * @returns {number} speed in mph (NaN for invalid input)
 */
function kmhToMph(kmh) {
  return isFiniteNumber(kmh) ? kmh * KMH_TO_MPH : NaN
}

/**
 * Converts hPa to inHg.
 * @param {number} hpa - pressure in hPa
 * @returns {number} pressure in inHg (NaN for invalid input)
 */
function hpaToInHg(hpa) {
  return isFiniteNumber(hpa) ? hpa * HPA_TO_INHG : NaN
}

/**
 * Converts km to miles (the same factor as km/h to mph).
 * @param {number} km - distance in km
 * @returns {number} distance in miles (NaN for invalid input)
 */
function kmToMi(km) {
  return isFiniteNumber(km) ? km * KMH_TO_MPH : NaN
}

/**
 * Formats a wind speed, converting to mph when imperial. Invalid input
 * gives "" rather than throwing.
 * @param {number} kmh - speed in km/h
 * @param {boolean} imperial - whether to show mph instead of km/h
 * @returns {string} e.g. "14 km/h" or "9 mph"
 */
function formatWind(kmh, imperial) {
  if (!isFiniteNumber(kmh)) return ""
  return imperial ? Math.round(kmhToMph(kmh)) + " mph" : Math.round(kmh) + " km/h"
}

/**
 * Formats a surface pressure, converting to inHg (2 decimals) when
 * imperial, else hPa (whole number). Invalid input gives "" rather than
 * throwing.
 * @param {number} hpa - pressure in hPa
 * @param {boolean} imperial - whether to show inHg instead of hPa
 * @returns {string} e.g. "1030 hPa" or "30.42 inHg"
 */
function formatPressure(hpa, imperial) {
  if (!isFiniteNumber(hpa)) return ""
  return imperial ? hpaToInHg(hpa).toFixed(2) + " inHg" : Math.round(hpa) + " hPa"
}

/**
 * Formats a visibility reading (open-meteo reports it in metres), as km or
 * mi when imperial. Invalid input gives "" rather than throwing.
 * @param {number} meters - visibility in metres
 * @param {boolean} imperial - whether to show mi instead of km
 * @returns {string} e.g. "20 km" or "12 mi"
 */
function formatVisibility(meters, imperial) {
  if (!isFiniteNumber(meters)) return ""
  var km = meters / 1000
  return imperial ? Math.round(kmToMi(km)) + " mi" : Math.round(km) + " km"
}

/**
 * The freshest peer report younger than the refresh interval, so a
 * multi-monitor setup makes one fetch per interval instead of one per
 * screen (the Clock lesson, `bar.moduleWidgets(entryId)`). A peer with no
 * report, a non-finite `fetchedAt`, or one at least `refreshMinutes` old is
 * ignored; among the rest, the most recently fetched one wins.
 * @param {Array<PeerReport>|undefined} peers - the other instances' last-fetched reports
 * @param {number} nowMs - the current instant, milliseconds
 * @param {number} refreshMinutes - the refresh interval, minutes
 * @returns {object|null} the freshest peer's report, or null to fetch
 */
function sharedReport(peers, nowMs, refreshMinutes) {
  if (!Array.isArray(peers)) return null
  var intervalMs = Math.max(0, Number(refreshMinutes) || 0) * 60000
  var best = null
  for (var i = 0; i < peers.length; i++) {
    var p = peers[i]
    if (!p || !p.report || !isFiniteNumber(p.fetchedAt)) continue
    var age = nowMs - p.fetchedAt
    if (age >= intervalMs) continue
    if (!best || p.fetchedAt > best.fetchedAt) best = p
  }
  return best ? best.report : null
}

/**
 * Parses wttr.in's `nearest_area[0]` coordinates (used as the open-meteo
 * request's location while the configured location is automatic). Invalid
 * JSON, a missing/empty `nearest_area`, or unparseable coordinates give
 * null rather than throwing.
 * @param {string|undefined} j1json - wttr.in's `?format=j1` response body
 * @returns {{lat: number, lon: number}|null} the coordinates, or null
 */
function wttrCoords(j1json) {
  var data
  try {
    data = JSON.parse(String(j1json))
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object") return null
  var areas = data.nearest_area
  if (!Array.isArray(areas) || areas.length === 0) return null
  var area = areas[0]
  if (!area || typeof area !== "object") return null
  var lat = parseFloat(area.latitude)
  var lon = parseFloat(area.longitude)
  if (!isFinite(lat) || !isFinite(lon)) return null
  return { lat: lat, lon: lon }
}

if (typeof module !== "undefined")
  module.exports = {
    buildForecastUrl: buildForecastUrl,
    buildAirUrl: buildAirUrl,
    parseOpenMeteo: parseOpenMeteo,
    parseAir: parseAir,
    rainSoon: rainSoon,
    compass: compass,
    pressureTrend: pressureTrend,
    aqiBand: aqiBand,
    uvBand: uvBand,
    hourlyPoints: hourlyPoints,
    kmhToMph: kmhToMph,
    hpaToInHg: hpaToInHg,
    kmToMi: kmToMi,
    formatWind: formatWind,
    formatPressure: formatPressure,
    formatVisibility: formatVisibility,
    sharedReport: sharedReport,
    wttrCoords: wttrCoords
  }
