// Logic contract for DisplaysLogic.js: parsing `omarchy-toggle-nightlight
// --status` and its caption, the keyboard backlight device lookup and
// `brightnessctl -d <device> -m` parsing, the keyboard-light command and
// control kind, which sections the dropdown shows and the keyboard order
// through them, the header caption, the pending/queue helpers (mirroring
// `araneadev.power`'s `PowerLogic`) and the keyboard hint. No QML, no I/O;
// run with `node --test tests/js/` (tools/check runs it with coverage).

const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(
  path.join(__dirname, "..", "..", "plugins/araneadev.monitor/DisplaysLogic.js")
)

// --- parseNightlight ---------------------------------------------------------------
//
// Real, read-only capture (2026-10-02) from `omarchy-toggle-nightlight
// --status`: hyprsunset isn't running right now, so it reads
// `{"enabled":false,"temperature":null}`.

test("parseNightlight parses a real --status capture (hyprsunset not running)", () => {
  assert.deepEqual(logic.parseNightlight('{"enabled":false,"temperature":null}'), {
    available: true,
    enabled: false,
    temperature: null
  })
})

test("parseNightlight parses an enabled reply with a temperature", () => {
  assert.deepEqual(logic.parseNightlight('{"enabled":true,"temperature":4000}'), {
    available: true,
    enabled: true,
    temperature: 4000
  })
})

test("parseNightlight is unavailable on invalid JSON, never throwing", () => {
  assert.deepEqual(logic.parseNightlight("not json"), {
    available: false,
    enabled: false,
    temperature: null
  })
  assert.deepEqual(logic.parseNightlight(undefined), {
    available: false,
    enabled: false,
    temperature: null
  })
  assert.deepEqual(logic.parseNightlight(""), {
    available: false,
    enabled: false,
    temperature: null
  })
})

test("parseNightlight is unavailable when the reply isn't an object", () => {
  assert.equal(logic.parseNightlight("42").available, false)
  assert.equal(logic.parseNightlight("null").available, false)
  assert.equal(logic.parseNightlight("[1,2]").available, false)
})

test("parseNightlight is unavailable with no boolean enabled field", () => {
  assert.equal(logic.parseNightlight("{}").available, false)
  assert.equal(logic.parseNightlight('{"enabled":"yes"}').available, false)
})

test("parseNightlight treats a non-numeric temperature as null", () => {
  assert.equal(logic.parseNightlight('{"enabled":true,"temperature":"warm"}').temperature, null)
})

// --- nightlightCaption -------------------------------------------------------------

test("nightlightCaption shows the temperature while on", () => {
  assert.equal(
    logic.nightlightCaption({ available: true, enabled: true, temperature: 4000 }),
    "4000 K"
  )
})

test("nightlightCaption reads Off while disabled", () => {
  assert.equal(
    logic.nightlightCaption({ available: true, enabled: false, temperature: null }),
    "Off"
  )
})

test("nightlightCaption reads Off when enabled but no temperature yet", () => {
  assert.equal(
    logic.nightlightCaption({ available: true, enabled: true, temperature: null }),
    "Off"
  )
})

test("nightlightCaption on missing state never throws, and reads Off", () => {
  assert.equal(logic.nightlightCaption(undefined), "Off")
  assert.equal(logic.nightlightCaption(null), "Off")
})

// --- kbdDevice -----------------------------------------------------------------------
//
// Real, read-only capture (2026-10-02) from `ls /sys/class/leds` on this
// machine: three input LEDs, the platform fn-lock LED, then the keyboard
// backlight, in that order.

const REAL_LEDS = [
  "input3::capslock",
  "input3::numlock",
  "input3::scrolllock",
  "platform::fnlock",
  "platform::kbd_backlight"
].join("\n")

test("kbdDevice finds the backlight entry in a real ls capture", () => {
  assert.equal(logic.kbdDevice(REAL_LEDS), "platform::kbd_backlight")
})

test("kbdDevice finds the backlight entry even when it isn't last", () => {
  const text = ["platform::kbd_backlight", "input3::capslock"].join("\n")
  assert.equal(logic.kbdDevice(text), "platform::kbd_backlight")
})

