// Logic contract for WeatherLogic.js: the open-meteo forecast and
// air-quality URLs, parsing both responses, rain soon, the wind compass,
// the pressure trend, the AQI/UV bands, the hourly trace points, unit
// conversions and their formatted strings, shared-report freshness and
// wttr.in coordinate parsing. Run with `node --test tests/js/`
// (tools/check runs it with coverage).
//
// TZ is pinned before any require, as the Clock tests do, even though this
// module never reads the host clock: every "now" is a `timezone=auto`
// local ISO string compared by its own wall-clock digits, never through
// `Date.now()` or the host's zone. Pinning TZ here keeps that guarantee
// honest should a future change ever introduce a `new Date()` without
// explicit components.
process.env.TZ = "Europe/Amsterdam"

const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.weather/WeatherLogic.js"))

// --- buildForecastUrl / buildAirUrl -------------------------------------------------
//
// Field lists captured read-only against the Amsterdam stand-in (52.37,
// 4.90): `curl -s 'https://api.open-meteo.com/v1/forecast?latitude=52.37&longitude=4.90&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day,wind_direction_10m,wind_gusts_10m,surface_pressure,visibility&hourly=temperature_2m,precipitation_probability,surface_pressure&past_hours=3&forecast_hours=24&minutely_15=precipitation&forecast_minutely_15=12&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=4&timezone=auto'`
// and the air-quality endpoint with `current=european_aqi,uv_index&timezone=auto`.

test("buildForecastUrl: stock's daily/current fields plus the extras, hourly and minutely windows", () => {
  assert.equal(
    logic.buildForecastUrl(52.37, 4.9),
    "https://api.open-meteo.com/v1/forecast" +
      "?latitude=52.37&longitude=4.9" +
      "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
      "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day,wind_direction_10m,wind_gusts_10m,surface_pressure,visibility" +
      "&hourly=temperature_2m,precipitation_probability,surface_pressure&past_hours=3&forecast_hours=24" +
      "&minutely_15=precipitation&forecast_minutely_15=12" +
      "&forecast_days=4&timezone=auto"
  )
})

test("buildForecastUrl: coordinates are URL-encoded", () => {
  const url = logic.buildForecastUrl(-33.87, 151.21)
  assert.ok(url.indexOf("latitude=-33.87") !== -1)
  assert.ok(url.indexOf("longitude=151.21") !== -1)
})

test("buildAirUrl: the air-quality endpoint with current AQI and UV", () => {
  assert.equal(
    logic.buildAirUrl(52.37, 4.9),
    "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=52.37&longitude=4.9&current=european_aqi,uv_index&timezone=auto"
  )
})

// --- parseOpenMeteo ------------------------------------------------------------------
//
// A trimmed, real-shaped fixture captured read-only against the Amsterdam
// stand-in (52.37, 4.90), rounded/redacted times.

const FORECAST_FIXTURE = JSON.stringify({
  latitude: 52.37,
  longitude: 4.9,
  timezone: "Europe/Amsterdam",
  utc_offset_seconds: 7200,
  current_units: { time: "iso8601", temperature_2m: "°C" },
  current: {
    time: "2026-10-02T20:00",
    temperature_2m: 17.1,
    apparent_temperature: 16.7,
    relative_humidity_2m: 70,
    wind_speed_10m: 6.5,
    weather_code: 0,
    is_day: 0,
    wind_direction_10m: 225,
    wind_gusts_10m: 15.8,
    surface_pressure: 1030.2,
    visibility: 19920.0
  },
  minutely_15_units: { time: "iso8601", precipitation: "mm" },
  minutely_15: {
    time: ["2026-10-02T19:30", "2026-10-02T19:45", "2026-10-02T20:00", "2026-10-02T20:15"],
    precipitation: [0.0, 0.0, 0.0, 0.0]
  },
  hourly_units: { time: "iso8601", temperature_2m: "°C" },
  hourly: {
    time: ["2026-10-02T17:00", "2026-10-02T18:00", "2026-10-02T19:00", "2026-10-02T20:00"],
    temperature_2m: [16.0, 16.5, 17.0, 17.1],
    precipitation_probability: [0, 0, 10, 20],
    surface_pressure: [1028.0, 1028.5, 1029.0, 1029.2]
  },
  daily_units: { time: "iso8601" },
  daily: {
    time: ["2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05"],
    weather_code: [3, 3, 51, 3],
    temperature_2m_max: [21.0, 20.4, 20.7, 18.9],
    temperature_2m_min: [13.1, 13.8, 15.7, 11.7]
  }
})

