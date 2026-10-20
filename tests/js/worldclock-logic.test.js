// Logic contract for WorldClockLogic.js: subsolar point, day/dusk/night node
// state, zone offsets and abbreviations, local time, daylight window and the
// strip gradient stops. No QML, no I/O, no Date.now(); run with
// `node --test tests/js/` (tools/check runs it with coverage).
process.env.TZ = "Europe/Amsterdam"

const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(
  path.join(__dirname, "..", "..", "plugins/araneadev.worldclock/WorldClockLogic.js")
)

const OCT20 = Date.UTC(2026, 9, 20, 10, 13)

test("subsolarPoint: June solstice noon and 20 Oct", () => {
  const a = logic.subsolarPoint(Date.UTC(2026, 5, 21, 12, 0))
  assert.ok(Math.abs(a.lat - 23.44) < 0.3)
  assert.ok(Math.abs(a.lon - -0.5) < 1)
  const b = logic.subsolarPoint(OCT20)
  assert.ok(Math.abs(b.lat - -10.6) < 0.5)
  assert.ok(Math.abs(b.lon - 22) < 1.5)
  assert.ok(b.lon >= -180 && b.lon < 180)
})

test("subsolarPoint: longitude wraps into [-180, 180)", () => {
  for (let h = 0; h < 24; h++) {
    const s = logic.subsolarPoint(Date.UTC(2026, 2, 3, h, 0))
    assert.ok(s.lon >= -180 && s.lon < 180)
  }
})

test("nodeState: day, night, dusk and none", () => {
  const sun = logic.subsolarPoint(OCT20)
  assert.equal(logic.nodeState({ lat: 52.37, lon: 4.9 }, sun), "day")
  assert.equal(logic.nodeState({ lat: 40.71, lon: -74.0 }, sun), "night")
  assert.equal(logic.nodeState({}, sun), "none")
  assert.equal(logic.nodeState(null, sun), "none")
  assert.equal(logic.nodeState({ lat: 0, lon: sun.lon + 90 }, { lat: 0, lon: sun.lon }), "dusk")
})

test("offsetMinutes and zoneAbbrev follow DST", () => {
  assert.equal(logic.offsetMinutes("Europe/London", Date.UTC(2026, 9, 24, 12)), 60)
  assert.equal(logic.offsetMinutes("Europe/London", Date.UTC(2026, 9, 25, 12)), 0)
  assert.equal(logic.zoneAbbrev("Europe/London", Date.UTC(2026, 9, 24, 12)), "BST")
  assert.equal(logic.zoneAbbrev("Europe/London", Date.UTC(2026, 9, 26, 12)), "GMT")
  assert.equal(logic.zoneAbbrev("America/New_York", Date.UTC(2026, 9, 20, 12)), "EDT")
  assert.equal(logic.zoneAbbrev("UTC", OCT20), "UTC")
})

test("offsetText: home, whole and half hours", () => {
  const t = Date.UTC(2026, 9, 20, 10)
  assert.equal(logic.offsetText("America/New_York", "Europe/Amsterdam", t), "−6 h")
  assert.equal(logic.offsetText("Asia/Kolkata", "Europe/Amsterdam", t), "+3:30 h")
  assert.equal(logic.offsetText("Asia/Bangkok", "Europe/Amsterdam", t), "+5 h")
  assert.equal(logic.offsetText("Europe/Amsterdam", "Europe/Amsterdam", t), "home")
  assert.equal(logic.offsetText("Asia/Kathmandu", "Europe/Amsterdam", t), "+3:45 h")
  assert.equal(logic.offsetText("America/St_Johns", "Europe/Amsterdam", t), "\u22124:30 h")
})

test("daylightWindow: polar night, polar day, normal window", () => {
  const sv = { lat: 78.2, lon: 15.6 }
  assert.equal(
    logic.daylightWindow(sv, "Arctic/Longyearbyen", Date.UTC(2026, 11, 21, 12)).kind,
    "night"
  )
  assert.equal(
    logic.daylightWindow(sv, "Arctic/Longyearbyen", Date.UTC(2026, 5, 21, 12)).kind,
    "day"
  )
  const w = logic.daylightWindow(
    { lat: 52.37, lon: 4.9 },
    "Europe/Amsterdam",
    Date.UTC(2026, 9, 20, 12)
  )
  assert.equal(w.kind, "window")
  assert.ok(Math.abs(w.rise - 8.2) < 0.2)
  assert.ok(Math.abs(w.set - 18.6) < 0.2)
})

test("daylightWindow: rise and set wrap into 0-24", () => {
  const w = logic.daylightWindow(
    { lat: -33.9, lon: 151.2 },
    "Pacific/Honolulu",
    Date.UTC(2026, 9, 20, 12)
  )
  assert.equal(w.kind, "window")
  assert.ok(w.rise >= 0 && w.rise < 24 && w.set >= 0 && w.set < 24)
})

test("stripStops: window, day, night", () => {
  const w = logic.daylightWindow(
    { lat: 52.37, lon: 4.9 },
    "Europe/Amsterdam",
    Date.UTC(2026, 9, 20, 12)
  )
  const s = logic.stripStops(w)
  assert.equal(s[0].tone, "night")
  assert.equal(s[s.length - 1].tone, "night")
  for (let i = 0; i < s.length; i++) {
    assert.ok(s[i].at >= 0 && s[i].at <= 1)
    if (i) assert.ok(s[i].at >= s[i - 1].at)
  }
  assert.ok(s.some((x) => x.tone === "day"))
  assert.ok(s.some((x) => x.tone === "dusk"))
  const d = logic.stripStops({ kind: "day", rise: 0, set: 24 })
  assert.ok(d.length > 0 && d.every((x) => x.tone === "day"))
  const n = logic.stripStops({ kind: "night", rise: 0, set: 0 })
  assert.ok(n.length > 0 && n.every((x) => x.tone === "night"))
})

test("stripStops: a wrapped window (set before rise) stays ascending", () => {
  const s = logic.stripStops({ kind: "window", rise: 20, set: 6 })
  for (let i = 1; i < s.length; i++) assert.ok(s[i].at >= s[i - 1].at)
  assert.ok(s.some((x) => x.tone === "day"))
  assert.ok(s.every((x) => x.at >= 0 && x.at <= 1))
})

test("nowFraction, localTime, placeCaption", () => {
  assert.equal(logic.localTime("America/Los_Angeles", OCT20), "03:13")
  assert.equal(logic.localTime("Europe/Amsterdam", Date.UTC(2026, 9, 20, 22, 0)), "00:00")
  const f = logic.nowFraction("America/Los_Angeles", OCT20)
  assert.ok(Math.abs(f - (3 * 60 + 13) / 1440) < 1e-9)
  assert.equal(logic.placeCaption({ lat: -10.4, lon: 20.2 }), "10°S 20°E")
  assert.equal(logic.placeCaption({ lat: 10.6, lon: -20.5 }), "11°N 21°W")
})

test("zoneAbbrev: a zone without a named abbreviation keeps its GMT offset", () => {
  assert.equal(logic.zoneAbbrev("Asia/Bangkok", OCT20), "GMT+7")
})
