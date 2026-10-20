// Logic contract for WorldClockLogic.js: subsolar point, day/dusk/night node
// state, zone offsets and abbreviations, local time, daylight window and the
// strip gradient stops. No QML, no I/O, no Date.now(); run with
// `node --test tests/js/` (tools/check runs it with coverage).
process.env.TZ = "Europe/Amsterdam"

const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")
const { execFileSync } = require("node:child_process")
const fs = require("node:fs")
const vm = require("node:vm")

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

const PROBE =
  "LOCAL|Europe/Amsterdam\nEurope/Amsterdam|CEST|+0200\nEurope/London|BST|+0100\n" +
  "America/New_York|EDT|-0400\nAsia/Kolkata|IST|+0530\nAsia/Bangkok|+07|+0700\nUTC|UTC|+0000\n"

test("parseProbe: local zone, offsets, abbreviations; malformed lines ignored", () => {
  const p = logic.parseProbe(PROBE + "garbage\nA|B\n|X|+0100\nBad/Zone|XX|nope\n")
  assert.equal(p.local, "Europe/Amsterdam")
  assert.equal(p.zones["Europe/London"].offsetMinutes, 60)
  assert.equal(p.zones["Europe/London"].abbr, "BST")
  assert.equal(p.zones["Asia/Kolkata"].offsetMinutes, 330)
  assert.equal(p.zones["America/New_York"].offsetMinutes, -240)
  assert.equal(Object.keys(p.zones).length, 6)
  assert.equal(logic.parseProbe(undefined).local, "")
})

test("abbrevText: numeric names become GMT offsets", () => {
  const z = logic.parseProbe(PROBE).zones
  assert.equal(logic.abbrevText(z["Asia/Bangkok"], "Asia/Bangkok"), "GMT+7")
  assert.equal(logic.abbrevText({ abbr: "+0530" }, "X"), "GMT+5:30")
  assert.equal(logic.abbrevText({ abbr: "-03" }, "X"), "GMT-3")
  assert.equal(logic.abbrevText(z.UTC, "UTC"), "UTC")
  assert.equal(logic.abbrevText(z["Europe/London"], "Europe/London"), "BST")
  assert.equal(logic.abbrevText(undefined, "X"), "")
})

test("probeCommand: zones are trailing arguments only", () => {
  const argv = logic.probeCommand(["Europe/London"], true)
  assert.deepEqual(argv.slice(0, 2), ["bash", "-c"])
  assert.deepEqual(argv.slice(3), ["bash", "Europe/London"])
  assert.ok(!argv[2].includes("Europe/London"))
  assert.ok(argv[2].includes("LOCAL"))
  assert.ok(!logic.probeCommand(["UTC"], false)[2].includes("LOCAL"))
  assert.deepEqual(logic.probeCommand(null, false).slice(3), ["bash"])
})

test("probeCommand: the script really runs and parses", () => {
  const argv = logic.probeCommand(["Europe/London", "UTC"], true)
  const out = execFileSync(argv[0], argv.slice(1), { encoding: "utf8" })
  const p = logic.parseProbe(out)
  assert.ok(p.local.length > 0)
  assert.ok([0, 60].includes(p.zones["Europe/London"].offsetMinutes))
  assert.equal(p.zones.UTC.offsetMinutes, 0)
})

test("offsetText: home, whole and half hours", () => {
  assert.equal(logic.offsetText(-240, 120), "−6 h")
  assert.equal(logic.offsetText(330, 120), "+3:30 h")
  assert.equal(logic.offsetText(420, 120), "+5 h")
  assert.equal(logic.offsetText(120, 120), "home")
  assert.equal(logic.offsetText(345, 120), "+3:45 h")
  assert.equal(logic.offsetText(-150, 120), "−4:30 h")
})

test("daylightWindow: polar night, polar day, normal window", () => {
  const sv = { lat: 78.2, lon: 15.6 }
  assert.equal(logic.daylightWindow(sv, 60, Date.UTC(2026, 11, 21, 12)).kind, "night")
  assert.equal(logic.daylightWindow(sv, 60, Date.UTC(2026, 5, 21, 12)).kind, "day")
  const w = logic.daylightWindow({ lat: 52.37, lon: 4.9 }, 120, Date.UTC(2026, 9, 20, 12))
  assert.equal(w.kind, "window")
  assert.ok(Math.abs(w.rise - 8.2) < 0.2)
  assert.ok(Math.abs(w.set - 18.6) < 0.2)
})

test("daylightWindow: rise and set wrap into 0-24", () => {
  const w = logic.daylightWindow({ lat: -33.9, lon: 151.2 }, -600, Date.UTC(2026, 9, 20, 12))
  assert.equal(w.kind, "window")
  assert.ok(w.rise >= 0 && w.rise < 24 && w.set >= 0 && w.set < 24)
})

test("stripStops: window, day, night", () => {
  const w = logic.daylightWindow({ lat: 52.37, lon: 4.9 }, 120, Date.UTC(2026, 9, 20, 12))
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
  assert.equal(logic.localTime(-420, OCT20), "03:13")
  assert.equal(logic.localTime(120, Date.UTC(2026, 9, 20, 22, 0)), "00:00")
  const f = logic.nowFraction(-420, OCT20)
  assert.ok(Math.abs(f - (3 * 60 + 13) / 1440) < 1e-9)
  assert.equal(logic.placeCaption({ lat: -10.4, lon: 20.2 }), "10°S 20°E")
  assert.equal(logic.placeCaption({ lat: 10.6, lon: -20.5 }), "11°N 21°W")
})

test("daylightWindow: stable across one local day", () => {
  const place = { lat: 52.37, lon: 4.9 }
  const a = logic.daylightWindow(place, 60, Date.UTC(2026, 2, 19, 23, 30))
  const b = logic.daylightWindow(place, 60, Date.UTC(2026, 2, 20, 22, 30))
  assert.deepEqual(a, b)
})

test("loads and runs in a context without Intl (the QML engine)", () => {
  const file = path.join(__dirname, "..", "..", "plugins/araneadev.worldclock/WorldClockLogic.js")
  const ctx = vm.createContext({ module: { exports: {} } })
  vm.runInContext("delete globalThis.Intl", ctx)
  vm.runInContext(fs.readFileSync(file, "utf8"), ctx)
  assert.equal(vm.runInContext("typeof Intl", ctx), "undefined")
  const m = ctx.module.exports
  const sun = m.subsolarPoint(OCT20)
  const w = m.daylightWindow({ lat: 52, lon: 5 }, 120, OCT20)
  const calls = [
    sun,
    m.sunElevation(1, 2, sun),
    m.nodeState({ lat: 1, lon: 2 }, sun),
    m.probeCommand(["UTC"], true),
    m.parseProbe(PROBE),
    m.abbrevText({ abbr: "+07" }, "X"),
    m.localTime(60, OCT20),
    m.offsetText(60, 0),
    w,
    m.stripStops(w),
    m.nowFraction(60, OCT20),
    m.placeCaption(sun)
  ]
  assert.equal(calls.length, 12)
  assert.equal(Object.keys(m).length, 12)
})
