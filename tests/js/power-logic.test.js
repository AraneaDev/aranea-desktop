// Logic contract for PowerLogic.js: the battery object path from `upower
// -e`, parsing busctl's GetHistory reply, building the 24h history chart's
// polyline segments and summary, formatting a sample time as a clock label,
// parsing busctl's EnergyRate property, the stock detail-row and hero-status
// rules (from `/usr/share/omarchy/shell/plugins/panels/power/Panel.qml`),
// and the keyboard hint. No QML, no I/O; run with `node --test tests/js/`
// (tools/check runs it with coverage).
//
// TZ is pinned before anything touches `Date`, since `timeLabel` reads local
// time (see the module header for why Europe/Amsterdam specifically).
process.env.TZ = "Europe/Amsterdam"

const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.power/PowerLogic.js"))

// --- batteryPath ---------------------------------------------------------------
//
// Real, read-only `upower -e` capture from this machine (2026-10-02): a
// battery, a line-power (AC) device, a Bluetooth headset and the synthetic
// DisplayDevice, in that order.

const REAL_UPOWER_ENUMERATE = [
  "/org/freedesktop/UPower/devices/battery_BAT1",
  "/org/freedesktop/UPower/devices/line_power_ACAD",
  "/org/freedesktop/UPower/devices/headset_dev_41_42_E4_22_11_78",
  "/org/freedesktop/UPower/devices/DisplayDevice"
].join("\n")

test("batteryPath finds the battery line in a real upower -e capture", () => {
  assert.equal(
    logic.batteryPath(REAL_UPOWER_ENUMERATE),
    "/org/freedesktop/UPower/devices/battery_BAT1"
  )
})

test("batteryPath finds the battery line even when it isn't first", () => {
  const text = [
    "/org/freedesktop/UPower/devices/line_power_ACAD",
    "/org/freedesktop/UPower/devices/battery_BAT0",
    "/org/freedesktop/UPower/devices/DisplayDevice"
  ].join("\n")
  assert.equal(logic.batteryPath(text), "/org/freedesktop/UPower/devices/battery_BAT0")
})

test("batteryPath is empty with no battery device, or on missing/empty input", () => {
  const text = [
    "/org/freedesktop/UPower/devices/line_power_ACAD",
    "/org/freedesktop/UPower/devices/DisplayDevice"
  ].join("\n")
  assert.equal(logic.batteryPath(text), "")
  assert.equal(logic.batteryPath(""), "")
  assert.equal(logic.batteryPath(undefined), "")
})

// --- parseHistory ----------------------------------------------------------------
//
// Real, read-only capture (2026-10-02) from `busctl --json=short call
// org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_BAT1
// org.freedesktop.UPower.Device GetHistory suu charge 86400 50`: busctl's
// `--json=short` wraps the method's single `a(udu)` out-parameter as
// `data: [ [ [time, percent, state], ... ] ]` (one array of 10 structs,
// newest first, since this battery only has 10 history points right now).
// Times and percentages are read-only facts about this machine and are fine
// to commit verbatim (task instructions).

const REAL_HISTORY_JSON =
  '{"type":"a(udu)","data":[[[1790918615,1.000000000000000000000e+02,4],' +
  "[1790917104,9.900000000000000000000e+01,1],[1790916804,9.800000000000000000000e+01,1]," +
  "[1790916563,9.700000000000000000000e+01,1],[1790916353,9.600000000000000000000e+01,1]," +
  "[1790916023,9.500000000000000000000e+01,4],[1790915873,9.600000000000000000000e+01,4]," +
  "[1790915723,9.700000000000000000000e+01,4],[1790915572,9.800000000000000000000e+01,4]," +
  "[1790915422,9.900000000000000000000e+01,4]]]}"

test("parseHistory parses a real GetHistory reply, newest-first input sorted oldest-first", () => {
  assert.deepEqual(logic.parseHistory(REAL_HISTORY_JSON), [
    { t: 1790915422, pct: 99, state: 4 },
    { t: 1790915572, pct: 98, state: 4 },
    { t: 1790915723, pct: 97, state: 4 },
    { t: 1790915873, pct: 96, state: 4 },
    { t: 1790916023, pct: 95, state: 4 },
    { t: 1790916353, pct: 96, state: 1 },
    { t: 1790916563, pct: 97, state: 1 },
    { t: 1790916804, pct: 98, state: 1 },
    { t: 1790917104, pct: 99, state: 1 },
    { t: 1790918615, pct: 100, state: 4 }
  ])
})

