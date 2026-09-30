const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.updates/UpdateLogic.js"))

test("parses update rows into grouped source counts", () => {
  const status = logic.parseStatus({
    updates: [
      { source: "system", name: "openssl" },
      { source: "system", name: "curl" },
      { source: "flatpak", name: "org.gimp.GIMP" }
    ],
    rebootRequired: false
  })

  assert.equal(status.available, true)
  assert.equal(status.count, 3)
  assert.deepEqual(status.groups, [
    { source: "system", count: 2, items: ["openssl", "curl"] },
    { source: "flatpak", count: 1, items: ["org.gimp.GIMP"] }
  ])
  assert.equal(status.rebootRequired, false)
  assert.equal(status.error, "")
})

test("normalizes reboot-required and malformed status values", () => {
  const status = logic.parseStatus({
    updates: [{ source: "system", name: "linux" }],
    rebootRequired: "yes"
  })

  assert.equal(status.rebootRequired, true)
  assert.equal(logic.parseStatus(null).error, "invalid status")
  assert.equal(logic.parseStatus({ updates: "bad" }).error, "invalid updates")
})

test("preserves a valid result while marking a failed refresh stale", () => {
  const previous = logic.parseStatus({
    updates: [{ source: "system", name: "vim" }],
    rebootRequired: false
  })
  const merged = logic.mergeRefresh(previous, { error: "status unavailable" }, 1234)

  assert.equal(merged.count, 1)
  assert.equal(merged.groups[0].items[0], "vim")
  assert.equal(merged.error, "status unavailable")
  assert.equal(merged.stale, true)
  assert.equal(merged.checkedAt, 1234)
})

test("maps update status to compact indicator severity", () => {
  assert.deepEqual(logic.displayState(logic.parseStatus({ updates: [] })), {
    visible: false,
    countText: "",
    severity: "muted"
  })
  assert.equal(
    logic.displayState(logic.parseStatus({ updates: [{ source: "system", name: "a" }] })).countText,
    "1"
  )
  assert.equal(
    logic.displayState(logic.parseStatus({ updates: [], rebootRequired: true })).severity,
    "warning"
  )
  assert.equal(logic.displayState({ count: 0, error: "offline", stale: true }).severity, "error")
})

test("the header hint states the check, it never repeats the REFRESH action", () => {
  const at = new Date(2026, 8, 30, 12, 5).getTime()
  assert.equal(logic.headerHint({ checkedAt: at }), "CHECKED 12:05")
  assert.equal(logic.headerHint({ checkedAt: at, error: "status unavailable" }), "CHECK FAILED")
  assert.equal(logic.headerHint({ checkedAt: 0 }), "")
  assert.equal(logic.headerHint(null), "")
})