test("parseOpenMeteo parses a real-shaped redacted fixture into current/hourly/minutely", () => {
  const r = logic.parseOpenMeteo(FORECAST_FIXTURE)
  assert.ok(r)
  assert.equal(r.current.temperature_2m, 17.1)
  assert.equal(r.current.wind_direction_10m, 225)
  assert.deepEqual(r.hourly, {
    time: ["2026-10-02T17:00", "2026-10-02T18:00", "2026-10-02T19:00", "2026-10-02T20:00"],
    temp: [16.0, 16.5, 17.0, 17.1],
    rain: [0, 0, 10, 20],
    pressure: [1028.0, 1028.5, 1029.0, 1029.2]
  })
  assert.deepEqual(r.minutely, {
    time: ["2026-10-02T19:30", "2026-10-02T19:45", "2026-10-02T20:00", "2026-10-02T20:15"],
    precip: [0.0, 0.0, 0.0, 0.0]
  })
  // The location's UTC offset, for nowIsoAt: the fixture's Amsterdam
  // utc_offset_seconds (UTC+2, CEST).
  assert.equal(r.utcOffsetSeconds, 7200)
})

test("parseOpenMeteo gives null on invalid JSON or a non-object body, never throwing", () => {
  assert.equal(logic.parseOpenMeteo("not json"), null)
  assert.equal(logic.parseOpenMeteo(undefined), null)
  assert.equal(logic.parseOpenMeteo(""), null)
  assert.equal(logic.parseOpenMeteo("null"), null)
})

test("parseOpenMeteo gives empty series (not null) for a valid body missing hourly/minutely", () => {
  const r = logic.parseOpenMeteo(JSON.stringify({ current: { temperature_2m: 10 } }))
  assert.ok(r)
  assert.equal(r.current.temperature_2m, 10)
  assert.deepEqual(r.hourly, { time: [], temp: [], rain: [], pressure: [] })
  assert.deepEqual(r.minutely, { time: [], precip: [] })
})

test("parseOpenMeteo reads a missing current as null", () => {
  const r = logic.parseOpenMeteo(JSON.stringify({ hourly: { time: [] } }))
  assert.equal(r.current, null)
})

test("parseOpenMeteo reads a missing or non-finite utc_offset_seconds as 0", () => {
  assert.equal(logic.parseOpenMeteo(JSON.stringify({ current: {} })).utcOffsetSeconds, 0)
  assert.equal(
    logic.parseOpenMeteo(JSON.stringify({ current: {}, utc_offset_seconds: "x" })).utcOffsetSeconds,
    0
  )
})

// --- nowIsoAt (the forecast LOCATION's local "now", never the host's) --------------
//
// This file pins TZ=Europe/Amsterdam at the top, as the Clock tests do. The
// whole point of nowIsoAt is that it must NOT depend on that: it reads the
// UTC fields of nowMs+offset, never the host's zone. The offsets below are
// all different from Amsterdam's (+7200s), which is exactly what would
// expose a host-local `new Date()` bug if one crept back in.

test("nowIsoAt: UTC+2 (e.g. Amsterdam CEST)", () => {
  const nowMs = Date.UTC(2026, 9, 2, 18, 0, 0)
  assert.equal(logic.nowIsoAt(nowMs, 7200), "2026-10-02T20:00")
})

test("nowIsoAt: UTC-5 (e.g. US Eastern standard time)", () => {
  const nowMs = Date.UTC(2026, 9, 2, 18, 0, 0)
  assert.equal(logic.nowIsoAt(nowMs, -18000), "2026-10-02T13:00")
})

test("nowIsoAt: UTC+5:30 (e.g. India)", () => {
  const nowMs = Date.UTC(2026, 9, 2, 18, 0, 0)
  assert.equal(logic.nowIsoAt(nowMs, 19800), "2026-10-02T23:30")
})

test("nowIsoAt: the offset can roll the date forward into the next day", () => {
  const nowMs = Date.UTC(2026, 9, 2, 23, 0, 0)
  assert.equal(logic.nowIsoAt(nowMs, 7200), "2026-10-03T01:00")
})

test("nowIsoAt: a non-finite nowMs reads '', never throwing", () => {
  assert.equal(logic.nowIsoAt(NaN, 7200), "")
  assert.equal(logic.nowIsoAt(undefined, 7200), "")
})

test("nowIsoAt: a non-finite offset is treated as 0 (UTC)", () => {
  const nowMs = Date.UTC(2026, 9, 2, 20, 0, 0)
  assert.equal(logic.nowIsoAt(nowMs, NaN), "2026-10-02T20:00")
  assert.equal(logic.nowIsoAt(nowMs, undefined), "2026-10-02T20:00")
})