test("kbdDevice is empty with no backlight entry, or on missing/empty input", () => {
  assert.equal(logic.kbdDevice(["input3::capslock", "platform::fnlock"].join("\n")), "")
  assert.equal(logic.kbdDevice(""), "")
  assert.equal(logic.kbdDevice(undefined), "")
})

// --- parseKbdLight ---------------------------------------------------------------
//
// Real, read-only capture (2026-10-02) from `brightnessctl -d
// platform::kbd_backlight -m`: a plain on/off switch (max 1), currently on.

test("parseKbdLight parses a real brightnessctl -m capture", () => {
  assert.deepEqual(logic.parseKbdLight("platform::kbd_backlight,leds,1,100%,1"), {
    device: "platform::kbd_backlight",
    current: 1,
    max: 1
  })
})

test("parseKbdLight parses a stepped device with a higher max", () => {
  assert.deepEqual(logic.parseKbdLight("kbd_backlight,leds,5,50%,10"), {
    device: "kbd_backlight",
    current: 5,
    max: 10
  })
})

test("parseKbdLight gives max 0 on too few fields, never throwing", () => {
  assert.deepEqual(logic.parseKbdLight("kbd_backlight,leds,1"), { device: "", current: 0, max: 0 })
})

test("parseKbdLight gives max 0 on missing/empty input", () => {
  assert.deepEqual(logic.parseKbdLight(""), { device: "", current: 0, max: 0 })
  assert.deepEqual(logic.parseKbdLight(undefined), { device: "", current: 0, max: 0 })
})

test("parseKbdLight gives max 0 when current or max isn't numeric", () => {
  assert.deepEqual(logic.parseKbdLight("kbd_backlight,leds,x,50%,10"), {
    device: "",
    current: 0,
    max: 0
  })
  assert.deepEqual(logic.parseKbdLight("kbd_backlight,leds,1,50%,y"), {
    device: "",
    current: 0,
    max: 0
  })
})

// --- kbdCommand ------------------------------------------------------------------

test("kbdCommand: a plain switch turning off runs the stock off script", () => {
  assert.deepEqual(logic.kbdCommand("platform::kbd_backlight", 0, 1), [
    "omarchy-brightness-keyboard",
    "off"
  ])
})

test("kbdCommand: a plain switch turning on runs brightnessctl set 1", () => {
  assert.deepEqual(logic.kbdCommand("platform::kbd_backlight", 1, 1), [
    "brightnessctl",
    "-sd",
    "platform::kbd_backlight",
    "set",
    "1"
  ])
})

test("kbdCommand: a stepped device runs brightnessctl set at the requested level", () => {
  assert.deepEqual(logic.kbdCommand("kbd_backlight", 7, 10), [
    "brightnessctl",
    "-sd",
    "kbd_backlight",
    "set",
    "7"
  ])
})

test("kbdCommand: a stepped device at 0 is not the off script (max isn't 1)", () => {
  assert.deepEqual(logic.kbdCommand("kbd_backlight", 0, 10), [
    "brightnessctl",
    "-sd",
    "kbd_backlight",
    "set",
    "0"
  ])
})

test("kbdCommand clamps the value into [0, max]", () => {
  assert.deepEqual(logic.kbdCommand("kbd_backlight", 99, 10), [
    "brightnessctl",
    "-sd",
    "kbd_backlight",
    "set",
    "10"
  ])
  assert.deepEqual(logic.kbdCommand("kbd_backlight", -5, 10), [
    "brightnessctl",
    "-sd",
    "kbd_backlight",
    "set",
    "0"
  ])
})

test("kbdCommand clamps to 0 when there is no range (max <= 0)", () => {
  assert.deepEqual(logic.kbdCommand("kbd_backlight", 50, 0), [
    "brightnessctl",
    "-sd",
    "kbd_backlight",
    "set",
    "0"
  ])
})

test("kbdCommand rounds a fractional value", () => {
  assert.deepEqual(logic.kbdCommand("kbd_backlight", 6.6, 10), [
    "brightnessctl",
    "-sd",
    "kbd_backlight",
    "set",
    "7"
  ])
})

