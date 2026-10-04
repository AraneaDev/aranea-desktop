// Logic contract for DisplaysLogic.js: parsing `omarchy-toggle-nightlight
// --status` and its caption, the keyboard backlight device lookup and
// `brightnessctl -d <device> -m` parsing, the keyboard-light command and
// control kind, which sections the dropdown shows and the keyboard order
// through them, the header caption, the pending/queue helpers (mirroring
// `araneadev.power`'s `PowerLogic`), the last-display guard, the
// focus-checked scale command, the exit queue and the keyboard hint. No QML, no I/O;
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
  assert.equal(logic.keyHint("brightness"), "↑↓ move · ←→ adjust")
  assert.equal(logic.keyHint("kbdlight"), "↑↓ move · ←→ adjust")
  assert.equal(logic.keyHint("textsize"), "↑↓ move · ←→ adjust")
})

test("keyHint: nightlight and monitors toggle with enter", () => {
  assert.equal(logic.keyHint("nightlight"), "↑↓ move · enter toggle")
  assert.equal(logic.keyHint("monitors"), "↑↓ move · enter toggle")
})

test("keyHint: scale picks a pill with the arrow keys", () => {
  assert.equal(logic.keyHint("scale"), "↑↓ move · ←→ pick · enter set")
})

test("keyHint: any other section (or none) defaults to esc close", () => {
  assert.equal(logic.keyHint("unknown"), "esc close")
  assert.equal(logic.keyHint(undefined), "esc close")
  assert.equal(logic.keyHint(""), "esc close")
})

// --- mayDisable / lastEnabledName (C1: never switch off the last display) ----------
//
// Only a display CONFIRMED on (read enabled, and no pending request to switch
// it off) counts as another enabled display; a display that is only pending
// on never does.

test("mayDisable: allowed while another display is confirmed on", () => {
  assert.equal(logic.mayDisable("eDP-1", { "eDP-1": true, "DP-2": true }, {}), true)
})

test("mayDisable: two displays, the other only pending on, is refused", () => {
  assert.equal(logic.mayDisable("eDP-1", { "eDP-1": true, "DP-2": false }, { "DP-2": true }), false)
})

test("mayDisable: the pending-on display failed (its request dropped), still refused", () => {
  assert.equal(logic.mayDisable("eDP-1", { "eDP-1": true, "DP-2": false }, {}), false)
})

test("mayDisable: another display already pending off does not count", () => {
  assert.equal(logic.mayDisable("eDP-1", { "eDP-1": true, "DP-2": true }, { "DP-2": false }), false)
})

test("mayDisable: a single display is refused", () => {
  assert.equal(logic.mayDisable("eDP-1", { "eDP-1": true }, {}), false)
})

test("mayDisable: no name, or missing maps, is refused without throwing", () => {
  assert.equal(logic.mayDisable("", { "eDP-1": true, "DP-2": true }, {}), false)
  assert.equal(logic.mayDisable("eDP-1", undefined, undefined), false)
  assert.equal(logic.mayDisable("eDP-1", { "DP-2": true }, null), true)
  assert.equal(logic.mayDisable("eDP-1", { "eDP-1": true, "DP-2": true }, { "DP-2": true }), false)
})

test("lastEnabledName: the only confirmed-on display", () => {
  assert.equal(logic.lastEnabledName({ "eDP-1": true, "DP-2": false }, {}), "eDP-1")
})

test("lastEnabledName: a display only pending on leaves the confirmed one last", () => {
  assert.equal(logic.lastEnabledName({ "eDP-1": true, "DP-2": false }, { "DP-2": true }), "eDP-1")
})

test("lastEnabledName: a display pending off leaves the other last", () => {
  assert.equal(logic.lastEnabledName({ "eDP-1": true, "DP-2": true }, { "eDP-1": false }), "DP-2")
})

test("lastEnabledName: two confirmed on, or none, gives no last display", () => {
  assert.equal(logic.lastEnabledName({ "eDP-1": true, "DP-2": true }, {}), "")
  assert.equal(logic.lastEnabledName({ "eDP-1": false }, {}), "")
  assert.equal(logic.lastEnabledName(undefined, undefined), "")
})

