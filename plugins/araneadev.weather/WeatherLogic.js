// Pure rules for the Aranea Weather dropdown (Panel.qml): the open-meteo
// forecast and air-quality request URLs (stock's fields plus the extras),
// parsing both responses, "rain soon" from the minutely trace, the wind
// compass (label plus the arrow's rotation to where the wind blows to), the
// 3-hour pressure trend arrow, the European AQI and WHO UV bands, the
// next-24h temperature/rain-chance points for the hourly trace (normalised
// 0..1), unit conversions and their formatted strings, the shared-report
// freshness check across per-monitor instances (the Clock lesson), parsing
// wttr.in's nearest_area down to coordinates only, and the pieces Panel's
// view object is built from (hour labels and the trace caption, the
// condition label, the days from today, keyed suggestion rows and picks,
// the air chips, the detail cells, the shared bundle and the automatic
// refresh plan). No QML, no I/O,
// no `Date.now()` (every "now" is passed in explicitly, as an open-meteo
// `timezone=auto` local ISO string, and compared by its wall-clock digits
// rather than through the host's timezone); tests/js/weather-logic.test.js
// runs this under Node.
//
// open-meteo's `timezone=auto` reports times in the requested LOCATION's
// local time, not the host's. A host-local `new Date()` string would
// misalign rainSoon/pressureTrend/hourlyPoints whenever the machine's
// timezone differs from the forecast location's (and `current.time` is no
// substitute: it is quantized to 15 minutes and goes stale while a report
// is shared across monitors). Callers must build "now" with `nowIsoAt`
// instead, from `Date.now()` and the parsed report's own
// `utcOffsetSeconds`.

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
 * @typedef {{current: object|null, hourly: HourlySeries, minutely: MinutelySeries, utcOffsetSeconds: number}} ParsedForecast
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
 * Parses open-meteo's forecast response body into the current reading, the
 * index-aligned hourly/minutely series this dropdown reads, and the
 * location's UTC offset (for `nowIsoAt`). Invalid JSON or a non-object body
 * gives null; a valid body missing `hourly` or `minutely_15` gives empty
 * series rather than throwing, so a response that only has `current` still
 * parses; a missing or non-finite `utc_offset_seconds` reads as 0.
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

  var utcOffsetSeconds = isFiniteNumber(data.utc_offset_seconds) ? data.utc_offset_seconds : 0

  return {
    current: current,
    hourly: hourly,
    minutely: minutely,
    utcOffsetSeconds: utcOffsetSeconds
  }
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
 * Zero-pads a non-negative integer to at least 2 digits.
 * @param {number} n - the value
 * @returns {string} "07", "43"
 */
function pad2(n) {
  var s = String(n)
  return s.length < 2 ? "0" + s : s
}

/**
 * Builds the local-ISO "now" string the location's local time needs:
 * `nowMs` (from `Date.now()`) shifted by the forecast's own
 * `utcOffsetSeconds` (from `parseOpenMeteo`), then read back through UTC
 * fields rather than the host's timezone, so the result reflects the
 * LOCATION's wall clock regardless of where this runs. This is the only
 * correct way to build the `nowIso` that `rainSoon`, `pressureTrend` and
 * `hourlyPoints` take; a host-local `new Date()` string would misalign
 * whenever the machine's timezone differs from the forecast location's.
 * A non-finite `nowMs` gives "" (every reader treats that as "no data");
 * a non-finite `utcOffsetSeconds` is treated as 0.
 * @param {number} nowMs - the current instant, milliseconds since the Unix epoch
 * @param {number} utcOffsetSeconds - the forecast location's UTC offset, seconds
 * @returns {string} "2026-10-02T20:15", or ""
 */