test("nowIsoAt: the result is the LOCATION's wall clock even though the process TZ is Amsterdam", () => {
  // process.env.TZ is pinned to Europe/Amsterdam (UTC+2) at the top of this
  // file. A host-local `new Date(nowMs).toString()`-style read would shift
  // this to the Amsterdam hour; nowIsoAt must give the US Eastern hour
  // (offset -18000) instead, proving it never consults the host's zone.
  assert.equal(process.env.TZ, "Europe/Amsterdam")
  const nowMs = Date.UTC(2026, 9, 2, 18, 0, 0)
  assert.equal(logic.nowIsoAt(nowMs, -18000), "2026-10-02T13:00")
})

// --- parseAir --------------------------------------------------------------------

const AIR_FIXTURE = JSON.stringify({
  latitude: 52.4,
  longitude: 4.9,
  timezone: "Europe/Amsterdam",
  current_units: { european_aqi: "EAQI", uv_index: "" },
  current: { time: "2026-10-02T20:00", european_aqi: 53, uv_index: 5.2 }
})

test("parseAir parses a real-shaped redacted fixture", () => {
  assert.deepEqual(logic.parseAir(AIR_FIXTURE), { aqi: 53, uv: 5.2 })
})

test("parseAir gives null on invalid JSON or a missing current block (the air request failed)", () => {
  assert.equal(logic.parseAir("not json"), null)
  assert.equal(logic.parseAir(undefined), null)
  assert.equal(logic.parseAir("{}"), null)
  assert.equal(logic.parseAir(JSON.stringify({ current: null })), null)
})

test("parseAir reads a non-numeric field as null for that field only", () => {
  assert.deepEqual(
    logic.parseAir(JSON.stringify({ current: { european_aqi: "n/a", uv_index: 5 } })),
    { aqi: null, uv: 5 }
  )
  assert.deepEqual(logic.parseAir(JSON.stringify({ current: {} })), { aqi: null, uv: null })
})

// --- rainSoon --------------------------------------------------------------------

test("rainSoon: the slot containing now already above threshold reads 'Raining now'", () => {
  const minutely = {
    time: ["2026-10-02T20:00", "2026-10-02T20:15", "2026-10-02T20:30"],
    precip: [0.2, 0.0, 0.0]
  }
  assert.equal(logic.rainSoon(minutely, "2026-10-02T20:05"), "Raining now")
})

test("rainSoon: exactly the 0.1mm threshold does not count as rain", () => {
  const minutely = { time: ["2026-10-02T20:00"], precip: [0.1] }
  assert.equal(logic.rainSoon(minutely, "2026-10-02T20:00"), "Dry for the next 3 h")
})

test("rainSoon: the first later slot above threshold gives the rounded minutes, floored at 5", () => {
  const minutely = {
    time: ["2026-10-02T20:00", "2026-10-02T20:15", "2026-10-02T20:30"],
    precip: [0.0, 0.2, 0.2]
  }
  // 20:03 -> 20:15 is 12 minutes away; round(12/5)*5 = 10.
  assert.equal(logic.rainSoon(minutely, "2026-10-02T20:03"), "Rain in ~10 min")
  // 20:13 -> 20:15 is 2 minutes away; round(2/5)*5 = 0, floored to 5.
  assert.equal(logic.rainSoon(minutely, "2026-10-02T20:13"), "Rain in ~5 min")
})

test("rainSoon: nothing above threshold in the window reads 'Dry for the next 3 h'", () => {
  const minutely = {
    time: ["2026-10-02T20:00", "2026-10-02T20:15", "2026-10-02T20:30"],
    precip: [0.0, 0.0, 0.0]
  }
  assert.equal(logic.rainSoon(minutely, "2026-10-02T20:00"), "Dry for the next 3 h")
})

test("rainSoon: now before every slot still finds a later slot above threshold", () => {
  const minutely = { time: ["2026-10-02T20:00", "2026-10-02T20:15"], precip: [0.2, 0.0] }
  assert.equal(logic.rainSoon(minutely, "2026-10-02T19:45"), "Rain in ~15 min")
})

test("rainSoon: missing, empty or malformed minutely data reads '', never throwing", () => {
  assert.equal(logic.rainSoon(null, "2026-10-02T20:00"), "")
  assert.equal(logic.rainSoon(undefined, "2026-10-02T20:00"), "")
  assert.equal(logic.rainSoon({ time: [], precip: [] }, "2026-10-02T20:00"), "")
  assert.equal(logic.rainSoon({ time: ["x"], precip: "nope" }, "2026-10-02T20:00"), "")
})

test("rainSoon: an unparseable nowIso reads '', never throwing", () => {
  const minutely = { time: ["2026-10-02T20:00"], precip: [0.2] }
  assert.equal(logic.rainSoon(minutely, "not a date"), "")
  assert.equal(logic.rainSoon(minutely, undefined), "")
})

// --- compass -----------------------------------------------------------------------