// --- scaleCommand (C2: a scale only lands on the display it was chosen for) -----------

test("scaleCommand: checks the focused display first, values passed as arguments", () => {
  assert.deepEqual(logic.scaleCommand("eDP-1", "2"), [
    "bash",
    "-c",
    '[ "$(hyprctl monitors -j | jq -r ".[]|select(.focused).name")" = "$1" ] && exec omarchy-hyprland-monitor-scaling "$2"',
    "_",
    "eDP-1",
    "2"
  ])
})

test("scaleCommand: hostile values stay single arguments, never spliced into the script", () => {
  const argv = logic.scaleCommand('x"; rm -rf ~; "', "2; reboot")
  assert.equal(argv[2].indexOf("rm"), -1)
  assert.equal(argv[2].indexOf("reboot"), -1)
  assert.deepEqual(argv.slice(3), ["_", 'x"; rm -rf ~; "', "2; reboot"])
})

test("scaleCommand: no display or no scale gives no command", () => {
  assert.equal(logic.scaleCommand("", "2"), null)
  assert.equal(logic.scaleCommand("eDP-1", ""), null)
  assert.equal(logic.scaleCommand(undefined, undefined), null)
})

// --- nextAction (C2: what runs when the scale/display command exits) ---------------
//
// Display switches are never queued (see displaysLocked); only a scale is.

const idleState = (over) =>
  Object.assign(
    {
      done: null,
      exitCode: 0,
      queuedScale: "",
      queuedScaleMonitor: "",
      pendingScale: "",
      pendingDisplays: {}
    },
    over
  )

test("nextAction: nothing queued runs nothing and keeps the pending state", () => {
  assert.deepEqual(
    logic.nextAction(idleState({ pendingScale: "2", done: { kind: "scale", key: "2" } })),
    {
      run: null,
      queuedScale: "",
      queuedScaleMonitor: "",
      pendingScale: "2",
      pendingDisplays: {}
    }
  )
})

test("nextAction: a failed display request drops its own pending entry", () => {
  const next = logic.nextAction(
    idleState({
      done: { kind: "display", key: "DP-2", enable: true },
      exitCode: 1,
      pendingDisplays: { "DP-2": true }
    })
  )
  assert.deepEqual(next.pendingDisplays, {})
  assert.equal(next.run, null)
})

test("nextAction: a failed display request leaves a pending entry that is no longer its own", () => {
  const next = logic.nextAction(
    idleState({
      done: { kind: "display", key: "DP-2", enable: true },
      exitCode: 1,
      pendingDisplays: { "DP-2": false }
    })
  )
  assert.deepEqual(next.pendingDisplays, { "DP-2": false })
})

test("nextAction: a successful display request keeps its pending entry for the re-read", () => {
  const next = logic.nextAction(
    idleState({
      done: { kind: "display", key: "DP-2", enable: true },
      pendingDisplays: { "DP-2": true }
    })
  )
  assert.deepEqual(next.pendingDisplays, { "DP-2": true })
  assert.equal(next.run, null)
})

test("nextAction: a failed scale drops its pending scale, a later one stays", () => {
  assert.equal(
    logic.nextAction(
      idleState({ done: { kind: "scale", key: "2" }, exitCode: 1, pendingScale: "2" })
    ).pendingScale,
    ""
  )
  assert.equal(
    logic.nextAction(
      idleState({ done: { kind: "scale", key: "2" }, exitCode: 1, pendingScale: "3" })
    ).pendingScale,
    "3"
  )
})

test("nextAction: a queued scale runs on the display it was chosen on", () => {
  const next = logic.nextAction(
    idleState({
      done: { kind: "scale", key: "2" },
      queuedScale: "3",
      queuedScaleMonitor: "eDP-1",
      pendingScale: "3"
    })
  )
  assert.deepEqual(next.run, { kind: "scale", key: "3", monitor: "eDP-1" })
  assert.equal(next.queuedScale, "")
  assert.equal(next.queuedScaleMonitor, "")
  assert.equal(next.pendingScale, "3")
})

