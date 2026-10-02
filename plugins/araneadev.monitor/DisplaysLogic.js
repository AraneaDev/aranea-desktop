// Pure rules for the Aranea Displays dropdown (Panel.qml): parsing
// `omarchy-toggle-nightlight --status` and its on/off caption, finding and
// parsing the keyboard backlight device from `/sys/class/leds` and
// `brightnessctl -d <device> -m`, the command a keyboard-light change runs,
// which sections the dropdown shows and the keyboard order through them,
// the header caption (`Model.cleanScale`'s companion), the pending/queue
// helpers (araneadev.power's `PowerLogic` pattern) and the keyboard hint. No
// QML, no I/O; tests/js/displays-logic.test.js runs this under Node.

/**
 * The night light's parsed status, from `omarchy-toggle-nightlight
 * --status`'s JSON (`{enabled, temperature}`).
 * @typedef {{available: boolean, enabled: boolean, temperature: number|null}} NightlightState
 */

/**
 * The keyboard backlight's parsed state, from `brightnessctl -d <device>
 * -m`'s one-line reply (`name,class,current,percent,max`).
 * @typedef {{device: string, current: number, max: number}} KbdLight
 */

/**
 * A display's identity and mode, as `omarchy-monitor-state`'s displays JSON
 * carries it (only the fields `headerCaption` needs).
 * @typedef {{name?: string, width?: number, height?: number}} Display
 */

/**
 * Parses `omarchy-toggle-nightlight --status`'s JSON reply, e.g.
 * `{"enabled":false,"temperature":null}`. `temperature` is `null` while
 * hyprsunset isn't running. Invalid input (bad JSON, not an object, or no
 * boolean `enabled`) gives `available: false` rather than throwing.
 * @param {string|undefined} json - the command's stdout
 * @returns {NightlightState} the parsed status
 */