function nowIsoAt(nowMs, utcOffsetSeconds) {
  if (!isFiniteNumber(nowMs)) return ""
  var offset = isFiniteNumber(utcOffsetSeconds) ? utcOffsetSeconds : 0
  var d = new Date(nowMs + offset * 1000)
  return (
    d.getUTCFullYear() +
    "-" +
    pad2(d.getUTCMonth() + 1) +
    "-" +
    pad2(d.getUTCDate()) +
    "T" +
    pad2(d.getUTCHours()) +
    ":" +
    pad2(d.getUTCMinutes())
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

var SLOT_MS = 15 * 60000

/**
 * The "rain soon" line from the minutely-15 precipitation trace.
 * open-meteo's `minutely_15` precipitation is the sum over the PRECEDING 15
 * minutes: the slot stamped T covers (T-15, T]. So the slot containing now
 * is the first one stamped after now, and the slot just ended is the latest
 * one stamped at or before now. "Raining now" when either exceeds the 0.1mm
 * threshold; else the first later wet slot, N minutes from now to its start
 * (T-15), rounded to the nearest 5 and at least 5 ("Rain in ~N min"; a
 * start already reached reads "Raining now"); else "Dry for the next 3 h".
 * Missing or empty minutely data, an unparseable `nowIso`, or a now at or
 * past the last slot's end (stale data) reads "" (hides the row) rather
 * than claiming dry or raining.
 * @param {MinutelySeries|null|undefined} minutely - from `parseOpenMeteo`
 * @param {string} nowIso - the current instant in the forecast LOCATION's
 *   local time, from `nowIsoAt(Date.now(), report.utcOffsetSeconds)`; never
 *   a host-local `new Date()` string, which would misalign this whenever
 *   the machine's timezone differs from the location's
 * @returns {string} the line to show, or ""
 */
function rainSoon(minutely, nowIso) {
  if (!minutely || !Array.isArray(minutely.time) || !Array.isArray(minutely.precip)) return ""
  var times = minutely.time
  var precip = minutely.precip
  if (times.length === 0) return ""
  var nowMs = parseLocalIso(nowIso)
  if (!isFiniteNumber(nowMs)) return ""

  var endedIdx = latestIndexAtOrBefore(times, nowMs)
  var nextIdx = -1
  for (var i = endedIdx + 1; i < times.length; i++) {
    if (isFiniteNumber(parseLocalIso(times[i]))) {
      nextIdx = i
      break
    }
  }
  // Stale: every slot has ended, so nothing is known about now or later.
  if (nextIdx < 0) return ""

  /**
   * Whether slot IDX's precipitation is above the 0.1mm threshold.
   * @param {number} idx - the slot's index
   * @returns {boolean} true when it rains in that slot
   */
  var wet = function (idx) {
    var p = Number(precip[idx])
    return isFiniteNumber(p) && p > 0.1
  }
  if (endedIdx >= 0 && wet(endedIdx)) return "Raining now"

  for (var j = nextIdx; j < times.length; j++) {
    if (!wet(j)) continue
    var slotMs = parseLocalIso(times[j])
    if (!isFiniteNumber(slotMs)) continue
    var minutes = (slotMs - SLOT_MS - nowMs) / 60000
    if (minutes <= 0) return "Raining now"
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
 * @param {string} nowIso - the current instant in the forecast LOCATION's
 *   local time, from `nowIsoAt(Date.now(), report.utcOffsetSeconds)`; never
 *   a host-local `new Date()` string, which would misalign this whenever
 *   the machine's timezone differs from the location's
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
 * normalised from the 0-100 percent probability. open-meteo's hourly
 * `precipitation_probability` describes the PRECEDING hour, so the bar
 * under each hour takes the next slot's value (0 past the series' end). `min`/`max`/`now` carry
 * the actual degree values for the caption. Missing hourly data, an
 * unparseable `nowIso`, or no slot at or before it gives the empty shape
 * (hides the section) rather than throwing.
 * @param {HourlySeries|null|undefined} hourly - from `parseOpenMeteo`
 * @param {string} nowIso - the current instant in the forecast LOCATION's
 *   local time, from `nowIsoAt(Date.now(), report.utcOffsetSeconds)`; never
 *   a host-local `new Date()` string, which would misalign this whenever
 *   the machine's timezone differs from the location's
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
    // precipitation_probability is a preceding-hour value: the hour from
    // this slot onward is reported at the next slot.
    var r = Number(rainProb[idx + 1])
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

/**
 * The hour labels under the next-24h trace: COUNT labels spread evenly over
 * the same window `hourlyPoints` draws (the hourly slot containing `nowIso`
 * onward, up to `slots` hours), the first reading "now" and the rest the
 * slot's two-digit hour ("03"). No window (missing data, an unparseable
 * `nowIso` or no slot at or before it) gives [].
 * @param {HourlySeries|null|undefined} hourly - from `parseOpenMeteo`
 * @param {string} nowIso - the location's "now", from `nowIsoAt`
 * @param {number} slots - the window's length in hours, as given to `hourlyPoints`
 * @param {number} count - how many labels to spread over it (at least 2)
 * @returns {string[]} the labels, left to right
 */
function hourLabels(hourly, nowIso, slots, count) {
  if (!hourly || !Array.isArray(hourly.time) || hourly.time.length === 0) return []
  var nowMs = parseLocalIso(nowIso)
  if (!isFiniteNumber(nowMs)) return []
  var nowIdx = latestIndexAtOrBefore(hourly.time, nowMs)
  if (nowIdx < 0) return []
  var n =
    Math.min(hourly.time.length, nowIdx + Math.max(1, Math.floor(Number(slots)) || 1)) - nowIdx
  var labels = Math.max(2, Math.floor(Number(count)) || 2)
  var out = ["now"]
  if (n < 2) return out
  for (var i = 1; i < labels; i++) {
    var idx = nowIdx + Math.round((i * (n - 1)) / (labels - 1))
    var m = /T(\d{2})/.exec(String(hourly.time[idx]))
    out.push(m ? m[1] : "")
  }
  return out
}

/**
 * A Celsius value as a bare rounded degree in the active unit ("17°", or
 * "63°" imperial), "" when it is not a finite number.
 * @param {*} celsius - the temperature, deg C
 * @param {boolean} imperial - whether to show Fahrenheit
 * @returns {string} the degree text, or ""
 */
function bareDegrees(celsius, imperial) {
  var c = typeof celsius === "string" && celsius !== "" ? Number(celsius) : celsius
  if (!isFiniteNumber(c)) return ""
  return Math.round(imperial ? (c * 9) / 5 + 32 : c) + "°"
}

/**
 * The next-24h caption from `hourlyPoints`'s actual degrees: "now → min →
 * max" ("17° → 11° → 19°"), "" without them.
 * @param {HourlyPoints|null|undefined} points - from `hourlyPoints`
 * @param {boolean} imperial - whether to show Fahrenheit
 * @returns {string} the caption, or ""
 */
function hourlyCaption(points, imperial) {
  if (!points) return ""
  var parts = [points.now, points.min, points.max].map(function (v) {
    return bareDegrees(v, imperial)
  })
  return parts.indexOf("") >= 0 ? "" : parts.join(" → ")
}

/** @type {Record<number, string>} */
var WMO_LABELS = {
  0: "Clear",
  1: "Mainly clear",
  2: "Partly cloudy",
  3: "Overcast",
  45: "Fog",
  48: "Rime fog",
  51: "Light drizzle",
  53: "Drizzle",
  55: "Heavy drizzle",
  56: "Freezing drizzle",
  57: "Freezing drizzle",
  61: "Light rain",
  63: "Rain",
  65: "Heavy rain",
  66: "Freezing rain",
  67: "Freezing rain",
  71: "Light snow",
  73: "Snow",
  75: "Heavy snow",
  77: "Snow grains",
  80: "Light showers",
  81: "Showers",
  82: "Heavy showers",
  85: "Snow showers",
  86: "Heavy snow showers",
  95: "Thunderstorm",
  96: "Thunderstorm, hail",
  99: "Thunderstorm, hail"
}

/**
 * The condition label under the hero temperature, from the current row the
 * panel uses (Model.js's shape): open-meteo's WMO weather code when the row
 * came from open-meteo, else wttr.in's own `weatherDesc`. "" when neither
 * names a condition.
 * @param {*} current - the panel's current-conditions row, or null
 * @returns {string} e.g. "Partly cloudy", or ""
 */
function conditionLabel(current) {
  if (!current || typeof current !== "object") return ""
  var code = current.openMeteoWeatherCode
  if (code !== undefined && code !== null) {
    var label = WMO_LABELS[parseInt(String(code), 10)]
    return typeof label === "string" ? label : ""
  }
  var desc =
    Array.isArray(current.weatherDesc) && current.weatherDesc[0] ? current.weatherDesc[0].value : ""
  return typeof desc === "string" ? desc.trim() : ""
}

/**
 * The forecast days the dropdown shows: today and the days after it, up to
 * COUNT, in Model.js's day shape (so its `bareTempForDay` and `dayIcon`
 * read them). open-meteo's daily block when it has today or later, else
 * wttr.in's `weather` days (stock's fallback order).
 * @param {*} report - wttr.in's parsed j1 response, or null
 * @param {*} daily - open-meteo's parsed forecast response (with `daily`), or null
 * @param {string} todayString - today's "yyyy-MM-dd" at the forecast location
 * @param {number} count - the most days to return
 * @returns {Array<object>} the days, today first
 */
function forecastFromToday(report, daily, todayString, count) {
  var max = Math.max(1, Math.floor(Number(count)) || 1)
  var today = String(todayString || "")
  var d = daily && daily.daily && Array.isArray(daily.daily.time) ? daily.daily : null
  var out = []
  if (d) {
    for (var i = 0; i < d.time.length && out.length < max; i++) {
      var date = String(d.time[i] || "")
      if (date.slice(0, 10) < today) continue
      var hi = Array.isArray(d.temperature_2m_max) ? d.temperature_2m_max[i] : null
      var lo = Array.isArray(d.temperature_2m_min) ? d.temperature_2m_min[i] : null
      out.push({
        date: date,
        maxtempC: bareDegrees(hi, false).replace("°", ""),
        mintempC: bareDegrees(lo, false).replace("°", ""),
        maxtempF: bareDegrees(hi, true).replace("°", ""),
        mintempF: bareDegrees(lo, true).replace("°", ""),
        openMeteoWeatherCode: Array.isArray(d.weather_code) ? d.weather_code[i] : null
      })
    }
    if (out.length > 0) return out
  }
  var days = report && Array.isArray(report.weather) ? report.weather : []
  for (var j = 0; j < days.length && out.length < max; j++)
    if (days[j] && String(days[j].date || "").slice(0, 10) >= today) out.push(days[j])
  return out
}

/**
 * A geocoding suggestion's key: its name and coordinates, so a pick names
 * the place the user saw even if the list was replaced underneath.
 * @param {*} suggestion - a Model.parseGeocodingResults row
 * @returns {string} "name|lat|lon", or "" for no row
 */
function suggestionKey(suggestion) {
  if (!suggestion || typeof suggestion !== "object") return ""
  return (
    String(suggestion.name) + "|" + String(suggestion.latitude) + "|" + String(suggestion.longitude)
  )
}

/**
 * The suggestion rows the view draws: {key, name, description}.
 * @param {*} suggestions - Model.parseGeocodingResults rows
 * @returns {Array<{key: string, name: string, description: string}>} the rows
 */
function suggestionRows(suggestions) {
  if (!Array.isArray(suggestions)) return []
  return suggestions.map(function (s) {
    return {
      key: suggestionKey(s),
      name: s && s.name ? String(s.name) : "",
      description: s && s.description ? String(s.description) : ""
    }
  })
}

/**
 * The suggestion a keyed pick names, only when row INDEX of the CURRENT
 * suggestions still carries KEY; null otherwise (the pick is refused).
 * @param {*} suggestions - the current Model.parseGeocodingResults rows
 * @param {*} index - the row the pick names
 * @param {*} key - the key the view saw at that row
 * @returns {object|null} the suggestion, or null
 */
function suggestionAt(suggestions, index, key) {
  if (!Array.isArray(suggestions) || typeof key !== "string" || key === "") return null
  if (typeof index !== "number" || index < 0 || index >= suggestions.length) return null
  var s = suggestions[index]
  return suggestionKey(s) === key ? s : null
}

/**
 * The view's air part from `parseAir`'s reading: an AQI chip ("AQI 53 ·
 * Fair", toned) and a UV chip ("UV 5 · Moderate"), each banded on the
 * rounded value it shows and hidden without its value; both hidden when
 * the air request failed (null).
 * @param {ParsedAir|null|undefined} air - from `parseAir`
 * @returns {{aqi: {visible: boolean, text: string, tone: string}, uv: {visible: boolean, text: string}}} the chips
 */
function airView(air) {
  // Banded on the rounded value the chip shows, so "UV 3" never reads Low.
  var aqiValue = air && isFiniteNumber(air.aqi) ? Math.round(air.aqi) : null
  var uvValue = air && isFiniteNumber(air.uv) ? Math.round(air.uv) : null
  var aqi = aqiValue === null ? null : aqiBand(aqiValue)
  var uv = uvValue === null ? null : uvBand(uvValue)
  return {
    aqi: {
      visible: !!aqi,
      text: aqi ? "AQI " + aqiValue + " · " + aqi.label : "",
      tone: aqi ? aqi.tone : "plain"
    },
    uv: {
      visible: !!uv,
      text: uv ? "UV " + uvValue + " · " + uv.label : ""
    }
  }
}

/**
 * One cell of the details grid: its key, label and value, with the wind's
 * arrow rotation and compass label, or the pressure trend.
 * @typedef {{key: string, label: string, value: string, arrow?: number, dir?: string, trend?: string}} DetailCell
 */

/**
 * The details grid's cells, in the mockup's order (feels, humid, wind,
 * gusts, pressure, visibility), each dropped when its value is "". Wind
 * gets the compass arrow and label when a direction is known; pressure
 * gets its trend when there is one.
 * @param {{feels?: string, humid?: string, wind?: string, windDeg?: *, gustsKmh?: *, pressureHpa?: *, trend?: string, visibilityM?: *, imperial?: boolean}} d - the readings: feels, humid and wind already formatted (stock's), the rest raw open-meteo values
 * @returns {Array<DetailCell>} the cells
 */
function detailCells(d) {
  var r = d || {}
  var imperial = !!r.imperial
  /** @type {Array<DetailCell>} */
  var cells = []
  /**
   * Adds a cell when its value is not empty.
   * @param {DetailCell} cell - the cell
   */
  function add(cell) {
    if (cell.value !== "") cells.push(cell)
  }
  add({ key: "feels", label: "Feels", value: String(r.feels || "") })
  add({ key: "humid", label: "Humid", value: String(r.humid || "") })
  /** @type {DetailCell} */
  var wind = { key: "wind", label: "Wind", value: String(r.wind || "") }
  var deg = Number(r.windDeg)
  if (r.windDeg !== null && r.windDeg !== undefined && r.windDeg !== "" && isFiniteNumber(deg)) {
    var c = compass(deg)
    wind.arrow = c.rotation
    wind.dir = c.label
  }
  add(wind)
  add({ key: "gusts", label: "Gusts", value: formatWind(r.gustsKmh, imperial) })
  /** @type {DetailCell} */
  var pressure = {
    key: "pressure",
    label: "Pressure",
    value: formatPressure(r.pressureHpa, imperial)
  }
  if (r.trend) pressure.trend = String(r.trend)
  add(pressure)
  add({ key: "visibility", label: "Visibility", value: formatVisibility(r.visibilityM, imperial) })
  return cells
}

/**
 * The bundle a refresh may adopt instead of fetching: the freshest
 * instance bundle (`{locationQuery, fetchedAtMs, ...}`) for the same
 * location query and younger than `freshMinutes` (`sharedReport`), or null.
 * @param {Array<*>|undefined} bundles - the instances' published bundles
 * @param {string} locationQuery - this instance's location query
 * @param {number} nowMs - the current instant, milliseconds
 * @param {number} freshMinutes - how young a bundle must be, minutes
 * @returns {object|null} the bundle to adopt, or null
 */
function sharedBundle(bundles, locationQuery, nowMs, freshMinutes) {
  if (!Array.isArray(bundles)) return null
  var peers = []
  for (var i = 0; i < bundles.length; i++) {
    var b = bundles[i]
    if (b && typeof b === "object" && b.locationQuery === locationQuery)
      peers.push({ fetchedAt: b.fetchedAtMs, report: b })
  }
  return sharedReport(peers, nowMs, freshMinutes)
}

/**
 * What an automatic refresh (the timer, an open, a location change) does,
 * so the per-monitor instances make one fetch per interval between them:
 * "defer" (try again shortly) until the bar is injected, so the other
 * instances can be seen; "skip" while this instance is already fetching;
 * "adopt" a fresh bundle (any instance's, this one's included); "wait"
 * while another instance is fetching the same location (its publish
 * reaches this one); else "fetch". An explicit refresh never asks: it
 * fetches.
 * @param {{ready: boolean, selfFetching: boolean, fresh: boolean, peerFetching: boolean}} s - the state
 * @returns {string} "defer", "skip", "adopt", "wait" or "fetch"
 */
function refreshPlan(s) {
  var st = s || { ready: true, selfFetching: false, fresh: false, peerFetching: false }
  if (!st.ready) return "defer"
  if (st.selfFetching) return "skip"
  if (st.fresh) return "adopt"
  if (st.peerFetching) return "wait"
  return "fetch"
}

/**
 * Whether a weather response (or an adopted report) may end the pending
 * place: only while a save is pending, once its refetch has started, and
 * never while omarchy-weather-location still runs (its exit ends it).
 * @param {boolean} saving - whether a place is pending
 * @param {boolean} queryStarted - whether the refetch for it has started
 * @param {boolean} saveRunning - whether omarchy-weather-location is running
 * @returns {boolean} true to end the pending place now
 */
function saveEnds(saving, queryStarted, saveRunning) {
  return !!saving && !!queryStarted && !saveRunning
}

if (typeof module !== "undefined")
  module.exports = {
    buildForecastUrl: buildForecastUrl,
    buildAirUrl: buildAirUrl,
    parseOpenMeteo: parseOpenMeteo,
    parseAir: parseAir,
    nowIsoAt: nowIsoAt,
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
    wttrCoords: wttrCoords,
    hourLabels: hourLabels,
    bareDegrees: bareDegrees,
    hourlyCaption: hourlyCaption,
    conditionLabel: conditionLabel,
    forecastFromToday: forecastFromToday,
    suggestionKey: suggestionKey,
    suggestionRows: suggestionRows,
    suggestionAt: suggestionAt,
    airView: airView,
    detailCells: detailCells,
    sharedBundle: sharedBundle,
    refreshPlan: refreshPlan,
    saveEnds: saveEnds
  }
