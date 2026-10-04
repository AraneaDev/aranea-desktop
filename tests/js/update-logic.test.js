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

test("the status caption states the check, it never repeats the REFRESH action", () => {
  const at = new Date(2026, 8, 30, 12, 5).getTime()
  assert.equal(logic.statusCaption({ checkedAt: at }), "checked 12:05")
  assert.equal(logic.statusCaption({ checkedAt: at, error: "status unavailable" }), "check failed")
  assert.equal(logic.statusCaption({ checkedAt: 0 }), "")
  assert.equal(logic.statusCaption(null), "")
})

test("the status caption shows checking even over a stale error or an unchecked status", () => {
  const at = new Date(2026, 8, 30, 12, 5).getTime()
  assert.equal(
    logic.statusCaption({ checkedAt: at, error: "status unavailable" }, true),
    "checking…"
  )
  assert.equal(logic.statusCaption(null, true), "checking…")
  assert.equal(logic.statusCaption({ checkedAt: at }, false), "checked 12:05")
})

test("the status row reads a failed check or a pending reboot as a warning", () => {
  assert.deepEqual(logic.statusRow({ count: 0 }), {
    tone: "ok",
    title: "Up to date",
    subtitle: "0 updates available"
  })
  assert.deepEqual(logic.statusRow({ count: 1 }), {
    tone: "ok",
    title: "Up to date",
    subtitle: "1 update available"
  })
  assert.deepEqual(logic.statusRow({ count: 3, rebootRequired: true }), {
    tone: "warn",
    title: "Reboot required",
    subtitle: "3 updates available"
  })
  assert.deepEqual(logic.statusRow({ count: 0, error: "offline" }), {
    tone: "warn",
    title: "Check failed",
    subtitle: "0 updates available"
  })
  assert.deepEqual(logic.statusRow(null), {
    tone: "ok",
    title: "Up to date",
    subtitle: "0 updates available"
  })
})

test("the pill cursor only reveals on its first key, then moves and wraps", () => {
  assert.deepEqual(logic.moveCursor(0, false, 1), { index: 0, keyboardCursor: true })
  assert.deepEqual(logic.moveCursor(0, false, -1), { index: 0, keyboardCursor: true })
  assert.deepEqual(logic.moveCursor(0, false, 0), { index: 0, keyboardCursor: false })
  assert.deepEqual(logic.moveCursor(0, true, 1), { index: 1, keyboardCursor: true })
  assert.deepEqual(logic.moveCursor(1, true, 1), { index: 0, keyboardCursor: true })
  assert.deepEqual(logic.moveCursor(0, true, -1), { index: 1, keyboardCursor: true })
  assert.deepEqual(logic.moveCursor(1, true, 0), { index: 1, keyboardCursor: true })
})

test("keyHint names Enter's action on the cursor's pill", () => {
  assert.equal(logic.keyHint(0), "↑↓ move · enter open updater · r refresh")
  assert.equal(logic.keyHint(1), "↑↓ move · enter refresh")
})
