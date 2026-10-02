/**
 * Clamps index into [0, length - 1], or 0 when length is 0 or less.
 * @param {number} index - the candidate index
 * @param {number} length - the list length
 * @returns {number} the clamped index
 */
function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

/**
 * Moves the power profile picker's index by delta, clamped to profiles.
 * @param {number} index - the current index
 * @param {number} delta - the move, positive or negative
 * @param {*} profiles - the profile name list
 * @returns {number} the new index, 0 when profiles is empty
 */
function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

/**
 * Parses a tab-separated `key<TAB>value` reply (one pair per line, as
 * `omarchy-battery-status --shell` and `omarchy-system-stats` print) into a
 * plain object.
 * @param {*} raw - the raw key/value output, or falsy
 * @returns {{[key: string]: string}} the parsed fields
 */
function parseKeyValue(raw) {
  /** @type {{[key: string]: string}} */
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

/**
 * Parses `omarchy-powerprofiles-list --active-state`'s reply
 * (`name<TAB>active`, one profile per line) into the profile list, the
 * active profile's name and a clamped cursor index.
 * @param {*} raw - the raw output, or falsy
 * @param {number} previousIndex - the cursor index before this parse
 * @returns {{profiles: Array<string>, activeProfile: string, profileIndex: number}} the parsed status
 */
function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

/**
 * Display glyph for a power profile name.
 * @param {string} name - "power-saver" | "balanced" | "performance", or anything else
 * @returns {string} the glyph
 */
function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

/**
 * 0..1 charge level for the battery progress bar.
 * @param {*} device - the UPower display device, or falsy
 * @returns {number} the charge fraction, 0 when there is no present device
 */
function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

/**
 * Whether a charge-control threshold is holding the battery just under
 * 100% rather than letting it keep charging.
 * @param {*} device - the UPower display device, or falsy
 * @param {boolean} onBattery - whether the device is running on battery
 * @param {*} states - UPowerDeviceState values, from Panel.qml's upowerStates()
 * @returns {boolean} whether a threshold is active
 */
function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

/**
 * The bar icon's battery glyph: a charge-level step, picked from the
 * charging or default icon set by state and charge-threshold.
 * @param {*} device - the UPower display device, or falsy
 * @param {boolean} onBattery - whether the device is running on battery
 * @param {*} states - UPowerDeviceState values, from Panel.qml's upowerStates()
 * @returns {string} the glyph, or "" when there is no present device
 */
function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

/**
 * The hero status line's fallback label (used when there is no rotating
 * phrase to show instead).
 * @param {*} device - the UPower display device, or falsy
 * @param {boolean} onBattery - whether the device is running on battery
 * @param {*} states - UPowerDeviceState values, from Panel.qml's upowerStates()
 * @returns {string} the label, or "" when there is no present device
 */
function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel
  }
}