function parseNightlight(json) {
  var parsed
  try {
    parsed = JSON.parse(String(json))
  } catch (e) {
    return { available: false, enabled: false, temperature: null }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return { available: false, enabled: false, temperature: null }
  if (typeof parsed.enabled !== "boolean")
    return { available: false, enabled: false, temperature: null }
  var temperature =
    typeof parsed.temperature === "number" && isFinite(parsed.temperature)
      ? parsed.temperature
      : null
  return { available: true, enabled: parsed.enabled, temperature: temperature }
}

/**
 * The night light row's caption: the temperature while it is on, else "Off"
 * (also "Off" while unavailable, or on with no temperature yet).
 * @param {{enabled?: boolean, temperature?: number|null}|null|undefined} state - from `parseNightlight`
 * @returns {string} "<temperature> K" or "Off"
 */
function nightlightCaption(state) {
  var s = state || {}
  if (s.enabled && typeof s.temperature === "number" && isFinite(s.temperature))
    return s.temperature + " K"
  return "Off"
}

/**
 * The first `*kbd_backlight*` entry in a newline list of `/sys/class/leds`
 * names (as `ls /sys/class/leds` prints them, one per line).
 * @param {string|undefined} lsOutput - `ls /sys/class/leds`'s stdout
 * @returns {string} the device name, or "" when there is none
 */
function kbdDevice(lsOutput) {
  var lines = String(lsOutput || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var name = lines[i].trim()
    if (name !== "" && name.indexOf("kbd_backlight") !== -1) return name
  }
  return ""
}

/**
 * Parses `brightnessctl -d <device> -m`'s one-line reply:
 * `name,class,current,percent,max`, e.g.
 * `platform::kbd_backlight,leds,1,100%,1`. Invalid input (too few fields, no
 * device name, or a non-finite current/max) gives `max: 0` rather than
 * throwing.
 * @param {string|undefined} text - the command's stdout
 * @returns {KbdLight} the parsed state
 */
function parseKbdLight(text) {
  var parts = String(text || "")
    .trim()
    .split(",")
  var device = parts[0] || ""
  var current = Number(parts[2])
  var max = Number(parts[4])
  if (parts.length < 5 || !device || !isFinite(current) || !isFinite(max))
    return { device: "", current: 0, max: 0 }
  return { device: device, current: current, max: max }
}

/**
 * The command a keyboard-light change runs: the stock off-switch script
 * when the device is a plain on/off switch (`max === 1`) being turned off,
 * else `brightnessctl` set to the value, clamped to `[0, max]`.
 * @param {string} device - the backlight device name
 * @param {number} value - the requested level
 * @param {number} max - the device's maximum level, from `parseKbdLight`
 * @returns {string[]} the argv to run
 */
function kbdCommand(device, value, max) {
  var dev = String(device || "")
  var m = Number(max)
  if (!isFinite(m) || m < 0) m = 0
  var v = Number(value)
  if (!isFinite(v)) v = 0
  v = Math.round(v)
  if (v < 0) v = 0
  if (v > m) v = m
  if (m === 1 && v === 0) return ["omarchy-brightness-keyboard", "off"]
  return ["brightnessctl", "-sd", dev, "set", String(v)]
}

/**
 * Which control the keyboard-light row shows: a switch for a plain on/off
 * device (`max === 1`), a slider for a stepped one (`max > 1`), or none
 * with no device (`max <= 0`).
 * @param {number} max - the device's maximum level, from `parseKbdLight`
 * @returns {"switch"|"slider"|"none"} the control kind
 */
function kbdMode(max) {
  var m = Number(max)
  if (!isFinite(m) || m <= 0) return "none"
  if (m === 1) return "switch"
  return "slider"
}

/**
 * The dropdown's visible sections, in keyboard order: brightness, night
 * light, keyboard light, text size, scale, then monitors. Brightness, night
 * light and keyboard light are included only when available; text size and
 * scale are always shown; monitors only when there is more than one
 * display (stock's rule).
 * @param {{brightness?: boolean, nightlight?: boolean, kbd?: boolean, displayCount?: number}|null|undefined} s
 * @returns {string[]} the section keys, in order
 */
function sectionsFor(s) {
  var opts = s || {}
  var sections = []
  if (opts.brightness) sections.push("brightness")
  if (opts.nightlight) sections.push("nightlight")
  if (opts.kbd) sections.push("kbdlight")
  sections.push("textsize")
  sections.push("scale")
  if (Number(opts.displayCount) > 1) sections.push("monitors")
  return sections
}

/**
 * Moves the section cursor by `dy` steps through `sections`, clamped to the
 * ends with no wrap. A `current` not in the list starts from its front.
 * @param {string[]|null|undefined} sections - from `sectionsFor`, in order
 * @param {string|null|undefined} current - the cursor's section
 * @param {number} dy - the step, usually -1 or 1
 * @returns {string} the section the cursor lands on, "" with no sections
 */
function moveSection(sections, current, dy) {
  var list = Array.isArray(sections) ? sections : []
  if (list.length === 0) return ""
  var idx = list.indexOf(current)
  if (idx === -1) idx = 0
  var step = Math.trunc(Number(dy))
  if (!isFinite(step)) step = 0
  var next = idx + step
  if (next < 0) next = 0
  if (next > list.length - 1) next = list.length - 1
  return list[next]
}

/**
 * Trims a decimal scale string's trailing zeros (and a bare trailing
 * point), so `cleanScale`-shaped values like "2.00" or "2.670" render as
 * "2" or "2.67".
 * @param {string} scale - the cleaned scale string
 * @returns {string} the trimmed string
 */
function trimScale(scale) {
  var s = String(scale)
  if (s.indexOf(".") === -1) return s
  return s.replace(/0+$/, "").replace(/\.$/, "")
}

/**
 * The header caption: the display's name, its resolution (as
 * `<width>×<height>`) and its effective scale (as `<scale>×`,
 * trailing zeros trimmed), joined with " · ". A missing part (no name,
 * no finite width/height, or no scale) is left out rather than shown blank.
 * @param {Display|null|undefined} display - the focused display
 * @param {string|null|undefined} scale - the already-`Model.cleanScale`d scale string
 * @returns {string} the caption, e.g. "eDP-1 · 3840×2160 · 2.67×"
 */
function headerCaption(display, scale) {
  var d = display || {}
  var parts = []
  if (d.name) parts.push(String(d.name))
  var width = Number(d.width)
  var height = Number(d.height)
  if (isFinite(width) && isFinite(height)) parts.push(width + "×" + height)
  var trimmed = scale ? trimScale(scale) : ""
  if (trimmed) parts.push(trimmed + "×")
  return parts.join(" · ")
}

/**
 * Whether a freshly read actual value confirms a pending request: once it
 * matches, the request is settled and dropped (and its busy pulse with
 * it); a request a refresh hasn't caught up to yet, or none at all, is
 * unchanged. Mirrors `araneadev.power`'s `PowerLogic.settlePending`.
 * @param {string|null|undefined} pending - requested but unconfirmed, "" for none
 * @param {string|null|undefined} actual - the freshly read value
 * @returns {string} the pending value to keep, "" once it is confirmed
 */
function settlePending(pending, actual) {
  var p = pending || ""
  if (p !== "" && p === actual) return ""
  return p
}

/**
 * The last-wins run-queue helper, mirroring `araneadev.power`'s
 * `actionProc.onExited` pattern: while a command is running, a newly
 * queued request is only held (not run); once nothing is running, the
 * queued request (if any) is what runs next and the queue is drained. Call
 * it both when a new request arrives (with the request as `queued`, and
 * `running` set from the action process) and when the process exits (with
 * `running: false` and the queue so far), so one pure rule covers both
 * call sites.
 * @param {{running?: boolean, queued?: string}|null|undefined} state
 * @returns {{run: string, queue: string}} what to run now ("" for nothing) and what stays queued
 */
function takeQueued(state) {
  var s = state || {}
  var queued = s.queued || ""
  if (s.running) return { run: "", queue: queued }
  return { run: queued, queue: "" }
}

/**
 * The key-hint line for the cursor's section.
 * @param {string|undefined} section - the cursor's section
 * @returns {string} the hint
 */
function keyHint(section) {
  if (section === "nightlight" || section === "monitors") return "↑↓ move · enter toggle · tab next"
  if (section === "scale") return "↑↓ move · ←→ pick · tab next"
  if (section === "brightness" || section === "kbdlight" || section === "textsize")
    return "↑↓ move · ←→ adjust · tab next"
  return "esc close · tab next"
}

if (typeof module !== "undefined")
  module.exports = {
    parseNightlight: parseNightlight,
    nightlightCaption: nightlightCaption,
    kbdDevice: kbdDevice,
    parseKbdLight: parseKbdLight,
    kbdCommand: kbdCommand,
    kbdMode: kbdMode,
    sectionsFor: sectionsFor,
    moveSection: moveSection,
    headerCaption: headerCaption,
    settlePending: settlePending,
    takeQueued: takeQueued,
    keyHint: keyHint
  }
