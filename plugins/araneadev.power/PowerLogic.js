// Pure rules for the Aranea Power dropdown (Panel.qml): the battery object
// path from `upower -e`, parsing busctl's UPower GetHistory reply into
// samples, turning those samples into the 24h chart's polyline segments and
// a first/now summary, formatting a sample's time as a clock label, parsing
// busctl's EnergyRate property, the stock detail-row and hero-status rules
// (from `/usr/share/omarchy/shell/plugins/panels/power/Panel.qml`'s InfoPair
// bindings and heroStatusText), and the keyboard hint. No QML, no I/O;
// tests/js/power-logic.test.js runs this under Node.

/**
 * One parsed history sample, from `parseHistory`.
 * @typedef {{t: number, pct: number, state: number}} HistorySample
 */

/**
 * One point on the history chart, in pixel space.
 * @typedef {{x: number, y: number}} ChartPoint
 */

/**
 * The battery device state and derived flags the detail rows and hero
 * status need, as the Panel.qml root computes them (`chargeThresholdActive`,
 * `discharging`, `batteryFlowIdle`, `batteryFull`, `fullyCharged`).
 * @typedef {{thresholdActive?: boolean, discharging?: boolean, flowIdle?: boolean, full?: boolean, fullyCharged?: boolean}} PowerState
 */

/**
 * The detail text `omarchy-battery-status --shell` provides, as `Panel.qml`
 * reads it off `batteryInfo`.
 * @typedef {{threshold?: string, time?: string, rate?: string, size?: string, cycles?: string}} BatteryInfo
 */

/**
 * The first `/battery_` device path in `upower -e`'s output (one object
 * path per line).
 * @param {string|undefined} text - `upower -e`'s stdout
 * @returns {string} the battery's object path, or "" when there is none
 */
function batteryPath(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("/battery_") !== -1) return lines[i]
  }
  return ""
}

/**
 * Parses busctl's `--json=short` reply to UPower's `GetHistory(type,
 * timespan, num_points)` method: `{"type":"a(udu)","data":[[[time, percent,
 * state], ...]]}`, one `[time, percent, state]` struct per history point,
 * newest first. Entries with `t <= 0` are dropped (UPower pads with zero
 * timestamps when there isn't enough history yet); a malformed entry (not an
 * array of at least 3 items) is skipped rather than thrown on. The result is
 * sorted oldest first.
 * @param {string|undefined} json - busctl's stdout
 * @returns {HistorySample[]} the samples, oldest first
 */
function parseHistory(json) {
  var parsed
  try {
    parsed = JSON.parse(String(json))
  } catch (e) {
    return []
  }
  var arr = parsed && Array.isArray(parsed.data) ? parsed.data[0] : null
  if (!Array.isArray(arr)) return []
  /** @type {HistorySample[]} */
  var out = []
  for (var i = 0; i < arr.length; i++) {
    var entry = arr[i]
    if (!Array.isArray(entry) || entry.length < 2) continue
    var t = Number(entry[0])
    if (!isFinite(t) || t <= 0) continue
    out.push({ t: t, pct: Number(entry[1]), state: entry[2] })
  }
  out.sort(function (a, b) {
    return a.t - b.t
  })
  return out
}

/**
 * Builds the 24h history chart's polyline segments over the window
 * `[nowSec-86400, nowSec]`. Samples after `nowSec` are dropped. A sample
 * before the window is clipped to a single start point at `x=0`, carrying
 * the last (most recent) such sample's percentage, as if it were sampled
 * exactly at the window's start (so a short gap to the first in-window
 * sample doesn't wrongly split the line). A new segment starts whenever two
 * consecutive points (after clipping) are more than 1800s apart, so one
 * sample alone gives a single, single-point segment.
 * @param {HistorySample[]|undefined} samples - from `parseHistory`
 * @param {number} nowSec - the current time, in epoch seconds
 * @param {number} width - the chart's pixel width
 * @param {number} height - the chart's pixel height
 * @returns {ChartPoint[][]} the polyline segments, oldest first within each
 */
function historyPoints(samples, nowSec, width, height) {
  var list = Array.isArray(samples) ? samples.slice() : []
  var windowStart = nowSec - 86400

  var valid = []
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (!s || typeof s.t !== "number" || !isFinite(s.t) || s.t > nowSec) continue
    valid.push(s)
  }
  valid.sort(function (a, b) {
    return a.t - b.t
  })

  var before = null
  var inWindow = []
  for (var j = 0; j < valid.length; j++) {
    var sample = valid[j]
    if (sample.t <= windowStart) {
      if (!before || sample.t > before.t) before = sample
    } else {
      inWindow.push(sample)
    }
  }

  /** @type {{t: number, pct: number}[]} */
  var points = []
  if (before) points.push({ t: windowStart, pct: before.pct })
  for (var k = 0; k < inWindow.length; k++) points.push({ t: inWindow[k].t, pct: inWindow[k].pct })

  if (points.length === 0) return []

  /** @type {ChartPoint[][]} */
  var segments = []
  /** @type {ChartPoint[]} */
  var current = []
  var prevT = null
  for (var p = 0; p < points.length; p++) {
    var point = points[p]
    if (prevT !== null && point.t - prevT > 1800) {
      segments.push(current)
      current = []
    }
    current.push({
      x: ((point.t - windowStart) * width) / 86400,
      y: height - (point.pct * height) / 100
    })
    prevT = point.t
  }
  segments.push(current)
  return segments
}

