// Logic contract for ClockLogic.js: NOAA sunrise/sunset, clock and daylight
// formatting, the sun-arc position, the synodic moon phase and its Nerd Font
// glyph, wttr.in/weather-location parsing, the place caption and the
// once-a-day fetch gate. No QML, no I/O, no Date.now(); run with
// `node --test tests/js/` (tools/check runs it with coverage).
//
// TZ is pinned before any require so Node's local-time helpers (none of
// which this module uses, since every date is passed explicitly) can never
// make a test depend on the host's zone.
process.env.TZ = "Europe/Amsterdam"

const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.clock/ClockLogic.js"))

// --- sunTimes (NOAA algorithm) ------------------------------------------------------
//
// Reference values for Amsterdam (52.37 N, 4.90 E), published by
// timeanddate.com's Amsterdam sunrise/sunset tables:
//   2026-06-21 (CEST, UTC+120): sunrise 05:19 (319 min), sunset 22:05 (1325 min)
//   2026-12-21 (CET, UTC+60):   sunrise 08:48 (528 min), sunset 16:28 (988 min)
// The NOAA algorithm is accurate to well under a minute for mid-latitudes, so
// these are checked within +/-2 minutes as the brief allows.

test("sunTimes: Amsterdam summer solstice matches the published sunrise/sunset within 2 minutes", () => {
  const r = logic.sunTimes(52.37, 4.9, 2026, 6, 21, 120)
  assert.ok(r, "a normal day returns a result")
  assert.equal(r.polar, "")
  assert.ok(Math.abs(r.sunrise - 319) <= 2, `sunrise ${r.sunrise} within 2 min of 319`)
  assert.ok(Math.abs(r.sunset - 1325) <= 2, `sunset ${r.sunset} within 2 min of 1325`)
})

test("sunTimes: Amsterdam winter solstice matches the published sunrise/sunset within 2 minutes", () => {
  const r = logic.sunTimes(52.37, 4.9, 2026, 12, 21, 60)
  assert.ok(r)
  assert.equal(r.polar, "")
  assert.ok(Math.abs(r.sunrise - 528) <= 2, `sunrise ${r.sunrise} within 2 min of 528`)
  assert.ok(Math.abs(r.sunset - 988) <= 2, `sunset ${r.sunset} within 2 min of 988`)
})

test("sunTimes: polar night at 78.2 N in December, no sunrise or sunset", () => {
  const r = logic.sunTimes(78.2, 15.6, 2026, 12, 21, 0)
  assert.deepEqual(r, { sunrise: null, sunset: null, polar: "night" })
})

test("sunTimes: polar day at 78.2 N in June, no sunrise or sunset", () => {
  const r = logic.sunTimes(78.2, 15.6, 2026, 6, 21, 0)
  assert.deepEqual(r, { sunrise: null, sunset: null, polar: "day" })
})

test("sunTimes: invalid latitude or longitude gives null, never throwing", () => {
  assert.equal(logic.sunTimes(999, 4.9, 2026, 6, 21, 0), null)
  assert.equal(logic.sunTimes(-999, 4.9, 2026, 6, 21, 0), null)
  assert.equal(logic.sunTimes(52.37, 999, 2026, 6, 21, 0), null)
  assert.equal(logic.sunTimes(NaN, 4.9, 2026, 6, 21, 0), null)
  assert.equal(logic.sunTimes(52.37, NaN, 2026, 6, 21, 0), null)
  assert.equal(logic.sunTimes(undefined, undefined, 2026, 6, 21, 0), null)
})

test("sunTimes: invalid date or timezone gives null, never throwing", () => {
  assert.equal(logic.sunTimes(52.37, 4.9, NaN, 6, 21, 0), null)
  assert.equal(logic.sunTimes(52.37, 4.9, 2026, NaN, 21, 0), null)
  assert.equal(logic.sunTimes(52.37, 4.9, 2026, 6, NaN, 0), null)
  assert.equal(logic.sunTimes(52.37, 4.9, 2026, 6, 21, NaN), null)
  assert.equal(logic.sunTimes(52.37, 4.9, 2026, 6, 21, undefined), null)
})

test("sunTimes: the equator has roughly equal day and night year-round", () => {
  // The standard sunrise/sunset zenith angle (90.833 deg) bakes in
  // atmospheric refraction and the solar disc's radius, so even at the
  // equinox daylight runs a bit over 12h (published equatorial equinox
  // daylight is commonly ~12h06m, not exactly 12h00m).
  const r = logic.sunTimes(0, 0, 2026, 3, 20, 0)
  assert.ok(r)
  assert.equal(r.polar, "")
  assert.ok(Math.abs(r.sunset - r.sunrise - 727) <= 5, "about 12 hours of daylight")
})