test("nextAction: a scale queued behind a display command is dropped with its pending", () => {
  const next = logic.nextAction(
    idleState({
      done: { kind: "display", key: "DP-2", enable: true },
      queuedScale: "3",
      queuedScaleMonitor: "eDP-1",
      pendingScale: "3",
      pendingDisplays: { "DP-2": true }
    })
  )
  assert.equal(next.run, null)
  assert.equal(next.queuedScale, "")
  assert.equal(next.queuedScaleMonitor, "")
  assert.equal(next.pendingScale, "")
})

test("nextAction: a queued scale with no display recorded is dropped", () => {
  const next = logic.nextAction(
    idleState({ done: { kind: "scale", key: "2" }, queuedScale: "3", pendingScale: "3" })
  )
  assert.equal(next.run, null)
  assert.equal(next.pendingScale, "")
})

test("nextAction: missing state never throws", () => {
  assert.deepEqual(logic.nextAction(undefined), {
    run: null,
    queuedScale: "",
    queuedScaleMonitor: "",
    pendingScale: "",
    pendingDisplays: {}
  })
})

test("nextAction: never mutates the map it is given", () => {
  const state = idleState({
    done: { kind: "display", key: "DP-2", enable: true },
    exitCode: 1,
    pendingDisplays: { "DP-2": true }
  })
  logic.nextAction(state)
  assert.deepEqual(state.pendingDisplays, { "DP-2": true })
})

// --- displaysLocked / mayToggleDisplay (no display switch behind a stale read) --------

test("displaysLocked: locked while a command runs", () => {
  assert.equal(logic.displaysLocked({ running: true, exitSerial: 0, landedSerial: 0 }), true)
})

test("displaysLocked: locked after a display command exits until a read started after it lands", () => {
  assert.equal(logic.displaysLocked({ running: false, exitSerial: 3, landedSerial: 2 }), true)
  assert.equal(logic.displaysLocked({ running: false, exitSerial: 3, landedSerial: 3 }), false)
  assert.equal(logic.displaysLocked({ running: false, exitSerial: 3, landedSerial: 4 }), false)
})

test("displaysLocked: unlocked from the start, and missing state never throws", () => {
  assert.equal(logic.displaysLocked({ running: false, exitSerial: 0, landedSerial: -1 }), false)
  assert.equal(logic.displaysLocked(undefined), false)
})

test("mayToggleDisplay: refused while locked, enable or disable", () => {
  const base = { locked: true, enabledMap: { A: true, B: true }, pendingMap: {} }
  assert.equal(logic.mayToggleDisplay(Object.assign({ name: "A", enable: true }, base)), false)
  assert.equal(logic.mayToggleDisplay(Object.assign({ name: "A", enable: false }, base)), false)
})

test("mayToggleDisplay: unlocked, an enable is allowed and a disable needs mayDisable", () => {
  assert.equal(
    logic.mayToggleDisplay({
      name: "B",
      enable: true,
      locked: false,
      enabledMap: { A: true, B: false },
      pendingMap: {}
    }),
    true
  )
  assert.equal(
    logic.mayToggleDisplay({
      name: "A",
      enable: false,
      locked: false,
      enabledMap: { A: true, B: true },
      pendingMap: {}
    }),
    true
  )
  assert.equal(
    logic.mayToggleDisplay({
      name: "A",
      enable: false,
      locked: false,
      enabledMap: { A: true, B: false },
      pendingMap: {}
    }),
    false
  )
})

test("mayToggleDisplay: no name, or missing state, is refused", () => {
  assert.equal(logic.mayToggleDisplay({ name: "", enable: true, locked: false }), false)
  assert.equal(logic.mayToggleDisplay(undefined), false)
})

test("mayDisable: a display with any pending entry is not confirmed (the stale-read repro, step 4)", () => {
  assert.equal(logic.mayDisable("B", { A: true, B: true }, { A: true }), false)
})

