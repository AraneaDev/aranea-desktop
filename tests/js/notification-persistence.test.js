const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const persistence = loadPragma("plugins/araneadev.notifications/NotificationSettings.js")

test("notification persistence normalizes settings and popup files", () => {
  assert.equal(
    JSON.stringify(persistence.parseSettings('{"dnd":true,"pending":[]}')),
    JSON.stringify({ error: false, dnd: true, legacy: true })
  )
  assert.equal(persistence.parseSettings("broken").error, true)

})
