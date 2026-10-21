const assert = require("node:assert/strict")
const { test } = require("node:test")
const Logic = require("../../plugins/araneadev.settings/SettingsLogic.js")
const state = {
  screensaver: {
    catalogAvailable: true,
    selectedId: "silk-journey",
    mode: "single",
    choices: [
      { id: "silk-journey", available: true },
      { id: "missing", available: false }
    ],
    idle: { screensaverSeconds: 150, lockSeconds: 1200 }
  }
}
test("screensaver routes accept only catalog identities and typed modes", () => {
  assert.equal(Logic.normalizeSection("screensavers"), "screensavers")
  assert.equal(Logic.normalizeSection("screensavers;bad"), "appearance")
  assert.deepEqual(
    Logic.command("/adapter", "configure screensaver", ["silk-journey", "single"], state),
    ["/adapter", "configure", "screensaver", "silk-journey", "single", "--json"]
  )
  assert.deepEqual(Logic.command("/adapter", "preview screensaver", ["silk-journey"], state), [
    "/adapter",
    "preview",
    "screensaver",
    "silk-journey",
    "--json"
  ])
  for (const id of ["unknown", "missing", "silk-journey;bad"])
    assert.equal(Logic.command("/adapter", "preview screensaver", [id], state), null)
  assert.equal(
    Logic.command("/adapter", "configure screensaver", ["silk-journey", "random"], state),
    null
  )
  assert.equal(Logic.command("/adapter", "start screensaver", ["silk-journey"], state), null)
})
test("timing accepts exact unedited seconds independently of scene availability", () => {
  assert.deepEqual(Logic.command("/adapter", "configure screensaver-timing", ["150", "1260"], {}), [
    "/adapter",
    "configure",
    "screensaver-timing",
    "150",
    "1260",
    "--json"
  ])
  for (const values of [
    ["0", "0"],
    ["1", "2"],
    ["86400", "0"]
  ])
    assert.ok(Logic.command("/adapter", "configure screensaver-timing", values, {}))
  for (const values of [
    ["-1", "1200"],
    ["1.5", "1200"],
    ["900", "900"],
    ["86401", "0"],
    ["", "0"],
    [" 0", "0"]
  ])
    assert.equal(Logic.command("/adapter", "configure screensaver-timing", values, state), null)
})
test("outcomes require readback, honest preview acknowledgment and reload metadata", () => {
  assert.equal(
    Logic.outcome("configure screensaver", ["silk-journey", "single"], state, true),
    "Saved"
  )
  assert.equal(
    Logic.outcome("configure screensaver", ["silk-journey", "shuffle"], state, true),
    "Save not confirmed"
  )
  assert.equal(
    Logic.outcome("preview screensaver", ["silk-journey"], state, true, {
      screensaverPreview: { accepted: true, sessionId: "s" }
    }),
    "Preview accepted"
  )
  assert.equal(
    Logic.outcome("preview screensaver", ["omarchy"], state, true, {
      screensaverPreview: { accepted: true, delegated: "stock", sessionId: null }
    }),
    "Stock preview delegated"
  )
  assert.equal(
    Logic.outcome("preview screensaver", ["silk-journey"], state, true, {}),
    "Preview not confirmed"
  )
  const result = { screensaverTiming: { persisted: true, applied: true } }
  assert.equal(
    Logic.outcome("configure screensaver-timing", ["150", "1200"], state, true, result),
    "Timing saved"
  )
  assert.equal(
    Logic.outcome("configure screensaver-timing", ["150", "1260"], state, true, result),
    "Save not confirmed"
  )
  assert.equal(
    Logic.outcome("configure screensaver-timing", ["150", "1200"], state, false, {
      screensaverTiming: { persisted: true, applied: false }
    }),
    "Saved · reload failed"
  )
})
