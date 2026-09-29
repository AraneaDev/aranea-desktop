// Contract for the generated QML-compatible JavaScript facades.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { test } = require("node:test")

const root = path.join(__dirname, "..", "..")

test("facades contain generator-owned source regions", () => {
  for (const file of [
    "plugins/araneadev.menu/MenuModel.js",
    "plugins/araneadev.clipboard/ClipboardLogic.js",
    "plugins/araneadev.health/HealthLogic.js",
    "plugins/araneadev.notifications/NotificationLogic.js",
    "plugins/araneadev.health/HealthBridge.js",
    "plugins/araneadev.notifications/ServiceBridge.js"
  ]) {
    const source = fs.readFileSync(path.join(root, file), "utf8")
    assert.match(source, /@aranea-facade-start:/)
    assert.match(source, /@aranea-facade-end/)
  }
})
