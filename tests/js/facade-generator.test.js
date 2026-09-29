// Contract for the generated QML-compatible JavaScript facades.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { test } = require("node:test")

const root = path.join(__dirname, "..", "..")

test("facades contain every generator-owned source region", () => {
  const expected = {
    "plugins/araneadev.menu/MenuModel.js": [
      "MenuPresentation.js",
      "MenuHistory.js",
      "MenuSearch.js",
      "MenuTree.js"
    ],
    "plugins/araneadev.clipboard/ClipboardLogic.js": ["ClipboardPresentation.js"],
    "plugins/araneadev.health/HealthLogic.js": ["HealthPresentation.js"],
    "plugins/araneadev.notifications/NotificationLogic.js": ["NotificationPresentation.js"],
    "plugins/araneadev.health/HealthBridge.js": ["ServiceRegistry.js"],
    "plugins/araneadev.notifications/ServiceBridge.js": ["ServiceRegistry.js"]
  }
  for (const [file, sources] of Object.entries(expected)) {
    const source = fs.readFileSync(path.join(root, file), "utf8")
    for (const name of sources)
      assert.match(source, new RegExp(`@aranea-facade-start: .*${name.replace(".", "\\.")}`))
  }
})