test("kbdCommand never throws on missing/invalid input", () => {
  assert.deepEqual(logic.kbdCommand(undefined, undefined, undefined), [
    "brightnessctl",
    "-sd",
    "",
    "set",
    "0"
  ])
})

// --- kbdMode -------------------------------------------------------------------------

test("kbdMode: max 1 is a switch", () => {
  assert.equal(logic.kbdMode(1), "switch")
})

test("kbdMode: max greater than 1 is a slider", () => {
  assert.equal(logic.kbdMode(10), "slider")
})

test("kbdMode: max 0 or missing is none", () => {
  assert.equal(logic.kbdMode(0), "none")
  assert.equal(logic.kbdMode(undefined), "none")
  assert.equal(logic.kbdMode(-1), "none")
  assert.equal(logic.kbdMode(NaN), "none")
})

// --- sectionsFor -----------------------------------------------------------------

test("sectionsFor: everything available, one display, keeps the keyboard order", () => {
  assert.deepEqual(
    logic.sectionsFor({ brightness: true, nightlight: true, kbd: true, displayCount: 1 }),
    ["brightness", "nightlight", "kbdlight", "textsize", "scale"]
  )
})

test("sectionsFor: more than one display adds monitors at the end", () => {
  assert.deepEqual(
    logic.sectionsFor({ brightness: true, nightlight: true, kbd: true, displayCount: 2 }),
    ["brightness", "nightlight", "kbdlight", "textsize", "scale", "monitors"]
  )
})

test("sectionsFor: textsize and scale are always present even with nothing else available", () => {
  assert.deepEqual(logic.sectionsFor({ displayCount: 1 }), ["textsize", "scale"])
})

test("sectionsFor: each optional section drops out on its own when unavailable", () => {
  assert.deepEqual(
    logic.sectionsFor({ brightness: false, nightlight: true, kbd: true, displayCount: 1 }),
    ["nightlight", "kbdlight", "textsize", "scale"]
  )
  assert.deepEqual(
    logic.sectionsFor({ brightness: true, nightlight: false, kbd: true, displayCount: 1 }),
    ["brightness", "kbdlight", "textsize", "scale"]
  )
  assert.deepEqual(
    logic.sectionsFor({ brightness: true, nightlight: true, kbd: false, displayCount: 1 }),
    ["brightness", "nightlight", "textsize", "scale"]
  )
})

test("sectionsFor on missing input never throws", () => {
  assert.deepEqual(logic.sectionsFor(undefined), ["textsize", "scale"])
  assert.deepEqual(logic.sectionsFor(null), ["textsize", "scale"])
})

// --- moveSection -----------------------------------------------------------------

const CHAIN = ["brightness", "nightlight", "kbdlight", "textsize", "scale", "monitors"]

test("moveSection steps forward and backward through the chain", () => {
  assert.equal(logic.moveSection(CHAIN, "brightness", 1), "nightlight")
  assert.equal(logic.moveSection(CHAIN, "scale", -1), "textsize")
})

test("moveSection clamps at the front, with no wrap", () => {
  assert.equal(logic.moveSection(CHAIN, "brightness", -1), "brightness")
})

test("moveSection clamps at the back, with no wrap", () => {
  assert.equal(logic.moveSection(CHAIN, "monitors", 1), "monitors")
})

test("moveSection on a current not in the list starts from the front", () => {
  assert.equal(logic.moveSection(CHAIN, "nope", 1), "nightlight")
  assert.equal(logic.moveSection(CHAIN, undefined, 0), "brightness")
})

test("moveSection on an empty or missing chain gives ''", () => {
  assert.equal(logic.moveSection([], "brightness", 1), "")
  assert.equal(logic.moveSection(undefined, "brightness", 1), "")
})

test("moveSection on a non-finite step stays put", () => {
  assert.equal(logic.moveSection(CHAIN, "nightlight", NaN), "nightlight")
})

// --- headerCaption ---------------------------------------------------------------

test("headerCaption joins name, resolution and scale", () => {
  assert.equal(
    logic.headerCaption({ name: "eDP-1", width: 3840, height: 2160 }, "2.67"),
    "eDP-1 · 3840×2160 · 2.67×"
  )
})

