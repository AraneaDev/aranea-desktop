// Logic contract for the Aranea Bluetooth dropdown (BluetoothLogic.js).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(
  path.join(__dirname, "..", "..", "plugins/araneadev.bluetooth/BluetoothLogic.js")
)
const g = (cp) => String.fromCodePoint(cp)

test("device types map to their glyphs", () => {
  assert.equal(logic.deviceGlyph("audio-headset", false), g(0xf02cb))
  assert.equal(logic.deviceGlyph("audio-headphones", true), g(0xf02cb))
  assert.equal(logic.deviceGlyph("audio-card", false), g(0xf04c3))
  assert.equal(logic.deviceGlyph("input-mouse", false), g(0xf037d))
  assert.equal(logic.deviceGlyph("input-keyboard", false), g(0xf030c))
  assert.equal(logic.deviceGlyph("input-gaming", false), g(0xf0297))
  assert.equal(logic.deviceGlyph("phone", false), g(0xf03f2))
  assert.equal(logic.deviceGlyph("computer", false), g(0xf07c0))
})

test("unknown types fall back to the Bluetooth glyph, connected or not", () => {
  assert.equal(logic.deviceGlyph("", false), g(0xf00af))
  assert.equal(logic.deviceGlyph(undefined, true), g(0xf00b1))
  assert.equal(logic.deviceGlyph("printer", false), g(0xf00af))
})

test("signal strength has three levels and none", () => {
  assert.equal(logic.signalLevel(-50), 3)
  assert.equal(logic.signalLevel(-60), 3)
  assert.equal(logic.signalLevel(-61), 2)
  assert.equal(logic.signalLevel(-75), 2)
  assert.equal(logic.signalLevel(-76), 1)
  assert.equal(logic.signalLevel(-90), 1)
  assert.equal(logic.signalLevel(-91), 0)
  assert.equal(logic.signalLevel(undefined), 0)
  assert.equal(logic.signalLevel(NaN), 0)
})

const managed = JSON.stringify({
  type: "a{oa{sa{sv}}}",
  data: [
    {
      "/org/bluez/hci0": {
        "org.bluez.Adapter1": { Address: { type: "s", data: "3C:95:09:5C:CE:70" } }
      },
      "/org/bluez/hci0/dev_AA_BB": {
        "org.bluez.Device1": {
          Address: { type: "s", data: "aa:bb:cc:dd:ee:ff" },
          RSSI: { type: "n", data: -63 }
        }
      },
      "/org/bluez/hci0/dev_11_22": {
        "org.bluez.Device1": { Address: { type: "s", data: "11:22:33:44:55:66" } }
      }
    }
  ]
})

test("RSSI is read per device address from BlueZ's managed objects", () => {
  assert.deepEqual(logic.parseRssi(managed), { "AA:BB:CC:DD:EE:FF": -63 })
})

test("bad or empty poll output gives no readings", () => {
  assert.deepEqual(logic.parseRssi(""), {})
  assert.deepEqual(logic.parseRssi("not json"), {})
  assert.deepEqual(logic.parseRssi('{"data":[]}'), {})
  assert.deepEqual(logic.parseRssi(undefined), {})
})
