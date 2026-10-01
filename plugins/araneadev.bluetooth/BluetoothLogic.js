// Pure rules for the Aranea Bluetooth dropdown (Panel.qml): the glyph for a
// device type, the signal level behind an available device's node glow, and
// reading RSSI from BlueZ's managed objects. No QML, no I/O;
// tests/js/bluetooth-logic.test.js runs this under Node.

/** @type {Record<string, number>} */
var typeGlyphs = {
  "audio-headset": 0xf02cb,
  "audio-headphones": 0xf02cb,
  "audio-card": 0xf04c3,
  "input-mouse": 0xf037d,
  "input-keyboard": 0xf030c,
  "input-gaming": 0xf0297,
  phone: 0xf03f2,
  computer: 0xf07c0
}

/**
 * The glyph for a Bluetooth device.
 * @param {string|undefined} icon - BlueZ icon name (Quickshell BluetoothDevice.icon)
 * @param {boolean} connected - the device is connected (generic glyph only)
 * @returns {string} a Nerd Font glyph
 */
function deviceGlyph(icon, connected) {
  var code = typeGlyphs[String(icon || "")]
  if (code) return String.fromCodePoint(code)
  return String.fromCodePoint(connected ? 0xf00b1 : 0xf00af)
}

/**
 * Signal level for an RSSI reading.
 * @param {number|undefined} rssi - dBm
 * @returns {number} 3 strong, 2 fair, 1 weak, 0 none
 */
function signalLevel(rssi) {
  if (typeof rssi !== "number" || !isFinite(rssi)) return 0
  if (rssi >= -60) return 3
  if (rssi >= -75) return 2
  if (rssi >= -90) return 1
  return 0
}

/**
 * RSSI per device address from `busctl --json=short call org.bluez /
 * org.freedesktop.DBus.ObjectManager GetManagedObjects` output.
 * @param {string|undefined} json - the command's stdout
 * @returns {Record<string, number>} upper-case address to RSSI
 */
function parseRssi(json) {
  /** @type {Record<string, number>} */
  var out = {}
  var parsed
  try {
    parsed = JSON.parse(String(json || ""))
  } catch (e) {
    return out
  }
  var objects = parsed && Array.isArray(parsed.data) ? parsed.data[0] : null
  if (!objects || typeof objects !== "object") return out
  for (var path in objects) {
    var device = objects[path] && objects[path]["org.bluez.Device1"]
    if (!device || !device.Address || !device.RSSI) continue
    var rssi = Number(device.RSSI.data)
    if (isFinite(rssi)) out[String(device.Address.data).toUpperCase()] = rssi
  }
  return out
}

/**
 * The dropdown's empty text, stock's wording with the adapter checked
 * first: without one the view hides every list, whatever the device rows.
 * @param {boolean} hasAdapter - a Bluetooth adapter is present
 * @param {boolean} enabled - the adapter is powered on
 * @param {boolean} hasRows - any connected, paired or available row exists
 * @returns {string} the text, or "" when the lists speak for themselves
 */
function emptyText(hasAdapter, enabled, hasRows) {
  if (!hasAdapter) return "No Bluetooth adapter"
  if (hasRows) return ""
  return enabled ? "Scanning for devices…" : "Turn Bluetooth on to scan"
}

/**
 * Whether a new RSSI poll differs from the readings already held, so an
 * unchanged poll can skip reassigning them (and rebuilding the view).
 * @param {Record<string, number>|undefined} prev - the readings held now
 * @param {Record<string, number>|undefined} next - the new poll's readings
 * @returns {boolean} true when an address or a value differs
 */
function rssiChanged(prev, next) {
  return JSON.stringify(prev || {}) !== JSON.stringify(next || {})
}

if (typeof module !== "undefined")
  module.exports = { deviceGlyph, signalLevel, parseRssi, emptyText, rssiChanged }