test("headerCaption trims a trailing-zero scale", () => {
  assert.equal(
    logic.headerCaption({ name: "eDP-1", width: 1920, height: 1080 }, "2.00"),
    "eDP-1 · 1920×1080 · 2×"
  )
  assert.equal(
    logic.headerCaption({ name: "eDP-1", width: 1920, height: 1080 }, "1.50"),
    "eDP-1 · 1920×1080 · 1.5×"
  )
})

test("headerCaption with no scale leaves that part out", () => {
  assert.equal(
    logic.headerCaption({ name: "eDP-1", width: 1920, height: 1080 }, ""),
    "eDP-1 · 1920×1080"
  )
  assert.equal(
    logic.headerCaption({ name: "eDP-1", width: 1920, height: 1080 }, undefined),
    "eDP-1 · 1920×1080"
  )
})

test("headerCaption with no name leaves that part out", () => {
  assert.equal(logic.headerCaption({ width: 1920, height: 1080 }, "1"), "1920×1080 · 1×")
})

test("headerCaption with no finite resolution leaves that part out", () => {
  assert.equal(logic.headerCaption({ name: "eDP-1" }, "1"), "eDP-1 · 1×")
})

test("headerCaption on missing display never throws", () => {
  assert.equal(logic.headerCaption(undefined, undefined), "")
  assert.equal(logic.headerCaption(null, null), "")
})

// --- settlePending ---------------------------------------------------------------------

test("settlePending: clears once the actual value catches up to it", () => {
  assert.equal(logic.settlePending("eDP-1", "eDP-1"), "")
})

test("settlePending: stays while the actual value hasn't caught up yet", () => {
  assert.equal(logic.settlePending("eDP-1", "DP-2"), "eDP-1")
})

test("settlePending: nothing pending stays nothing", () => {
  assert.equal(logic.settlePending("", "eDP-1"), "")
  assert.equal(logic.settlePending(undefined, "eDP-1"), "")
})

// --- takeQueued ------------------------------------------------------------------------

test("takeQueued: while running, a new request is only held, not run", () => {
  assert.deepEqual(logic.takeQueued({ running: true, queued: "2" }), { run: "", queue: "2" })
})

test("takeQueued: not running, the queued request runs and the queue drains", () => {
  assert.deepEqual(logic.takeQueued({ running: false, queued: "2" }), { run: "2", queue: "" })
})

test("takeQueued: not running with nothing queued runs nothing", () => {
  assert.deepEqual(logic.takeQueued({ running: false, queued: "" }), { run: "", queue: "" })
})

test("takeQueued: running with nothing queued holds nothing", () => {
  assert.deepEqual(logic.takeQueued({ running: true, queued: "" }), { run: "", queue: "" })
})

test("takeQueued on missing state never throws", () => {
  assert.deepEqual(logic.takeQueued(undefined), { run: "", queue: "" })
  assert.deepEqual(logic.takeQueued(null), { run: "", queue: "" })
})

// --- keyHint -------------------------------------------------------------------------

test("keyHint: brightness, kbdlight and textsize adjust with the arrow keys", () => {
  assert.equal(logic.keyHint("brightness"), "↑↓ move · ←→ adjust · tab next")
  assert.equal(logic.keyHint("kbdlight"), "↑↓ move · ←→ adjust · tab next")
  assert.equal(logic.keyHint("textsize"), "↑↓ move · ←→ adjust · tab next")
})

test("keyHint: nightlight and monitors toggle with enter", () => {
  assert.equal(logic.keyHint("nightlight"), "↑↓ move · enter toggle · tab next")
  assert.equal(logic.keyHint("monitors"), "↑↓ move · enter toggle · tab next")
})

test("keyHint: scale picks a pill with the arrow keys", () => {
  assert.equal(logic.keyHint("scale"), "↑↓ move · ←→ pick · tab next")
})

test("keyHint: any other section (or none) defaults to esc close / tab next", () => {
  assert.equal(logic.keyHint("unknown"), "esc close · tab next")
  assert.equal(logic.keyHint(undefined), "esc close · tab next")
  assert.equal(logic.keyHint(""), "esc close · tab next")
})
