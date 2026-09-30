// Pure state rules for the Aranea OSD (Osd.qml): map an icon name to a Nerd
// Font glyph and turn the raw strings of an `osd show` request into display
// state. No QML, no I/O; tests/osd.test.sh runs this under Node.

/**
 * Display state for one OSD request (stateForShow).
 * @typedef {object} OsdState
 * @property {number} maxValue - progress maximum, at least 1
 * @property {boolean} hasProgress - a numeric value was given and no message
 * @property {number} value - progress value clamped to 0..maxValue (0 without progress)
 * @property {string} message - the message, else the progress text or "<percent>%"
 * @property {string} icon - glyph from iconFor
 * @property {number} duration - ms before the OSD hides; 0 keeps it open
 */

/**
 * Limits a number to a range.
 * @param {number} value - number to limit
 * @param {number} min - lower bound
 * @param {number} max - upper bound
 * @returns {number} value clamped to min..max
 */
function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

/**
 * Picks the OSD glyph for an icon name. Known names map to Nerd Font glyphs,
 * any other non-empty name is used as the glyph itself, and an empty name
 * gets a volume glyph chosen by percent.
 * @param {string} name - icon name, matched case-insensitively
 * @param {number} percent - progress percent, -1 without progress
 * @returns {string} the glyph
 */
function iconFor(name, percent) {
  var n = String(name || "").toLowerCase()
  if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return ""
  if (n === "volume-low") return ""
  if (n === "volume-medium") return ""
  if (n === "volume-high" || n === "volume") return ""
  if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off")
    return "󰍭"
  if (n === "microphone" || n === "mic") return "󰍬"
  if (n === "keyboard") return "󰌌"
  if (n === "brightness" || n === "display") return "󰍹"
  if (n === "touchpad") return "󰟸"
  if (n === "touch" || n === "touchscreen") return "󰝁"
  if (n === "reboot" || n === "restart") return "󰜉"
  if (n === "shutdown" || n === "power" || n === "poweroff") return "󰐥"
  if (n === "logout" || n === "sign-out" || n === "leave") return "󰍃"
  if (n === "media" || n === "player") return "󰝚"
  if (n === "media-source" || n === "player-source") return "󰝚"
  if (n === "media-play" || n === "player-play") return "󰐊"
  if (n === "media-pause" || n === "player-pause") return "󰏤"
  if (n === "media-next" || n === "player-next") return "󰒭"
  if (n === "media-previous" || n === "player-previous") return "󰒮"
  if (n.length > 0) return name
  if (percent <= 0) return ""
  if (percent <= 33) return ""
  if (percent <= 66) return ""
  return ""
}

// Canonical icon names, one per distinct glyph iconFor can return; alias
// names that resolve to the same glyph (e.g. "restart" for "reboot") are
// left out. Used by allIconGlyphs to size the OSD's icon column to the
// widest glyph it can show.
var iconNames = [
  "volume-muted",
  "volume-low",
  "volume-medium",
  "volume-high",
  "microphone-muted",
  "microphone",
  "keyboard",
  "brightness",
  "touchpad",
  "touch",
  "reboot",
  "shutdown",
  "logout",
  "media",
  "media-play",
  "media-pause",
  "media-next",
  "media-previous"
]

// Glyphs shown by the OSD that do not come through iconFor's name mapping:
// a caller can pass a glyph straight through `-i` (iconFor returns `name`
// unchanged for any name it does not recognize). /usr/bin/omarchy-chromium-ytdlp-host
// does this (`omarchy-osd -i <glyph> -p ...`) with the download glyph
// U+F01DA, so the icon column's fixed width must cover it too.
var extraIconGlyphs = [String.fromCodePoint(0xf01da)]

/**
 * Every glyph the OSD can show: one call to iconFor per name in iconNames,
 * plus extraIconGlyphs (glyphs passed straight through by name, not mapped
 * by iconFor). The percent-only fallback glyphs (no icon name given) reuse
 * the volume-* glyphs, so they need no separate entries here.
 * @returns {string[]} the glyphs
 */
function allIconGlyphs() {
  return iconNames
    .map(function (name) {
      return iconFor(name, -1)
    })
    .concat(extraIconGlyphs)
}

/**
 * Widest ink width among a list of glyphs, at whatever font `measure`
 * applies. Pure: QML supplies `measure` (typically a TextMetrics probe),
 * this function only loops and compares, so it is unit-testable without a
 * QML engine.
 * @param {string[]} glyphs - glyphs to measure
 * @param {(glyph: string) => number} measure - a glyph's ink width
 * @returns {number} the widest ink width, 0 for an empty glyph list
 */
function maxInkWidth(glyphs, measure) {
  var max = 0
  for (var i = 0; i < glyphs.length; i++) {
    max = Math.max(max, measure(glyphs[i]))
  }
  return max
}

/**
 * OSD value column width: the wider of the fixed "100%" floor and the
 * current value text's ink, so a normal 0-100% value keeps the card's fixed
 * width and only an out-of-range value (e.g. "1000%" from
 * `omarchy osd -p 1000`, which /usr/bin/omarchy-osd builds unclamped from
 * the raw argument) widens the card instead of spilling past its padding.
 * @param {number} floorWidth - ink width of "100%" at the value font
 * @param {number} valueInkWidth - ink width of the current value text at the value font
 * @returns {number} the value column's width
 */
function valueColumnWidth(floorWidth, valueInkWidth) {
  return Math.max(floorWidth, valueInkWidth)
}

/**
 * Turns the raw strings of an OSD request into display state.
 * @param {string} iconName - icon name for iconFor
 * @param {string} rawMessage - message text; a non-empty message disables progress
 * @param {*} rawValue - progress value; undefined, null or "" for none
 * @param {*} rawMax - progress maximum; 100 when not a number
 * @param {string} rawProgressText - text shown instead of "<percent>%"
 * @param {string} rawDuration - display time in ms, "1200" when empty or not a number
 * @returns {OsdState} the state Osd.qml copies into its properties
 */
function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
  // A maximum that is not a number means 100; a missing value (undefined,
  // null or "") means no progress bar.
  var parsedMax = parseInt(rawMax, 10)
  var maxValue = isNaN(parsedMax) ? 100 : Math.max(1, parsedMax)
  var hasValue = rawValue !== undefined && rawValue !== null && String(rawValue) !== ""
  var parsedValue = hasValue ? parseInt(rawValue, 10) : NaN
  var messageText = String(rawMessage || "")
  var hasProgress = hasValue && !isNaN(parsedValue) && messageText === ""
  var value = hasProgress ? clamp(parsedValue, 0, maxValue) : 0
  var percent = hasProgress ? Math.round((value * 100) / maxValue) : -1
  var parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    maxValue: maxValue,
    hasProgress: hasProgress,
    value: value,
    message: messageText || (hasProgress ? rawProgressText || percent + "%" : ""),
    icon: iconFor(iconName, percent),
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
  }
}

/**
 * Computes how full the progress strand is.
 * @param {?{hasProgress: boolean, value: number, maxValue: number}} state - progress fields of an OsdState
 * @returns {number} value / maxValue clamped to 0..1, 0 without progress
 */
function progressFraction(state) {
  if (!state || !state.hasProgress || !state.maxValue) return 0
  return clamp(Number(state.value) / Number(state.maxValue), 0, 1)
}

if (typeof module !== "undefined") {
  module.exports = {
    iconFor,
    stateForShow,
    progressFraction,
    allIconGlyphs,
    maxInkWidth,
    valueColumnWidth
  }
}