test("parseHistory drops entries with t <= 0", () => {
  const json = '{"type":"a(udu)","data":[[[0,50,1],[-5,40,1],[1000,60,1]]]}'
  assert.deepEqual(logic.parseHistory(json), [{ t: 1000, pct: 60, state: 1 }])
})

test("parseHistory skips malformed entries rather than throwing", () => {
  const json = '{"type":"a(udu)","data":[[[1000,60],"nope",null,[2000,70,1]]]}'
  assert.deepEqual(logic.parseHistory(json), [
    { t: 1000, pct: 60, state: undefined },
    { t: 2000, pct: 70, state: 1 }
  ])
})

test("parseHistory on an empty history gives []", () => {
  assert.deepEqual(logic.parseHistory('{"type":"a(udu)","data":[[]]}'), [])
})

test("parseHistory on invalid input never throws, and gives []", () => {
  assert.deepEqual(logic.parseHistory("not json"), [])
  assert.deepEqual(logic.parseHistory(undefined), [])
  assert.deepEqual(logic.parseHistory(""), [])
  assert.deepEqual(logic.parseHistory("{}"), [])
  assert.deepEqual(logic.parseHistory('{"data":"nope"}'), [])
  assert.deepEqual(logic.parseHistory('{"data":[]}'), [])
})

// --- historyPoints -----------------------------------------------------------------
//
// width = 86400 and height = 100 are chosen so `x = (t - windowStart)` and
// `y = 100 - pct` directly, keeping the fixtures' arithmetic readable.

const NOW = 200000
const WINDOW_START = NOW - 86400

test("historyPoints: consecutive samples within 1800s stay in one segment", () => {
  const samples = [
    { t: WINDOW_START + 100, pct: 50, state: 1 },
    { t: WINDOW_START + 200, pct: 60, state: 1 }
  ]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [
    [
      { x: 100, y: 50 },
      { x: 200, y: 40 }
    ]
  ])
})

test("historyPoints: a gap of more than 1800s starts a new segment", () => {
  const samples = [
    { t: WINDOW_START + 100, pct: 50, state: 1 },
    { t: WINDOW_START + 200, pct: 60, state: 1 },
    { t: WINDOW_START + 2500, pct: 70, state: 1 },
    { t: WINDOW_START + 2600, pct: 80, state: 1 }
  ]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [
    [
      { x: 100, y: 50 },
      { x: 200, y: 40 }
    ],
    [
      { x: 2500, y: 30 },
      { x: 2600, y: 20 }
    ]
  ])
})

test("historyPoints: a gap of exactly 1800s stays in the same segment", () => {
  const samples = [
    { t: WINDOW_START + 100, pct: 50, state: 1 },
    { t: WINDOW_START + 1900, pct: 60, state: 1 }
  ]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [
    [
      { x: 100, y: 50 },
      { x: 1900, y: 40 }
    ]
  ])
})

test("historyPoints: a sample before the window becomes a clipped start point at x=0", () => {
  const samples = [
    { t: WINDOW_START - 500, pct: 40, state: 1 },
    { t: WINDOW_START + 300, pct: 55, state: 1 }
  ]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [
    [
      { x: 0, y: 60 },
      { x: 300, y: 45 }
    ]
  ])
})

test("historyPoints: only the LAST sample before the window is kept as the clip point", () => {
  const samples = [
    { t: WINDOW_START - 9000, pct: 10, state: 1 },
    { t: WINDOW_START - 500, pct: 40, state: 1 },
    { t: WINDOW_START + 300, pct: 55, state: 1 }
  ]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [
    [
      { x: 0, y: 60 },
      { x: 300, y: 45 }
    ]
  ])
})

test("historyPoints: a clip point more than 1800s from the next real sample starts its own segment", () => {
  const samples = [
    { t: WINDOW_START - 100000, pct: 40, state: 1 },
    { t: WINDOW_START + 5000, pct: 90, state: 1 }
  ]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [
    [{ x: 0, y: 60 }],
    [{ x: 5000, y: 10 }]
  ])
})

test("historyPoints: one sample in the window with nothing before it gives one single-point segment", () => {
  const samples = [{ t: WINDOW_START + 500, pct: 77, state: 1 }]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [[{ x: 500, y: 23 }]])
})

test("historyPoints: samples after now are dropped", () => {
  const samples = [
    { t: NOW + 500, pct: 99, state: 1 },
    { t: WINDOW_START + 300, pct: 50, state: 1 }
  ]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [[{ x: 300, y: 50 }]])
})

test("historyPoints: a sample exactly at now is kept, at the right edge", () => {
  const samples = [{ t: NOW, pct: 88, state: 1 }]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [[{ x: 86400, y: 12 }]])
})