// --- formatClock -----------------------------------------------------------------

test("formatClock renders minutes-after-midnight as HH:MM", () => {
  assert.equal(logic.formatClock(463), "07:43")
  assert.equal(logic.formatClock(0), "00:00")
  assert.equal(logic.formatClock(1439), "23:59")
})

test("formatClock rounds a fractional minute", () => {
  assert.equal(logic.formatClock(90.6), "01:31")
})

test("formatClock wraps minutes outside a single day, with no throw", () => {
  assert.equal(logic.formatClock(1440), "00:00")
  assert.equal(logic.formatClock(-5), "23:55")
})

test("formatClock on invalid input never throws, reading 00:00", () => {
  assert.equal(logic.formatClock(NaN), "00:00")
  assert.equal(logic.formatClock(undefined), "00:00")
  assert.equal(logic.formatClock(null), "00:00")
})

// --- daylightText ------------------------------------------------------------------

test("daylightText renders the span as 'H h MM'", () => {
  assert.equal(logic.daylightText(0, 692), "11 h 32")
})

test("daylightText pads single-digit minutes", () => {
  assert.equal(logic.daylightText(300, 905), "10 h 05")
})

test("daylightText wraps when the sunset minute is before the sunrise minute", () => {
  assert.equal(logic.daylightText(1430, 10), "0 h 20")
})

test("daylightText on invalid input never throws, reading ''", () => {
  assert.equal(logic.daylightText(NaN, 500), "")
  assert.equal(logic.daylightText(300, NaN), "")
  assert.equal(logic.daylightText(undefined, undefined), "")
  assert.equal(logic.daylightText(null, null), "")
})

// --- sunArcPosition ----------------------------------------------------------------

test("sunArcPosition: midday sits halfway along the day arc", () => {
  assert.deepEqual(logic.sunArcPosition(720, 360, 1080), { t: 0.5, night: false })
})

test("sunArcPosition: exactly at sunrise or sunset is the day arc's ends", () => {
  assert.deepEqual(logic.sunArcPosition(360, 360, 1080), { t: 0, night: false })
  assert.deepEqual(logic.sunArcPosition(1080, 360, 1080), { t: 1, night: false })
})

test("sunArcPosition: before sunrise is on the night arc", () => {
  const r = logic.sunArcPosition(100, 360, 1080)
  assert.equal(r.night, true)
  assert.ok(Math.abs(r.t - 460 / 720) < 1e-9)
})

test("sunArcPosition: after sunset is on the night arc", () => {
  const r = logic.sunArcPosition(1200, 360, 1080)
  assert.equal(r.night, true)
  assert.ok(Math.abs(r.t - 120 / 720) < 1e-9)
})

test("sunArcPosition: now wraps into a single day before comparing", () => {
  assert.deepEqual(logic.sunArcPosition(720 + 1440, 360, 1080), { t: 0.5, night: false })
  assert.deepEqual(logic.sunArcPosition(-720, 360, 1080), { t: 0.5, night: false })
})

test("sunArcPosition: no sun data (polar night/day) reads night at the start, never throwing", () => {
  assert.deepEqual(logic.sunArcPosition(720, null, null), { t: 0, night: true })
  assert.deepEqual(logic.sunArcPosition(720, undefined, undefined), { t: 0, night: true })
  assert.deepEqual(logic.sunArcPosition(720, 1080, 360), { t: 0, night: true })
})

// --- moonPhase (NOAA-independent synodic approximation) -----------------------------
//
// Reference new moon 2000-01-06 18:14 UTC, synodic month 29.530588853 days.
// At the reference instant itself the age is exactly zero, so this is an
// exact, floating-point-safe check (no tolerance needed): illumination
// round((1 - cos(0)) / 2 * 100) = 0.

const REF_NEW_MOON = Date.UTC(2000, 0, 6, 18, 14, 0)
const DAY_MS = 86400000

test("moonPhase: the reference instant itself is an exact new moon", () => {
  assert.deepEqual(logic.moonPhase(REF_NEW_MOON), {
    index: 0,
    name: "New moon",
    illumination: 0
  })
})

