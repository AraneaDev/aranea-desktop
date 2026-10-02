// Logic contract for NmcliTerse.js (splitTerse), generated into both
// NetworkLogic.js and VpnLogic.js by tools/js-facade-generator.mjs. Run with
// `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.shared/NmcliTerse.js"))

test("splitTerse splits on unescaped colons", () => {
  assert.deepEqual(logic.splitTerse("a:b:c"), ["a", "b", "c"])
  assert.deepEqual(logic.splitTerse(""), [""])
  assert.deepEqual(logic.splitTerse(undefined), [""])
})

test("splitTerse unescapes \\: and \\\\ within a field", () => {
  assert.deepEqual(logic.splitTerse("My\\:Net:uuid-1:802-11-wireless::no:0"), [
    "My:Net",
    "uuid-1",
    "802-11-wireless",
    "",
    "no",
    "0"
  ])
  assert.deepEqual(logic.splitTerse("a\\\\\\:b"), ["a\\:b"])
})

test("splitTerse splits nmcli VPN connection lines and unescapes a parenthesized name", () => {
  assert.deepEqual(logic.splitTerse("Office (Firebox)\\: HQ:uuid-1:vpn:tun0:yes:activated"), [
    "Office (Firebox): HQ",
    "uuid-1",
    "vpn",
    "tun0",
    "yes",
    "activated"
  ])
})

test("splitTerse unescapes a literal backslash before a field it doesn't also escape", () => {
  assert.deepEqual(logic.splitTerse("back\\\\slash:next"), ["back\\slash", "next"])
})