test("compass: each of the 8 points, label from the FROM direction, rotation pointing TO", () => {
  assert.deepEqual(logic.compass(0), { label: "N", rotation: 180 })
  assert.deepEqual(logic.compass(45), { label: "NE", rotation: 225 })
  assert.deepEqual(logic.compass(90), { label: "E", rotation: 270 })
  assert.deepEqual(logic.compass(135), { label: "SE", rotation: 315 })
  assert.deepEqual(logic.compass(180), { label: "S", rotation: 360 })
  assert.deepEqual(logic.compass(225), { label: "SW", rotation: 405 })
  assert.deepEqual(logic.compass(270), { label: "W", rotation: 450 })
  assert.deepEqual(logic.compass(315), { label: "NW", rotation: 495 })
})

test("compass: sector boundaries round to the nearer point and wrap at 360", () => {
  assert.equal(logic.compass(22.5).label, "NE")
  assert.equal(logic.compass(337.5).label, "N")
})

test("compass: a negative or out-of-range degree wraps before labeling", () => {
  assert.deepEqual(logic.compass(-90), { label: "W", rotation: 90 })
})

test("compass: invalid input reads a blank label and a zero rotation, never throwing", () => {
  assert.deepEqual(logic.compass(NaN), { label: "", rotation: 0 })
  assert.deepEqual(logic.compass(undefined), { label: "", rotation: 0 })
})

// --- pressureTrend -----------------------------------------------------------------

test("pressureTrend: a rise above +1hPa over 3h reads up", () => {
  const hourly = {
    time: ["2026-10-02T17:00", "2026-10-02T18:00", "2026-10-02T19:00", "2026-10-02T20:00"],
    pressure: [1028.0, 1028.5, 1029.0, 1029.2]
  }
  assert.equal(logic.pressureTrend(hourly, "2026-10-02T20:00"), "↑")
})

test("pressureTrend: a fall below -1hPa over 3h reads down", () => {
  const hourly = {
    time: ["2026-10-02T17:00", "2026-10-02T18:00", "2026-10-02T19:00", "2026-10-02T20:00"],
    pressure: [1030.0, 1029.5, 1029.0, 1028.0]
  }
  assert.equal(logic.pressureTrend(hourly, "2026-10-02T20:00"), "↓")
})

test("pressureTrend: exactly +-1hPa stays flat", () => {
  const rising = {
    time: ["2026-10-02T17:00", "2026-10-02T20:00"],
    pressure: [1028.0, 1029.0]
  }
  const falling = {
    time: ["2026-10-02T17:00", "2026-10-02T20:00"],
    pressure: [1029.0, 1028.0]
  }
  assert.equal(logic.pressureTrend(rising, "2026-10-02T20:00"), "→")
  assert.equal(logic.pressureTrend(falling, "2026-10-02T20:00"), "→")
})

test("pressureTrend: missing hourly data, no 3h-prior slot, or an unparseable now reads '', never throwing", () => {
  assert.equal(logic.pressureTrend(null, "2026-10-02T20:00"), "")
  assert.equal(logic.pressureTrend({ time: [], pressure: [] }, "2026-10-02T20:00"), "")
  const tooShort = { time: ["2026-10-02T19:00", "2026-10-02T20:00"], pressure: [1029.0, 1029.2] }
  assert.equal(logic.pressureTrend(tooShort, "2026-10-02T20:00"), "")
  const hourly = { time: ["2026-10-02T20:00"], pressure: [1029.0] }
  assert.equal(logic.pressureTrend(hourly, "not a date"), "")
})

// --- aqiBand (European AQI bands) ---------------------------------------------------

test("aqiBand: every boundary, Good/Fair tinted good, Moderate plain, Poor and worse bad", () => {
  assert.deepEqual(logic.aqiBand(19.9), { label: "Good", tone: "good" })
  assert.deepEqual(logic.aqiBand(20), { label: "Fair", tone: "good" })
  assert.deepEqual(logic.aqiBand(39.9), { label: "Fair", tone: "good" })
  assert.deepEqual(logic.aqiBand(40), { label: "Moderate", tone: "plain" })
  assert.deepEqual(logic.aqiBand(59.9), { label: "Moderate", tone: "plain" })
  assert.deepEqual(logic.aqiBand(60), { label: "Poor", tone: "bad" })
  assert.deepEqual(logic.aqiBand(79.9), { label: "Poor", tone: "bad" })
  assert.deepEqual(logic.aqiBand(80), { label: "Very poor", tone: "bad" })
  assert.deepEqual(logic.aqiBand(100), { label: "Very poor", tone: "bad" })
  assert.deepEqual(logic.aqiBand(100.1), { label: "Extremely poor", tone: "bad" })
})

test("aqiBand: a missing or non-finite value gives null (hides the chip)", () => {
  assert.equal(logic.aqiBand(NaN), null)
  assert.equal(logic.aqiBand(undefined), null)
  assert.equal(logic.aqiBand(null), null)
})