/**
 * The history caption's summary: the first sample's percentage (the oldest
 * one given, so the caller is expected to pass only the samples it wants
 * summarized) to the current percentage, both rounded.
 * @param {HistorySample[]|undefined} samples - oldest first
 * @param {number} nowPct - the current battery percentage
 * @returns {string} "" with no samples, else "<first>% -> <now>%"
 */
function historySummary(samples, nowPct) {
  if (!Array.isArray(samples) || samples.length === 0) return ""
  var first = Math.round(Number(samples[0].pct) || 0)
  var now = Math.round(Number(nowPct) || 0)
  return first + "% → " + now + "%"
}

/**
 * Zero-pads a number to (at least) two digits.
 * @param {number} n - the number
 * @returns {string} the padded text
 */
function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

/**
 * A sample's time as a clock label, in local time: "HH:MM", or "yesterday
 * HH:MM" when the sample falls on the calendar day before `nowSec`'s.
 * @param {number} sec - the sample's time, in epoch seconds
 * @param {number} nowSec - the current time, in epoch seconds
 * @returns {string} the label
 */
function timeLabel(sec, nowSec) {
  var t = Number(sec)
  var now = Number(nowSec)
  if (!isFinite(t)) t = 0
  if (!isFinite(now)) now = 0
  var d = new Date(t * 1000)
  var n = new Date(now * 1000)
  var label = pad2(d.getHours()) + ":" + pad2(d.getMinutes())

  var sameDay =
    d.getFullYear() === n.getFullYear() &&
    d.getMonth() === n.getMonth() &&
    d.getDate() === n.getDate()
  if (sameDay) return label

  var yesterday = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1)
  var isYesterday =
    d.getFullYear() === yesterday.getFullYear() &&
    d.getMonth() === yesterday.getMonth() &&
    d.getDate() === yesterday.getDate()
  return isYesterday ? "yesterday " + label : label
}

/**
 * Parses busctl's `--json=short` reply to a `get-property ... EnergyRate`
 * call: `{"type":"d","data":<number>}`. The rate is never shown negative
 * (UPower reports a negative EnergyRate while discharging on some systems).
 * @param {string|undefined} json - busctl's stdout
 * @returns {number} the rate in watts, or 0 on bad input or a negative value
 */
function parseEnergyRate(json) {
  var parsed
  try {
    parsed = JSON.parse(String(json))
  } catch (e) {
    return 0
  }
  var n = parsed ? Number(parsed.data) : NaN
  if (!isFinite(n) || n < 0) return 0
  return n
}

/**
 * The four detail rows, with stock's exact rules
 * (`/usr/share/omarchy/shell/plugins/panels/power/Panel.qml`'s InfoPair
 * bindings): row 1 is the time (or the charge limit while a threshold holds
 * the battery), row 2 the charge rate (or "Holding" while a threshold
 * holds), then the static battery size and cycle count.
 * @param {BatteryInfo|null|undefined} info - `omarchy-battery-status --shell`'s parsed fields
 * @param {PowerState|null|undefined} s - the derived power state
 * @returns {{label: string, value: string}[]} the four rows, in display order
 */
function detailRows(info, s) {
  /** @type {BatteryInfo} */
  var i = info || {}
  /** @type {PowerState} */
  var state = s || {}
  var thresholdActive = !!state.thresholdActive
  var discharging = !!state.discharging
  var flowIdle = !!state.flowIdle
  var full = !!state.full

  var row1Label = thresholdActive ? "Charge limit" : discharging ? "Time left" : "Time to full"
  var row1Value = thresholdActive ? i.threshold || "-" : flowIdle ? "-" : i.time || "\u2014"

  var row2Label = thresholdActive ? "Battery state" : discharging ? "Discharging" : "Charging"
  var row2Value = thresholdActive ? "Holding" : full ? "-" : i.rate || ""

  return [
    { label: row1Label, value: row1Value },
    { label: row2Label, value: row2Value },
    { label: "Battery size", value: i.size || "" },
    { label: "Charge cycles", value: i.cycles || "\u2014" }
  ]
}

/**
 * The hero status line: "Fully charged" when full, else the rotating phrase
 * at `phraseIndex` when there is a non-empty phrase list, else the mode
 * label.
 * @param {PowerState|null|undefined} s - the derived power state
 * @param {string[]|null|undefined} phrases - the active rotating phrase list
 * @param {number} phraseIndex - the current phrase's index (wrapped by the list's length)
 * @param {string} modeLabel - the fallback label (stock's `Model.modeLabel(...)`)
 * @returns {string} the status text
 */
function heroStatus(s, phrases, phraseIndex, modeLabel) {
  if (s && s.fullyCharged) return "Fully charged"
  var list = Array.isArray(phrases) ? phrases : []
  if (list.length > 0) {
    var idx = (Math.floor(Number(phraseIndex)) || 0) % list.length
    if (idx < 0) idx += list.length
    return list[idx]
  }
  return String(modeLabel || "")
}

/**
 * The key-hint line for a section.
 * @param {string|undefined} section - the cursor's section ("profiles" or anything else)
 * @returns {string} the hint
 */
function keyHint(section) {
  if (section === "profiles") return "←→ pick · enter set · tab next"
  return "esc close · tab next"
}

if (typeof module !== "undefined")
  module.exports = {
    batteryPath: batteryPath,
    parseHistory: parseHistory,
    historyPoints: historyPoints,
    historySummary: historySummary,
    timeLabel: timeLabel,
    parseEnergyRate: parseEnergyRate,
    detailRows: detailRows,
    heroStatus: heroStatus,
    keyHint: keyHint
  }