// The re-review's repro, played through the pure rules the panel follows: A and
// B read on; disable A (in flight); re-enable A; disable B; A's disable exits 0;
// the enable of A would fail. Every step after the first is refused, so a
// display always stays on.
test("the stale-read repro now leaves A or B on", () => {
  let enabledMap = { A: true, B: true }
  let pendingMap = {}
  let running = false
  let exitSerial = 0
  let landedSerial = -1
  let actionSerial = 0
  const locked = () => logic.displaysLocked({ running, exitSerial, landedSerial })
  const request = (name, enable) => {
    if (!logic.mayToggleDisplay({ name, enable, locked: locked(), enabledMap, pendingMap }))
      return false
    pendingMap = Object.assign({}, pendingMap, { [name]: enable })
    running = true
    return { kind: "display", key: name, enable }
  }
  const exit = (done, code) => {
    running = false
    actionSerial++
    exitSerial = actionSerial
    pendingMap = logic.nextAction({
      done,
      exitCode: code,
      pendingDisplays: pendingMap
    }).pendingDisplays
  }

  // 1-2. Disable A: allowed, now in flight.
  const disableA = request("A", false)
  assert.ok(disableA, "disabling A is allowed while B is confirmed on")
  // 3. Re-enable A while its disable is in flight: refused, nothing queued.
  assert.equal(request("A", true), false, "re-enabling A is refused while a command runs")
  // 4. Disable B: refused.
  assert.equal(request("B", false), false, "disabling B is refused while a command runs")
  // 5. A's disable exits 0; the read is now stale.
  exit(disableA, 0)
  assert.equal(locked(), true, "still locked until a fresh read lands")
  assert.equal(request("A", true), false, "re-enabling A waits for the fresh read")
  assert.equal(request("B", false), false, "and so does disabling B")
  // 6. A fresh read lands: A off, B on; the confirmed request settles.
  enabledMap = { A: false, B: true }
  landedSerial = actionSerial
  pendingMap = {}
  assert.equal(locked(), false, "the fresh read unlocks the switches")
  assert.equal(request("B", false), false, "B is now the last display and cannot be disabled")
  assert.equal(logic.lastEnabledName(enabledMap, pendingMap), "B")
  // The re-enable of A runs now and fails: B was never touched.
  const enableA = request("A", true)
  assert.ok(enableA, "re-enabling A is allowed again")
  assert.equal(request("B", false), false, "B cannot be disabled while A is only pending on")
  exit(enableA, 1)
  assert.deepEqual(pendingMap, {}, "the failed enable drops its own pending entry")
  assert.equal(request("B", false), false, "nor before the read after the failure lands")
  landedSerial = actionSerial
  assert.equal(request("B", false), false, "nor after it: A is off")
  const on = Object.keys(enabledMap).filter((n) => enabledMap[n])
  assert.deepEqual(on, ["B"], "a display stays on")
})

// --- nightToggleTarget (the state omarchy-toggle-nightlight will leave) -------------
//
// The script sets 4000 K only from no temperature or exactly 6500 K; from any
// other temperature (4000 K, or an odd one such as 6200 K that --status already
// reads as off) it sets 6500 K, i.e. off.

test("nightToggleTarget: off at 6500 K, or with no temperature, turns on", () => {
  assert.equal(logic.nightToggleTarget({ enabled: false, temperature: 6500 }), true)
  assert.equal(logic.nightToggleTarget({ enabled: false, temperature: null }), true)
})

test("nightToggleTarget: on turns off", () => {
  assert.equal(logic.nightToggleTarget({ enabled: true, temperature: 4000 }), false)
  assert.equal(logic.nightToggleTarget({ enabled: true, temperature: 5000 }), false)
})

test("nightToggleTarget: an odd temperature (6000-6499 K) is treated as off: the script sets 6500 K", () => {
  assert.equal(logic.nightToggleTarget({ enabled: false, temperature: 6000 }), false)
  assert.equal(logic.nightToggleTarget({ enabled: false, temperature: 6200 }), false)
  assert.equal(logic.nightToggleTarget({ enabled: false, temperature: 6499 }), false)
})

test("nightToggleTarget: missing state predicts on (no temperature) without throwing", () => {
  assert.equal(logic.nightToggleTarget(undefined), true)
  assert.equal(logic.nightToggleTarget(null), true)
})

// --- keyHint with the keyboard light mode ------------------------------------------

test("keyHint: the keyboard light switch toggles with enter", () => {
  assert.equal(logic.keyHint("kbdlight", "switch"), "↑↓ move · enter toggle")
})

test("keyHint: the keyboard light slider adjusts with the arrow keys", () => {
  assert.equal(logic.keyHint("kbdlight", "slider"), "↑↓ move · ←→ adjust")
})