// --- uvBand (WHO UV index bands) -----------------------------------------------------

test("uvBand: every boundary", () => {
  assert.deepEqual(logic.uvBand(2.9), { label: "Low" })
  assert.deepEqual(logic.uvBand(3), { label: "Moderate" })
  assert.deepEqual(logic.uvBand(5.9), { label: "Moderate" })
  assert.deepEqual(logic.uvBand(6), { label: "High" })
  assert.deepEqual(logic.uvBand(7.9), { label: "High" })
  assert.deepEqual(logic.uvBand(8), { label: "Very high" })
  assert.deepEqual(logic.uvBand(10.9), { label: "Very high" })
  assert.deepEqual(logic.uvBand(11), { label: "Extreme" })
})

test("uvBand: a missing or non-finite value gives null (hides the chip)", () => {
  assert.equal(logic.uvBand(NaN), null)
  assert.equal(logic.uvBand(undefined), null)
})

// --- hourlyPoints --------------------------------------------------------------------

test("hourlyPoints: normalises temperature 0..1 against the window's own min/max, and rain 0..1 from percent", () => {
  const hourly = {
    time: ["2026-10-02T19:00", "2026-10-02T20:00", "2026-10-02T21:00", "2026-10-02T22:00"],
    temp: [15.0, 17.0, 16.0, 19.0],
    rain: [0, 50, 100, 10]
  }
  const r = logic.hourlyPoints(hourly, "2026-10-02T20:00", 3)
  assert.equal(r.min, 16.0)
  assert.equal(r.max, 19.0)
  assert.equal(r.now, 17.0)
  assert.deepEqual(r.temp, [
    { x: 0, y: (17.0 - 16.0) / (19.0 - 16.0) },
    { x: 0.5, y: (16.0 - 16.0) / (19.0 - 16.0) },
    { x: 1, y: (19.0 - 16.0) / (19.0 - 16.0) }
  ])
  assert.deepEqual(r.rain, [
    { x: 0, h: 0.5 },
    { x: 0.5, h: 1 },
    { x: 1, h: 0.1 }
  ])
})

test("hourlyPoints: a flat window (equal min and max) reads the midline rather than dividing by zero", () => {
  const hourly = {
    time: ["2026-10-02T20:00", "2026-10-02T21:00"],
    temp: [16.0, 16.0],
    rain: [0, 0]
  }
  const r = logic.hourlyPoints(hourly, "2026-10-02T20:00", 2)
  assert.deepEqual(r.temp, [
    { x: 0, y: 0.5 },
    { x: 1, y: 0.5 }
  ])
})

test("hourlyPoints: asking for more slots than available clips to what's there", () => {
  const hourly = {
    time: ["2026-10-02T20:00", "2026-10-02T21:00"],
    temp: [16.0, 17.0],
    rain: [0, 0]
  }
  const r = logic.hourlyPoints(hourly, "2026-10-02T20:00", 24)
  assert.equal(r.temp.length, 2)
  assert.equal(r.now, 16.0)
})

test("hourlyPoints: a zero, negative or non-numeric slots count falls back to 1 slot", () => {
  const hourly = {
    time: ["2026-10-02T20:00", "2026-10-02T21:00"],
    temp: [16.0, 17.0],
    rain: [0, 0]
  }
  for (const bogus of [0, -5, NaN, "nope"]) {
    const r = logic.hourlyPoints(hourly, "2026-10-02T20:00", bogus)
    assert.equal(r.temp.length, 1, `slots=${bogus}`)
    assert.equal(r.now, 16.0, `slots=${bogus}`)
  }
})

test("hourlyPoints: missing hourly data, no slot at or before now, or an unparseable now gives the empty shape", () => {
  const empty = { temp: [], rain: [], min: null, max: null, now: null }
  assert.deepEqual(logic.hourlyPoints(null, "2026-10-02T20:00", 6), empty)
  assert.deepEqual(logic.hourlyPoints({ time: [], temp: [] }, "2026-10-02T20:00", 6), empty)
  const hourly = { time: ["2026-10-02T20:00"], temp: [16.0], rain: [0] }
  assert.deepEqual(logic.hourlyPoints(hourly, "2026-10-02T19:00", 6), empty)
  assert.deepEqual(logic.hourlyPoints(hourly, "not a date", 6), empty)
})

// --- unit conversions and formatting -------------------------------------------------

test("kmhToMph / kmToMi / hpaToInHg convert, and read NaN for invalid input", () => {
  assert.ok(Math.abs(logic.kmhToMph(100) - 62.1371) < 1e-6)
  assert.ok(Math.abs(logic.kmToMi(10) - 6.21371) < 1e-6)
  assert.ok(Math.abs(logic.hpaToInHg(1013.25) - 29.9212) < 1e-3)
  assert.ok(Number.isNaN(logic.kmhToMph(NaN)))
  assert.ok(Number.isNaN(logic.kmToMi(undefined)))
  assert.ok(Number.isNaN(logic.hpaToInHg("x")))
})