test("historyPoints on an empty history gives []", () => {
  assert.deepEqual(logic.historyPoints([], NOW, 86400, 100), [])
})

test("historyPoints on missing/malformed samples never throws, and gives []", () => {
  assert.deepEqual(logic.historyPoints(undefined, NOW, 86400, 100), [])
  assert.deepEqual(logic.historyPoints(null, NOW, 86400, 100), [])
})

test("historyPoints tolerates samples given out of order", () => {
  const samples = [
    { t: WINDOW_START + 200, pct: 60, state: 1 },
    { t: WINDOW_START + 100, pct: 50, state: 1 }
  ]
  assert.deepEqual(logic.historyPoints(samples, NOW, 86400, 100), [
    [
      { x: 100, y: 50 },
      { x: 200, y: 40 }
    ]
  ])
})

// --- historySummary ----------------------------------------------------------------

test("historySummary: the first sample in the window, rounded, to the current percentage", () => {
  const samples = [
    { t: 1, pct: 42.4, state: 1 },
    { t: 2, pct: 55, state: 1 }
  ]
  assert.equal(logic.historySummary(samples, 77.6), "42% → 78%")
})

test("historySummary is empty with no samples", () => {
  assert.equal(logic.historySummary([], 50), "")
  assert.equal(logic.historySummary(undefined, 50), "")
})

// --- timeLabel -----------------------------------------------------------------------
//
// TZ is pinned to Europe/Amsterdam at the top of this file. Timestamps are
// built with the local `Date` constructor (year, month 0-based, day, hour,
// minute) so they land on the pinned TZ's wall-clock time regardless of its
// UTC offset or DST state on the chosen date.

const toSec = (y, mo, d, h, mi) => Math.floor(new Date(y, mo, d, h, mi, 0).getTime() / 1000)

test("timeLabel: same calendar day reads HH:MM, zero-padded", () => {
  const now = toSec(2026, 9, 2, 14, 30)
  assert.equal(logic.timeLabel(toSec(2026, 9, 2, 9, 5), now), "09:05")
})

test("timeLabel: the previous calendar day reads 'yesterday HH:MM'", () => {
  const now = toSec(2026, 9, 2, 1, 10)
  assert.equal(logic.timeLabel(toSec(2026, 9, 1, 23, 45), now), "yesterday 23:45")
})

test("timeLabel: right at midnight, a minute earlier is yesterday", () => {
  const now = toSec(2026, 9, 2, 0, 0)
  assert.equal(logic.timeLabel(toSec(2026, 9, 1, 23, 59), now), "yesterday 23:59")
})

test("timeLabel: right at midnight, the same instant is today", () => {
  const now = toSec(2026, 9, 2, 0, 0)
  assert.equal(logic.timeLabel(now, now), "00:00")
})

// --- parseEnergyRate ---------------------------------------------------------------
//
// Real, read-only capture (2026-10-02) from `busctl --json=short
// get-property org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_BAT1
// org.freedesktop.UPower.Device EnergyRate`: `{"type":"d","data":0}` (idle,
// fully charged, on AC at capture time).

test("parseEnergyRate parses a real EnergyRate property reply", () => {
  assert.equal(logic.parseEnergyRate('{"type":"d","data":0.000000000000000000000e+00}'), 0)
})

test("parseEnergyRate parses a positive rate", () => {
  assert.equal(logic.parseEnergyRate('{"type":"d","data":8.4}'), 8.4)
})

test("parseEnergyRate is never negative", () => {
  assert.equal(logic.parseEnergyRate('{"type":"d","data":-3.2}'), 0)
})

test("parseEnergyRate is 0 on bad input, never throwing", () => {
  assert.equal(logic.parseEnergyRate("not json"), 0)
  assert.equal(logic.parseEnergyRate(undefined), 0)
  assert.equal(logic.parseEnergyRate("{}"), 0)
  assert.equal(logic.parseEnergyRate('{"data":"nope"}'), 0)
})

// --- detailRows ------------------------------------------------------------------
//
// Stock's exact rules, from `/usr/share/omarchy/shell/plugins/panels/power/Panel.qml`'s
// InfoPair bindings.

test("detailRows: charge-threshold active shows the limit and 'Holding'", () => {
  const info = { threshold: "80%", size: "52 Wh", cycles: "120" }
  const s = { thresholdActive: true, discharging: false, flowIdle: false, full: false }
  assert.deepEqual(logic.detailRows(info, s), [
    { label: "Charge limit", value: "80%" },
    { label: "Battery state", value: "Holding" },
    { label: "Battery size", value: "52 Wh" },
    { label: "Charge cycles", value: "120" }
  ])
})