// --- scaleCaption -----------------------------------------------------------------

test("scaleCaption: a scale no preset matches reads custom", () => {
  assert.equal(logic.scaleCaption("", "", "2.67"), "2.67× · custom")
  assert.equal(logic.scaleCaption("", "", "1.500"), "1.5× · custom")
})

test("scaleCaption: nothing while a preset matches or one is pending", () => {
  assert.equal(logic.scaleCaption("2", "", "2"), "")
  assert.equal(logic.scaleCaption("", "3", "2.67"), "")
})

test("scaleCaption: nothing with no scale read", () => {
  assert.equal(logic.scaleCaption("", "", ""), "")
  assert.equal(logic.scaleCaption(undefined, undefined, undefined), "")
})

test("displaysLocked: after a display command, an unknown landed read counts as stale", () => {
  assert.equal(logic.displaysLocked({ running: false, exitSerial: 2 }), true)
})

// --- displayCommand (hyprctl keyword is rejected under the Lua config) ---------------

test("displayCommand: a disable is an hl.monitor eval with disabled = true", () => {
  assert.deepEqual(logic.displayCommand("DP-2", false), [
    "hyprctl",
    "eval",
    'hl.monitor({ output = "DP-2", disabled = true })'
  ])
})

test("displayCommand: an enable keeps stock's preferred/auto/auto", () => {
  assert.deepEqual(logic.displayCommand("HDMI-A-1", true), [
    "hyprctl",
    "eval",
    'hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = "auto" })'
  ])
})

test("displayCommand: plain monitor names with dots, underscores and dashes are accepted", () => {
  assert.ok(logic.displayCommand("eDP-1", true))
  assert.ok(logic.displayCommand("Virtual.1_x", false))
})

test("displayCommand: a hostile name is refused, never spliced into the Lua", () => {
  assert.equal(logic.displayCommand('DP-2"', false), null)
  assert.equal(logic.displayCommand("DP-2)", false), null)
  assert.equal(logic.displayCommand('DP-2", disabled = true }) os.execute("x', true), null)
  assert.equal(logic.displayCommand("DP\n2", false), null)
  assert.equal(logic.displayCommand("DP 2", true), null)
})

test("displayCommand: an empty or missing name is refused", () => {
  assert.equal(logic.displayCommand("", true), null)
  assert.equal(logic.displayCommand(undefined, false), null)
})

// --- settleDisplayPending (keep a request until a read shows it, up to 3 reads) ------

test("settleDisplayPending: a read that shows the requested state drops the request", () => {
  assert.deepEqual(
    logic.settleDisplayPending({
      pending: { "DP-2": true },
      exits: { "DP-2": 4 },
      reads: { "DP-2": 1 },
      enabledMap: { "DP-2": true },
      readSerial: 4
    }),
    { pending: {}, exits: {}, reads: {} }
  )
})

test("settleDisplayPending: a fresh read that doesn't show it yet keeps the request and counts", () => {
  assert.deepEqual(
    logic.settleDisplayPending({
      pending: { "DP-2": true },
      exits: { "DP-2": 4 },
      reads: {},
      enabledMap: { "DP-2": false },
      readSerial: 4
    }),
    { pending: { "DP-2": true }, exits: { "DP-2": 4 }, reads: { "DP-2": 1 } }
  )
})

test("settleDisplayPending: the third fresh read without it drops the request", () => {
  let state = { pending: { "DP-2": true }, exits: { "DP-2": 4 }, reads: {} }
  for (let i = 0; i < 2; i++) {
    state = logic.settleDisplayPending(
      Object.assign({ enabledMap: { "DP-2": false }, readSerial: 4 }, state)
    )
    assert.deepEqual(state.pending, { "DP-2": true }, "kept after fresh read " + (i + 1))
  }
  state = logic.settleDisplayPending(
    Object.assign({ enabledMap: { "DP-2": false }, readSerial: 5 }, state)
  )
  assert.deepEqual(state, { pending: {}, exits: {}, reads: {} })
})

