/**
 * Clamps value to an integer brightness percent, 1-100 (0 reads as "off" to
 * some backlights, so the floor is 1).
 * @param {*} value - the candidate brightness
 * @returns {number} the clamped percent, 1 for non-finite input
 */
function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

/**
 * Normalizes a scale value to a string with at most two decimal places
 * (e.g. 1.2000000000000002 -> "1.2"), so scales compare as text.
 * @param {*} scale - the candidate scale
 * @returns {string} the normalized scale, "" for non-finite input
 */
function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

/**
 * The greatest common divisor of a and b (Euclid's algorithm).
 * @param {number} a - the first integer
 * @param {number} b - the second integer
 * @returns {number} their greatest common divisor
 */
function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

/**
 * The scale a requested preset actually resolves to on a display mode: the
 * nearest scale, at 1/120th steps, whose logical size divides the mode's
 * width/height evenly (avoids the sub-pixel rounding Hyprland otherwise
 * introduces).
 * @param {*} scale - the requested scale
 * @param {*} width - the display mode's width, px
 * @param {*} height - the display mode's height, px
 * @returns {string} the effective scale, normalized; "" when any input is
 *   not a positive finite number
 */
function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (
    !isFinite(requested) ||
    !isFinite(modeWidth) ||
    !isFinite(modeHeight) ||
    requested <= 0 ||
    modeWidth <= 0 ||
    modeHeight <= 0
  )
    return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

/**
 * The index into scales whose effective scale (cleanScale) matches
 * currentScale, breaking ties by whichever requested value is closest to
 * currentScale.
 * @param {*} scales - the candidate scale presets
 * @param {*} currentScale - the display's current scale
 * @param {*} width - the display mode's width, px
 * @param {*} height - the display mode's height, px
 * @returns {number} the matching index, or -1 with no match
 */
function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

/**
 * The scale presets whose effective (cleanScale) values are distinct on this
 * display mode, each reduced to whichever requested preset lands closest to
 * its own effective value, in scales' original order.
 * @param {*} scales - the candidate scale presets
 * @param {*} width - the display mode's width, px
 * @param {*} height - the display mode's height, px
 * @returns {Array<*>} the deduplicated presets; scales (or []) unchanged
 *   when width/height aren't positive
 */
function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  /** @type {{[key: string]: {value: string, index: number, distance: number}}} */
  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function (key) {
      return byEffectiveScale[key]
    })
    .sort(function (a, b) {
      return a.index - b.index
    })
    .map(function (candidate) {
      return candidate.value
    })
}

/**
 * Playful mood-name for a brightness percent, lowest to highest.
 * @param {*} percent - the brightness percent
 * @returns {string} the mood name
 */
function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

/**
 * Parses `omarchy-monitor-state`'s displays JSON into the display list and
 * how many entries are enabled. Invalid input (bad JSON, not an array)
 * gives an empty list.
 * @param {*} raw - the raw displays JSON, or falsy
 * @returns {{displays: Array<*>, enabledDisplayCount: number}} the parsed
 *   displays and enabled count
 */
function parseDisplays(raw) {
  var displays
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    brightnessName: brightnessName,
    parseDisplays: parseDisplays
  }
}
