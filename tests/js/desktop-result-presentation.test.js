const assert = require("node:assert/strict")
const { test } = require("node:test")
const view = require("../../plugins/araneadev.menu/DesktopResultPresentation.js")

test("typed results keep a visible identity without an application icon", () => {
  for (const type of ["app", "command", "window", "workspace", "setting", "action"]) {
    assert.ok(view.typeLabel(type))
    assert.ok(view.fallbackIcon(type))
  }
  assert.equal(view.typeLabel(""), "")
  assert.equal(view.fallbackIcon(""), "")
})