test("moonPhase: known full/new/quarter dates, a fixed number of days from the reference (clear of bucket edges)", () => {
  // 1 day after the reference: still a thin new crescent.
  assert.deepEqual(logic.moonPhase(REF_NEW_MOON + 1 * DAY_MS), {
    index: 0,
    name: "New moon",
    illumination: 1
  })
  // 8 days after: first quarter.
  assert.deepEqual(logic.moonPhase(REF_NEW_MOON + 8 * DAY_MS), {
    index: 2,
    name: "First quarter",
    illumination: 57
  })
  // 16 days after: full moon.
  assert.deepEqual(logic.moonPhase(REF_NEW_MOON + 16 * DAY_MS), {
    index: 4,
    name: "Full moon",
    illumination: 98
  })
  // 23 days after: last quarter.
  assert.deepEqual(logic.moonPhase(REF_NEW_MOON + 23 * DAY_MS), {
    index: 6,
    name: "Last quarter",
    illumination: 41
  })
  // 1 day before the reference: a thin waning crescent (wraps to the end of
  // the previous cycle without going negative).
  assert.deepEqual(logic.moonPhase(REF_NEW_MOON - 1 * DAY_MS), {
    index: 7,
    name: "Waning crescent",
    illumination: 1
  })
})

test("moonPhase: today (2026-10-02) matches wttr's Waning Gibbous ~68% within +/-6 points", () => {
  const r = logic.moonPhase(Date.UTC(2026, 9, 2, 12, 0, 0))
  assert.equal(r.name, "Waning gibbous")
  assert.equal(r.index, 5)
  assert.ok(Math.abs(r.illumination - 68) <= 6, `illumination ${r.illumination} within 6 of 68`)
})

test("moonPhase on invalid input never throws, falling back to the Unix epoch", () => {
  assert.doesNotThrow(() => logic.moonPhase(NaN))
  assert.doesNotThrow(() => logic.moonPhase(undefined))
  const r = logic.moonPhase(NaN)
  assert.ok(r.index >= 0 && r.index <= 7)
  assert.ok(r.illumination >= 0 && r.illumination <= 100)
})

// --- moonGlyph (Nerd Font Material Design Icons moon-phase glyphs) ------------------
//
// Codepoints from the Material Design Icons set (also the Nerd Fonts v3
// codepoints, which were realigned to MDI's own): moon-first-quarter
// F0F61, moon-full F0F62, moon-last-quarter F0F63, moon-new F0F64,
// moon-waning-crescent F0F65, moon-waning-gibbous F0F66,
// moon-waxing-crescent F0F67, moon-waxing-gibbous F0F68.

const GLYPH_BY_INDEX = [
  0xf0f64, // 0 New moon
  0xf0f67, // 1 Waxing crescent
  0xf0f61, // 2 First quarter
  0xf0f68, // 3 Waxing gibbous
  0xf0f62, // 4 Full moon
  0xf0f66, // 5 Waning gibbous
  0xf0f63, // 6 Last quarter
  0xf0f65 // 7 Waning crescent
]

test("moonGlyph: each of the 8 phases has its own glyph", () => {
  for (let i = 0; i < 8; i++) {
    assert.equal(logic.moonGlyph(i), String.fromCodePoint(GLYPH_BY_INDEX[i]), `index ${i}`)
  }
})

test("moonGlyph: an out-of-range index wraps rather than throwing", () => {
  assert.equal(logic.moonGlyph(8), String.fromCodePoint(GLYPH_BY_INDEX[0]))
  assert.equal(logic.moonGlyph(-1), String.fromCodePoint(GLYPH_BY_INDEX[7]))
})

test("moonGlyph on invalid input never throws, falling back to index 0", () => {
  assert.equal(logic.moonGlyph(NaN), String.fromCodePoint(GLYPH_BY_INDEX[0]))
  assert.equal(logic.moonGlyph(undefined), String.fromCodePoint(GLYPH_BY_INDEX[0]))
})

// --- parseWttrArea (wttr.in's nearest_area[0]) --------------------------------------
//
// A real-shaped, redacted fixture: wttr.in's nearest_area carries the
// resolved place name and coordinates as strings. Area name and country are
// stand-ins ("Testville"); coordinates are rounded to a non-identifying
// 52.0, 5.0 (never the real captured values).

const WTTR_FIXTURE = JSON.stringify({
  nearest_area: [
    {
      areaName: [{ value: "Testville" }],
      country: [{ value: "Testland" }],
      region: [{ value: "" }],
      latitude: "52.000",
      longitude: "5.000",
      population: "100000"
    }
  ],
  current_condition: [{ temp_C: "15" }]
})

test("parseWttrArea parses a real-shaped redacted wttr.in fixture", () => {
  assert.deepEqual(logic.parseWttrArea(WTTR_FIXTURE), { name: "Testville", lat: 52, lon: 5 })
})