test("formatWind: metric km/h, imperial mph, invalid input ''", () => {
  assert.equal(logic.formatWind(14.9, false), "15 km/h")
  assert.equal(logic.formatWind(15.8, true), "10 mph")
  assert.equal(logic.formatWind(NaN, false), "")
})

test("formatPressure: metric whole hPa, imperial 2-decimal inHg, invalid input ''", () => {
  assert.equal(logic.formatPressure(1030.2, false), "1030 hPa")
  assert.equal(logic.formatPressure(1030.2, true), "30.42 inHg")
  assert.equal(logic.formatPressure(undefined, false), "")
})

test("formatVisibility: metres to km, or mi when imperial, invalid input ''", () => {
  assert.equal(logic.formatVisibility(19920, false), "20 km")
  assert.equal(logic.formatVisibility(19920, true), "12 mi")
  assert.equal(logic.formatVisibility(NaN, true), "")
})

// --- sharedReport (C2-style: one fetch per refresh across monitors) -----------------

test("sharedReport: the freshest peer report younger than the interval wins", () => {
  const peers = [
    { fetchedAt: 1000, report: { a: 1 } },
    { fetchedAt: 4000, report: { a: 2 } }
  ]
  assert.deepEqual(logic.sharedReport(peers, 5000, 15), { a: 2 })
})

test("sharedReport: a peer at least refreshMinutes old is ignored", () => {
  const peers = [{ fetchedAt: 0, report: { a: 1 } }]
  // 15 minutes = 900000ms; exactly that old no longer counts as fresh.
  assert.equal(logic.sharedReport(peers, 900000, 15), null)
  assert.deepEqual(logic.sharedReport(peers, 899999, 15), { a: 1 })
})

test("sharedReport: a peer with no report or a non-finite fetchedAt is ignored", () => {
  const peers = [{ fetchedAt: 1000, report: null }, { fetchedAt: NaN, report: { a: 1 } }, null]
  assert.equal(logic.sharedReport(peers, 1500, 15), null)
})

test("sharedReport: no peers, or an invalid list, gives null (go fetch)", () => {
  assert.equal(logic.sharedReport([], 1000, 15), null)
  assert.equal(logic.sharedReport(undefined, 1000, 15), null)
})

// --- wttrCoords (the auto-location coordinates for the open-meteo requests) ---------

const WTTR_AREA_FIXTURE = JSON.stringify({
  nearest_area: [
    {
      areaName: [{ value: "Testville" }],
      country: [{ value: "Testland" }],
      latitude: "52.000",
      longitude: "5.000"
    }
  ]
})

test("wttrCoords parses a real-shaped redacted fixture's nearest_area coordinates", () => {
  assert.deepEqual(logic.wttrCoords(WTTR_AREA_FIXTURE), { lat: 52, lon: 5 })
})

test("wttrCoords gives null on invalid JSON, a missing/empty nearest_area, or bad coordinates", () => {
  assert.equal(logic.wttrCoords("not json"), null)
  assert.equal(logic.wttrCoords(undefined), null)
  assert.equal(logic.wttrCoords("{}"), null)
  assert.equal(logic.wttrCoords(JSON.stringify({ nearest_area: [] })), null)
  assert.equal(
    logic.wttrCoords(JSON.stringify({ nearest_area: [{ latitude: "x", longitude: "5" }] })),
    null
  )
})

// --- Panel's view pieces (Task 4) ----------------------------------------------------

const HOURLY = {
  time: [
    "2026-10-02T17:00",
    "2026-10-02T18:00",
    "2026-10-02T19:00",
    "2026-10-02T20:00",
    "2026-10-02T21:00",
    "2026-10-02T22:00",
    "2026-10-02T23:00",
    "2026-10-03T00:00",
    "2026-10-03T01:00"
  ],
  temp: [15, 16, 17, 17, 16, 15, 14, 13, 12],
  rain: [0, 0, 0, 10, 20, 0, 0, 0, 0],
  pressure: [1010, 1010, 1011, 1012, 1012, 1012, 1013, 1013, 1013]
}

test("hourLabels: 'now' then spread two-digit hours over the hourlyPoints window", () => {
  assert.deepEqual(logic.hourLabels(HOURLY, "2026-10-02T20:15", 24, 3), ["now", "23", "01"])
  assert.deepEqual(logic.hourLabels(HOURLY, "2026-10-02T20:15", 5, 5), [
    "now",
    "21",
    "22",
    "23",
    "00"
  ])
})