test("detailRows: threshold active with no threshold value falls back to '-'", () => {
  const s = { thresholdActive: true, discharging: false, flowIdle: false, full: false }
  assert.equal(logic.detailRows({}, s)[0].value, "-")
})

test("detailRows: discharging shows Time left and Discharging with the rate", () => {
  const info = { time: "3:12", rate: "8.4 W", size: "52 Wh", cycles: "120" }
  const s = { thresholdActive: false, discharging: true, flowIdle: false, full: false }
  assert.deepEqual(logic.detailRows(info, s), [
    { label: "Time left", value: "3:12" },
    { label: "Discharging", value: "8.4 W" },
    { label: "Battery size", value: "52 Wh" },
    { label: "Charge cycles", value: "120" }
  ])
})

test("detailRows: discharging with no time value falls back to the em dash", () => {
  const s = { thresholdActive: false, discharging: true, flowIdle: false, full: false }
  assert.equal(logic.detailRows({}, s)[0].value, "\u2014")
})

test("detailRows: charging and idle (flowIdle) shows Time to full as '-' and Charging with the rate", () => {
  const info = { rate: "22 W", size: "52 Wh", cycles: "120" }
  const s = { thresholdActive: false, discharging: false, flowIdle: true, full: false }
  assert.deepEqual(logic.detailRows(info, s), [
    { label: "Time to full", value: "-" },
    { label: "Charging", value: "22 W" },
    { label: "Battery size", value: "52 Wh" },
    { label: "Charge cycles", value: "120" }
  ])
})

test("detailRows: charging and not idle shows Time to full with the time", () => {
  const info = { time: "0:45", rate: "22 W" }
  const s = { thresholdActive: false, discharging: false, flowIdle: false, full: false }
  assert.deepEqual(logic.detailRows(info, s).slice(0, 2), [
    { label: "Time to full", value: "0:45" },
    { label: "Charging", value: "22 W" }
  ])
})

test("detailRows: full battery shows '-' for the rate even though flowIdle is also true", () => {
  const info = { rate: "0 W" }
  const s = { thresholdActive: false, discharging: false, flowIdle: true, full: true }
  assert.deepEqual(logic.detailRows(info, s).slice(0, 2), [
    { label: "Time to full", value: "-" },
    { label: "Charging", value: "-" }
  ])
})

test("detailRows: missing size/cycles fall back to '' and the em dash", () => {
  const s = { thresholdActive: false, discharging: false, flowIdle: false, full: false }
  assert.deepEqual(logic.detailRows({}, s).slice(2), [
    { label: "Battery size", value: "" },
    { label: "Charge cycles", value: "\u2014" }
  ])
})

test("detailRows on missing info/s never throws", () => {
  assert.equal(logic.detailRows(undefined, undefined).length, 4)
  assert.equal(logic.detailRows(null, null).length, 4)
})

// --- heroStatus --------------------------------------------------------------------

test("heroStatus: fully charged wins over everything else", () => {
  assert.equal(
    logic.heroStatus({ fullyCharged: true }, ["Pumping power"], 0, "Charging"),
    "Fully charged"
  )
})

test("heroStatus: the rotating phrase at phraseIndex, wrapped by the list length", () => {
  const phrases = ["a", "b", "c"]
  assert.equal(logic.heroStatus({ fullyCharged: false }, phrases, 0, "Charging"), "a")
  assert.equal(logic.heroStatus({ fullyCharged: false }, phrases, 1, "Charging"), "b")
  assert.equal(logic.heroStatus({ fullyCharged: false }, phrases, 3, "Charging"), "a")
})

test("heroStatus: no phrases falls back to the mode label", () => {
  assert.equal(logic.heroStatus({ fullyCharged: false }, [], 0, "Charging"), "Charging")
  assert.equal(
    logic.heroStatus({ fullyCharged: false }, undefined, 0, "Not charging"),
    "Not charging"
  )
})

test("heroStatus on missing state never throws", () => {
  assert.equal(logic.heroStatus(undefined, [], 0, "Idle"), "Idle")
})

// --- keyHint -------------------------------------------------------------------------

test("keyHint: the profiles section picks with arrows", () => {
  assert.equal(logic.keyHint("profiles"), "←→ pick · enter set · tab next")
})

test("keyHint: any other section (or none) defaults to esc close / tab next", () => {
  assert.equal(logic.keyHint("details"), "esc close · tab next")
  assert.equal(logic.keyHint(undefined), "esc close · tab next")
  assert.equal(logic.keyHint(""), "esc close · tab next")
})