test("parseWttrArea gives null on invalid JSON, never throwing", () => {
  assert.equal(logic.parseWttrArea("not json"), null)
  assert.equal(logic.parseWttrArea(undefined), null)
  assert.equal(logic.parseWttrArea(""), null)
})

test("parseWttrArea gives null when nearest_area is missing or empty", () => {
  assert.equal(logic.parseWttrArea("{}"), null)
  assert.equal(logic.parseWttrArea(JSON.stringify({ nearest_area: [] })), null)
  assert.equal(logic.parseWttrArea(JSON.stringify({ nearest_area: "nope" })), null)
})

test("parseWttrArea gives null when the area name or coordinates don't parse", () => {
  assert.equal(
    logic.parseWttrArea(
      JSON.stringify({ nearest_area: [{ areaName: [], latitude: "52", longitude: "5" }] })
    ),
    null
  )
  assert.equal(
    logic.parseWttrArea(
      JSON.stringify({
        nearest_area: [{ areaName: [{ value: "Testville" }], latitude: "x", longitude: "5" }]
      })
    ),
    null
  )
})

// --- parseWeatherLocation (weather.loc, mirroring stock's parseLocationFile) --------

test("parseWeatherLocation parses a name with coordinates", () => {
  assert.deepEqual(
    logic.parseWeatherLocation(JSON.stringify({ name: "Testville", latitude: 52, longitude: 5 })),
    { name: "Testville", lat: 52, lon: 5 }
  )
})

test("parseWeatherLocation trims the name", () => {
  assert.deepEqual(
    logic.parseWeatherLocation(
      JSON.stringify({ name: "  Testville  ", latitude: 52, longitude: 5 })
    ),
    { name: "Testville", lat: 52, lon: 5 }
  )
})

test("parseWeatherLocation accepts a name-only entry (hand-edited weather.loc)", () => {
  assert.deepEqual(logic.parseWeatherLocation(JSON.stringify({ name: "Somewhere" })), {
    name: "Somewhere",
    lat: null,
    lon: null
  })
})

test("parseWeatherLocation accepts coordinates with no name", () => {
  assert.deepEqual(logic.parseWeatherLocation(JSON.stringify({ latitude: 52, longitude: 5 })), {
    name: "",
    lat: 52,
    lon: 5
  })
})

test("parseWeatherLocation gives null with nothing configured (auto-detect by IP)", () => {
  assert.equal(logic.parseWeatherLocation("{}"), null)
  assert.equal(logic.parseWeatherLocation(JSON.stringify({ name: "" })), null)
})

test("parseWeatherLocation gives null on invalid/missing input, never throwing", () => {
  assert.equal(logic.parseWeatherLocation("not json"), null)
  assert.equal(logic.parseWeatherLocation(undefined), null)
  assert.equal(logic.parseWeatherLocation(""), null)
})

// --- placeCaption --------------------------------------------------------------------

test("placeCaption prefers the configured location's name", () => {
  assert.equal(logic.placeCaption({ name: "My Place" }, { name: "Testville" }), "My Place")
})

test("placeCaption falls back to the resolved wttr area name", () => {
  assert.equal(logic.placeCaption(null, { name: "Testville" }), "Testville")
})

test("placeCaption falls back to 'Here' with nothing resolved", () => {
  assert.equal(logic.placeCaption(null, null), "Here")
  assert.equal(logic.placeCaption(undefined, undefined), "Here")
})

test("placeCaption treats a blank configured name as unset", () => {
  assert.equal(logic.placeCaption({ name: "   " }, { name: "Testville" }), "Testville")
  assert.equal(logic.placeCaption({ name: "" }, null), "Here")
})

// --- shouldFetchArea (wttr.in runs at most once a day, only on open, only unconfigured) --

test("shouldFetchArea: never while closed", () => {
  assert.equal(logic.shouldFetchArea(null, "", "2026-10-02", false), false)
})

test("shouldFetchArea: never when a location is already configured", () => {
  assert.equal(logic.shouldFetchArea({ name: "My Place" }, "", "2026-10-02", true), false)
})

test("shouldFetchArea: fetches on open, unconfigured, not yet fetched today", () => {
  assert.equal(logic.shouldFetchArea(null, "", "2026-10-02", true), true)
  assert.equal(logic.shouldFetchArea(null, "2026-10-01", "2026-10-02", true), true)
  assert.equal(logic.shouldFetchArea(null, undefined, "2026-10-02", true), true)
})

test("shouldFetchArea: no retry once already fetched today", () => {
  assert.equal(logic.shouldFetchArea(null, "2026-10-02", "2026-10-02", true), false)
})