test("hourLabels: no window gives [], a single slot only 'now', a bad time an empty label", () => {
  assert.deepEqual(logic.hourLabels(null, "2026-10-02T20:15", 24, 5), [])
  assert.deepEqual(logic.hourLabels({ time: [] }, "2026-10-02T20:15", 24, 5), [])
  assert.deepEqual(logic.hourLabels(HOURLY, "nope", 24, 5), [])
  assert.deepEqual(logic.hourLabels(HOURLY, "2026-10-01T00:00", 24, 5), [])
  assert.deepEqual(logic.hourLabels(HOURLY, "2026-10-03T01:30", 24, 5), ["now"])
  assert.deepEqual(logic.hourLabels(HOURLY, "2026-10-02T20:15", "x", 5), ["now"])
  assert.deepEqual(
    logic.hourLabels({ time: ["2026-10-02T20:00", "bad"] }, "2026-10-02T20:15", 2, "y"),
    ["now", ""]
  )
})

test("bareDegrees and hourlyCaption: rounded degrees, Fahrenheit when imperial", () => {
  assert.equal(logic.bareDegrees(16.6, false), "17°")
  assert.equal(logic.bareDegrees("20", true), "68°")
  assert.equal(logic.bareDegrees("", false), "")
  assert.equal(logic.bareDegrees(null, false), "")
  assert.equal(logic.hourlyCaption({ now: 17, min: 11, max: 19 }, false), "17° → 11° → 19°")
  assert.equal(logic.hourlyCaption({ now: 0, min: -5, max: 5 }, true), "32° → 23° → 41°")
  assert.equal(logic.hourlyCaption({ now: null, min: 1, max: 2 }, false), "")
  assert.equal(logic.hourlyCaption(null, false), "")
})

test("conditionLabel: WMO code from open-meteo, else wttr's weatherDesc", () => {
  assert.equal(logic.conditionLabel({ openMeteoWeatherCode: 2 }), "Partly cloudy")
  assert.equal(logic.conditionLabel({ openMeteoWeatherCode: "63" }), "Rain")
  assert.equal(logic.conditionLabel({ openMeteoWeatherCode: 42 }), "")
  assert.equal(logic.conditionLabel({ weatherDesc: [{ value: " Light rain " }] }), "Light rain")
  assert.equal(logic.conditionLabel({ weatherDesc: [] }), "")
  assert.equal(logic.conditionLabel({ weatherDesc: [{ value: 3 }] }), "")
  assert.equal(logic.conditionLabel(null), "")
})

const DAILY = {
  daily: {
    time: ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05"],
    weather_code: [0, 2, 3, 61, 0],
    temperature_2m_max: [18.2, 19.4, 16, 18, 15],
    temperature_2m_min: [10, 11.2, 10, 9, 8]
  }
}

test("forecastFromToday: open-meteo days from today on, in Model.js's shape", () => {
  const days = logic.forecastFromToday(null, DAILY, "2026-10-02", 4)
  assert.deepEqual(
    days.map((d) => d.date),
    ["2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05"]
  )
  assert.deepEqual(days[0], {
    date: "2026-10-02",
    maxtempC: "19",
    mintempC: "11",
    maxtempF: "67",
    mintempF: "52",
    openMeteoWeatherCode: 2
  })
  assert.equal(logic.forecastFromToday(null, DAILY, "2026-10-02", 2).length, 2)
  const bare = logic.forecastFromToday(null, { daily: { time: ["2026-10-02"] } }, "2026-10-02", "x")
  assert.deepEqual(bare, [
    {
      date: "2026-10-02",
      maxtempC: "",
      mintempC: "",
      maxtempF: "",
      mintempF: "",
      openMeteoWeatherCode: null
    }
  ])
})

test("forecastFromToday: falls back to wttr's days from today when open-meteo has none", () => {
  const report = {
    weather: [{ date: "2026-10-01" }, { date: "2026-10-02" }, null, { date: "2026-10-03" }]
  }
  assert.deepEqual(logic.forecastFromToday(report, null, "2026-10-02", 4), [
    { date: "2026-10-02" },
    { date: "2026-10-03" }
  ])
  assert.deepEqual(logic.forecastFromToday(report, DAILY, "2026-11-01", 4), [])
  assert.deepEqual(logic.forecastFromToday(null, null, undefined, 4), [])
})

const PLACES = [
  {
    name: "Amsterdam",
    description: "Noord-Holland, Netherlands",
    latitude: 52.37,
    longitude: 4.89
  },
  { name: "Amstelveen", latitude: 52.3, longitude: 4.86 }
]

test("suggestionKey and suggestionRows: keyed by name and coordinates", () => {
  assert.equal(logic.suggestionKey(PLACES[0]), "Amsterdam|52.37|4.89")
  assert.equal(logic.suggestionKey(null), "")
  assert.deepEqual(logic.suggestionRows(PLACES), [
    { key: "Amsterdam|52.37|4.89", name: "Amsterdam", description: "Noord-Holland, Netherlands" },
    { key: "Amstelveen|52.3|4.86", name: "Amstelveen", description: "" }
  ])
  assert.deepEqual(logic.suggestionRows([null]), [{ key: "", name: "", description: "" }])
  assert.deepEqual(logic.suggestionRows(undefined), [])
})

