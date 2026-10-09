const assert = require("node:assert/strict")
const { test } = require("node:test")
const logic = require("../../plugins/araneadev.settings/SettingsLogic.js")

test("unknown sections fall back while supported destinations survive", () => {
  assert.equal(logic.normalizeSection("unknown"), "appearance")
  assert.equal(logic.normalizeSection("schedule"), "schedule")
})
test("local file URLs reject query and fragment components without changing path identity", () => {
  assert.equal(logic.normalizeFolder("file:///tmp/repo?revision=1"), "")
  assert.equal(logic.normalizeFolder("file:///tmp/repo#main"), "")
  assert.equal(
    logic.normalizeFolder("file:///tmp/repo%23main%3Frevision%3D1"),
    "/tmp/repo#main?revision=1"
  )
  assert.equal(logic.normalizeFolder("/tmp/repo#main?revision=1"), "/tmp/repo#main?revision=1")
  assert.equal(logic.normalizeFolder("file://localhost/tmp/repo%23main"), "/tmp/repo#main")
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
test("compact window height preserves 24-unit caps and navigation threshold", () => {
  assert.deepEqual(logic.geometry(1920, 1080, 1), { width: 840, height: 460, compact: false })
  assert.deepEqual(logic.geometry(1920, 1080, 2), { width: 1680, height: 920, compact: false })
  assert.deepEqual(logic.geometry(1280 / 2.667, 720 / 2.667, 1), {
    width: 1280 / 2.667 - 48,
    height: 720 / 2.667 - 48,
    compact: true
  })
  assert.deepEqual(logic.geometry(700, 500, 1), { width: 652, height: 452, compact: true })
  assert.deepEqual(logic.geometry(1280, 720, 1.5), { width: 1208, height: 648, compact: false })
})

test("custom scale validates decimals and preserves exact argv and observed target", () => {
  const state = { display: { monitor: "eDP-1", scale: 2, availability: "available" } }
  for (const scale of ["2.5", "2.667", "1", "4"]) {
    assert.equal(logic.validateScale(scale).ok, true)
    assert.deepEqual(logic.command("/adapter", "set display-scale", [scale], state), [
      "/adapter",
      "set",
      "display-scale",
      scale,
      "--monitor",
      "eDP-1",
      "--json"
    ])
  }
  for (const scale of ["0", "4.1", "2e0", " 2.5", "2;touch /tmp/x", "NaN", ""]) {
    assert.equal(logic.validateScale(scale).ok, false)
    assert.equal(logic.command("/adapter", "set display-scale", [scale], state), null)
  }
  state.display.availability = "unavailable"
  assert.equal(logic.command("/adapter", "set display-scale", ["2.5"], state), null)
})
test("scale outcome checks effective scale and identity through later independent read", () => {
  const result = {
    displayScale: {
      requested: "2.667",
      monitor: "eDP-1",
      width: 3840,
      height: 2160,
      expectedScale: 2.6666666667,
      effectiveScale: 2.666667,
      confirmed: true,
      persistence: "session-only"
    }
  }
  const state = {
    display: {
      monitor: "eDP-1",
      scale: 2.666667,
      width: 3840,
      height: 2160,
      availability: "available"
    }
  }
  assert.match(
    logic.outcome("set display-scale", ["2.667"], state, true, result),
    /2.666667.*session only/
  )
  state.display.monitor = "DP-1"
  assert.equal(
    logic.outcome("set display-scale", ["2.667"], state, true, result),
    "Application not confirmed"
  )
  state.display.monitor = "eDP-1"
  state.display.scale = 2
  assert.equal(
    logic.outcome("set display-scale", ["2.667"], state, true, result),
    "Application not confirmed"
  )
  assert.deepEqual(
    logic.parseResponse(JSON.stringify({ schemaVersion: 1, ok: true, state, result }), 0).result,
    result
  )
})

test("scale feedback rechecks saved persistence in the later owner snapshot", () => {
  const result = {
    displayScale: {
      requested: "2.5",
      monitor: "eDP-1",
      width: 3840,
      height: 2160,
      expectedScale: 2.5,
      confirmed: true,
      persistence: "persisted"
    }
  }
  const state = {
    display: {
      monitor: "eDP-1",
      width: 3840,
      height: 2160,
      scale: 2.5,
      availability: "available",
      persistenceSupport: "supported",
      configuredScale: 2
    }
  }
  assert.match(
    logic.outcome("set display-scale", ["2.5"], state, true, result),
    /persistence unconfirmed/
  )
  state.display.configuredScale = 2.5
  assert.match(logic.outcome("set display-scale", ["2.5"], state, true, result), /saved/)
})
test("scale confirmation requires the applied display mode as well as connector", () => {
  const result = {
    displayScale: {
      requested: "2.5",
      monitor: "eDP-1",
      width: 3840,
      height: 2160,
      expectedScale: 2.5,
      confirmed: true,
      persistence: "persisted"
    }
  }
  const state = {
    display: { monitor: "eDP-1", width: 1920, height: 1080, scale: 2.5, availability: "available" }
  }
  assert.equal(
    logic.outcome("set display-scale", ["2.5"], state, true, result),
    "Application not confirmed"
  )
})

test("scale confirmation needs complete mode metadata and a boolean confirmation", () => {
  const result = {
    displayScale: {
      requested: "2.5",
      monitor: "eDP-1",
      expectedScale: 2.5,
      confirmed: true,
      persistence: "session-only"
    }
  }
  const state = {
    display: { monitor: "eDP-1", width: 3840, height: 2160, scale: 2.5, availability: "available" }
  }
  assert.equal(
    logic.outcome("set display-scale", ["2.5"], state, true, result),
    "Application not confirmed"
  )
  Object.assign(result.displayScale, { width: 3840, height: 2160, confirmed: "true" })
  assert.equal(
    logic.outcome("set display-scale", ["2.5"], state, true, result),
    "Application not confirmed"
  )
})

// Catches the generic failure branch hiding independently confirmed persistence.
test("failed motion preserves saved preference while live failure stays unsuccessful", () => {
  for (const [applied, expected] of [
    ["off", "Saved · live application failed"],
    [null, "Saved · live application unconfirmed"],
    ["on", "Saved · live application unconfirmed"]
  ]) {
    const envelope = logic.parseResponse(
      JSON.stringify({
        schemaVersion: 1,
        ok: false,
        state: {
          motion: { configured: "on", applied, availability: "available", application: "pending" }
        },
        error: { code: "HELPER_FAILED", message: "compositor rejected animations" }
      }),
      7
    )
    assert.equal(envelope.ok, false)
    assert.equal(logic.outcome("set motion", ["on"], envelope.state, envelope.ok), expected)
    assert.equal(envelope.error.message, "compositor rejected animations")
  }
  assert.equal(
    logic.outcome("set motion", ["on"], { motion: { configured: "off", applied: "on" } }, false),
    "Failed"
  )
  assert.equal(logic.outcome("set motion", ["on"], null, false), "Failed")
})

test("Display normalizes alongside existing stable destinations", () => {
  for (const section of ["appearance", "display", "schedule", "integrations", "notifications"])
    assert.equal(logic.normalizeSection(section), section)
})

test("font selection uses installed roles and exact argv, defaults and owner readback", () => {
  const state = {
    fonts: {
      availability: "available",
      uiFamily: "Example Sans",
      technicalFamily: "Example Mono",
      families: ["Example Sans", "Example Mono"],
      monospaceFamilies: ["Example Mono"]
    }
  }
  assert.deepEqual(
    logic.command("/theme/settings", "configure fonts", ["Example Sans", "Example Mono"], state),
    ["/theme/settings", "configure", "fonts", "Example Sans", "Example Mono", "--json"]
  )
  assert.deepEqual(logic.command("/theme/settings", "configure fonts", ["", ""], state), [
    "/theme/settings",
    "configure",
    "fonts",
    "",
    "",
    "--json"
  ])
  assert.equal(
    logic.command("/theme/settings", "configure fonts", ["Missing", "Example Mono"], state),
    null
  )
  assert.equal(
    logic.command("/theme/settings", "configure fonts", ["Example Sans", "Example Sans"], state),
    null
  )
  assert.equal(
    logic.command("/theme/settings", "configure fonts", ["", ""], {
      fonts: { ...state.fonts, availability: "unavailable" }
    }),
    null
  )
  assert.equal(
    logic.outcome("configure fonts", ["Example Sans", "Example Mono"], state, true),
    "Applied"
  )
  assert.equal(logic.outcome("configure fonts", ["", ""], state, true), "Save not confirmed")
})