test("settleDisplayPending: a read that started before the exit, or while it runs, is not counted", () => {
  const stale = {
    pending: { "DP-2": true },
    exits: { "DP-2": 4 },
    reads: {},
    enabledMap: {},
    readSerial: 3
  }
  assert.deepEqual(logic.settleDisplayPending(stale), {
    pending: { "DP-2": true },
    exits: { "DP-2": 4 },
    reads: {}
  })
  const running = {
    pending: { "DP-2": false },
    exits: {},
    reads: {},
    enabledMap: { "DP-2": true },
    readSerial: 9
  }
  assert.deepEqual(logic.settleDisplayPending(running), {
    pending: { "DP-2": false },
    exits: {},
    reads: {}
  })
})

test("settleDisplayPending: bookkeeping for a request no longer pending is dropped", () => {
  assert.deepEqual(
    logic.settleDisplayPending({
      pending: {},
      exits: { "DP-2": 4 },
      reads: { "DP-2": 2 },
      enabledMap: {},
      readSerial: 5
    }),
    { pending: {}, exits: {}, reads: {} }
  )
})

test("settleDisplayPending: missing state never throws", () => {
  assert.deepEqual(logic.settleDisplayPending(undefined), { pending: {}, exits: {}, reads: {} })
})

// --- displaysLocked on open --------------------------------------------------------

test("displaysLocked: after an open, locked until a read started since the open lands", () => {
  assert.equal(
    logic.displaysLocked({
      running: false,
      exitSerial: 0,
      landedSerial: 0,
      openMark: 5,
      landedRead: 5
    }),
    true
  )
  assert.equal(
    logic.displaysLocked({
      running: false,
      exitSerial: 0,
      landedSerial: 0,
      openMark: 5,
      landedRead: 6
    }),
    false
  )
})

test("displaysLocked: an unknown landed read after an open counts as stale", () => {
  assert.equal(logic.displaysLocked({ running: false, exitSerial: 0, openMark: 0 }), true)
})

// --- startDisplayRequest (a re-toggle gets its full settle window) ---------------

test("startDisplayRequest: clears the display's read count and stale exit, keeps the others", () => {
  assert.deepEqual(
    logic.startDisplayRequest(
      { exits: { "DP-2": 4, "DP-3": 2 }, reads: { "DP-2": 2, "DP-3": 1 } },
      "DP-2"
    ),
    { exits: { "DP-3": 2 }, reads: { "DP-3": 1 } }
  )
})

test("startDisplayRequest: missing state never throws, and never mutates its input", () => {
  assert.deepEqual(logic.startDisplayRequest(undefined, "DP-2"), { exits: {}, reads: {} })
  const state = { exits: { "DP-2": 4 }, reads: { "DP-2": 2 } }
  logic.startDisplayRequest(state, "DP-2")
  assert.deepEqual(state, { exits: { "DP-2": 4 }, reads: { "DP-2": 2 } })
})

test("a re-toggle while the previous request is still settling gets its own 3 fresh reads", () => {
  const read = (state, enabledMap, readSerial) =>
    logic.settleDisplayPending(Object.assign({ enabledMap, readSerial }, state))
  // First request: switch DP-2 on, exits at 4; two fresh reads don't show it yet.
  let state = { pending: { "DP-2": true }, exits: { "DP-2": 4 }, reads: {} }
  state = read(state, { "DP-2": false }, 4)
  state = read(state, { "DP-2": false }, 4)
  assert.deepEqual(state.reads, { "DP-2": 2 })
  // Re-toggle DP-2 off: a new command starts, then exits at 6.
  const fresh = logic.startDisplayRequest(state, "DP-2")
  state = { pending: { "DP-2": false }, exits: fresh.exits, reads: fresh.reads }
  state = read(state, { "DP-2": true }, 5)
  assert.deepEqual(state.pending, { "DP-2": false }, "a read while it runs does not count")
  state.exits = Object.assign({}, state.exits, { "DP-2": 6 })
  for (let i = 1; i <= 2; i++) {
    state = read(state, { "DP-2": true }, 6)
    assert.deepEqual(state.pending, { "DP-2": false }, "kept after its own fresh read " + i)
  }
  state = read(state, { "DP-2": true }, 6)
  assert.deepEqual(state.pending, {}, "dropped on its own third fresh read")
})