test("suggestionAt: only the current row carrying the key; refused otherwise", () => {
  assert.equal(logic.suggestionAt(PLACES, 1, "Amstelveen|52.3|4.86"), PLACES[1])
  assert.equal(logic.suggestionAt(PLACES, 0, "Amstelveen|52.3|4.86"), null)
  assert.equal(logic.suggestionAt(PLACES, 2, "Amsterdam|52.37|4.89"), null)
  assert.equal(logic.suggestionAt(PLACES, -1, "Amsterdam|52.37|4.89"), null)
  assert.equal(logic.suggestionAt(PLACES, "0", "Amsterdam|52.37|4.89"), null)
  assert.equal(logic.suggestionAt(PLACES, 0, ""), null)
  assert.equal(logic.suggestionAt(null, 0, "Amsterdam|52.37|4.89"), null)
})

test("airView: toned AQI and UV chips, each hidden without its value", () => {
  assert.deepEqual(logic.airView({ aqi: 53.4, uv: 0.2 }), {
    aqi: { visible: true, text: "AQI 53 · Moderate", tone: "plain" },
    uv: { visible: true, text: "UV 0 · Low" }
  })
  assert.deepEqual(logic.airView({ aqi: 25, uv: null }), {
    aqi: { visible: true, text: "AQI 25 · Fair", tone: "good" },
    uv: { visible: false, text: "" }
  })
  assert.deepEqual(logic.airView(null), {
    aqi: { visible: false, text: "", tone: "plain" },
    uv: { visible: false, text: "" }
  })
})

test("detailCells: the six cells in order, wind arrow and pressure trend, empties dropped", () => {
  const cells = logic.detailCells({
    feels: "16°",
    humid: "71%",
    wind: "7 km/h",
    windDeg: 225,
    gustsKmh: 19,
    pressureHpa: 1030,
    trend: "↑",
    visibilityM: 20000,
    imperial: false
  })
  assert.deepEqual(cells, [
    { key: "feels", label: "Feels", value: "16°" },
    { key: "humid", label: "Humid", value: "71%" },
    { key: "wind", label: "Wind", value: "7 km/h", arrow: 405, dir: "SW" },
    { key: "gusts", label: "Gusts", value: "19 km/h" },
    { key: "pressure", label: "Pressure", value: "1030 hPa", trend: "↑" },
    { key: "visibility", label: "Visibility", value: "20 km" }
  ])
  const imperial = logic.detailCells({
    wind: "4 mph",
    windDeg: null,
    gustsKmh: 16.1,
    pressureHpa: 1013.25,
    visibilityM: 16093,
    imperial: true
  })
  assert.deepEqual(imperial, [
    { key: "wind", label: "Wind", value: "4 mph" },
    { key: "gusts", label: "Gusts", value: "10 mph" },
    { key: "pressure", label: "Pressure", value: "29.92 inHg" },
    { key: "visibility", label: "Visibility", value: "10 mi" }
  ])
  assert.deepEqual(logic.detailCells(undefined), [])
  assert.deepEqual(logic.detailCells({ wind: "", windDeg: 90 }), [])
})

test("sharedBundle: the freshest peer bundle for the same location query", () => {
  const a = { locationQuery: "52.37,4.89", fetchedAtMs: 1000 }
  const b = { locationQuery: "52.37,4.89", fetchedAtMs: 2000 }
  const other = { locationQuery: "", fetchedAtMs: 3000 }
  assert.equal(logic.sharedBundle([a, b, other, null, 7], "52.37,4.89", 3000, 15), b)
  assert.equal(logic.sharedBundle([other], "52.37,4.89", 3000, 15), null)
  assert.equal(logic.sharedBundle([a], "52.37,4.89", 1000 + 15 * 60000, 15), null)
  assert.equal(logic.sharedBundle(undefined, "", 0, 15), null)
})

test("refreshPlan: defer until ready, skip while fetching, adopt fresh, wait on a peer, else fetch", () => {
  const plan = (ready, selfFetching, fresh, peerFetching) =>
    logic.refreshPlan({ ready, selfFetching, fresh, peerFetching })
  assert.equal(plan(false, true, true, true), "defer")
  assert.equal(plan(true, true, true, true), "skip")
  assert.equal(plan(true, false, true, true), "adopt")
  assert.equal(plan(true, false, false, true), "wait")
  assert.equal(plan(true, false, false, false), "fetch")
  assert.equal(logic.refreshPlan(undefined), "fetch")
})
