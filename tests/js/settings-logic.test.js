const assert = require("node:assert/strict")
const { test } = require("node:test")
const logic = require("../../plugins/araneadev.settings/SettingsLogic.js")

test("unknown sections fall back while supported destinations survive", () => {
  assert.equal(logic.normalizeSection("unknown"), "appearance")
  assert.equal(logic.normalizeSection("schedule"), "schedule")
})
test("schedule rejects invalid clock values, missing phases and nonascending times", () => {
  assert.equal(logic.validateSchedule(["06:00", "08:00", "18:00", "20:00"]).ok, true)
  for (const times of [
    ["08:00", "06:00", "18:00", "20:00"],
    ["06:00", "08:00", "18:00", "24:00"],
    ["6:00", "08:00", "18:00", "20:00"],
    ["06:00"],
    ["06:00", "06:00", "18:00", "20:00"]
  ])
    assert.equal(logic.validateSchedule(times).ok, false)
})
test("only latest dispatched read may replace state", () => {
  assert.equal(logic.acceptRead(4, 3), false)
  assert.equal(logic.acceptRead(4, 4), true)
  assert.equal(logic.acceptRead(4, 5), false)
})
test("allowlisted commands retain arguments as separate values", () => {
  const state = {
    motion: { availability: "available" },
    wallpaper: { availability: "available" },
    wallpapersAvailability: "available",
    wallpapers: [
      { id: "day", available: true },
      { id: "missing", available: false }
    ],
    schedule: { availability: "available" },
    integrationsAvailability: "available",
    integrations: [{ id: "session", availability: "available" }]
  }
  assert.deepEqual(logic.command("/theme path/settings", "set motion", ["off"], state), [
    "/theme path/settings",
    "set",
    "motion",
    "off",
    "--json"
  ])
  assert.deepEqual(logic.command("/adapter", "set integration", ["session", "active"], state), [
    "/adapter",
    "set",
    "integration",
    "session",
    "active",
    "--json"
  ])
  assert.equal(logic.command("/adapter", "set wallpaper", ["missing"], state), null)
  assert.equal(logic.command("/adapter", "set wallpaper", ["day;touch /tmp/x"], state), null)
  assert.equal(
    logic.command("/adapter", "configure schedule", ["08:00", "06:00", "18:00", "20:00"], state),
    null
  )
  assert.equal(logic.command("/adapter", "unknown", [], state), null)
  state.motion.availability = "unavailable"
  assert.equal(logic.command("/adapter", "set motion", ["off"], state), null)
})
test("envelope parsing preserves partial sections and rejects unsupported schema", () => {
  const partial = {
    schemaVersion: 1,
    ok: false,
    state: { motion: { configured: "off", applied: "off", availability: "available" } },
    error: { code: "STATE_UNAVAILABLE", message: "schedule unavailable" }
  }
  assert.equal(logic.parseResponse(JSON.stringify(partial), 1).state.motion.configured, "off")
  assert.equal(logic.parseResponse("{", 0).state, null)
  assert.equal(logic.parseResponse('{"schemaVersion":2,"ok":true,"state":{}}', 0).state, null)
  assert.equal(logic.parseResponse('{"schemaVersion":1,"ok":true,"state":{}}', 23).ok, false)
})
test("Applied requires independent owner match; deferred and saved differ from applied", () => {
  assert.equal(
    logic.outcome(
      "set motion",
      ["off"],
      { motion: { configured: "off", applied: null, application: "deferred" } },
      true
    ),
    "Saved · application deferred"
  )
  assert.equal(
    logic.outcome(
      "set motion",
      ["off"],
      { motion: { configured: "off", applied: "on", application: "pending" } },
      true
    ),
    "Saved · application pending"
  )
  assert.equal(
    logic.outcome("set motion", ["off"], { motion: { configured: "off", applied: "off" } }, true),
    "Applied"
  )
  assert.equal(
    logic.outcome("set wallpaper", ["day"], { wallpaper: { activeId: "night" } }, true),
    "Application not confirmed"
  )
  assert.equal(
    logic.outcome("set schedule", ["on"], { schedule: { enabled: true, applied: false } }, true),
    "Saved · application pending"
  )
  assert.equal(
    logic.outcome(
      "set integration",
      ["session", "active"],
      { integrations: [{ id: "session", status: "active" }] },
      false
    ),
    "Failed"
  )
})
test("window caps preserve 24-unit margins and switch navigation at 720", () => {
  assert.deepEqual(logic.geometry(1920, 1080, 1), { width: 840, height: 620, compact: false })
  assert.deepEqual(logic.geometry(700, 500, 1), { width: 652, height: 452, compact: true })
  assert.deepEqual(logic.geometry(1280, 720, 1.5), { width: 1208, height: 648, compact: false })
})
