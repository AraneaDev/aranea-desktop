// Logic contract for the toast side of NotificationLogic.js: DND bypass,
// feedback senders, compact glyph cards, in-place updates and placement.
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const n = require(
  path.join(__dirname, "..", "..", "plugins/araneadev.notifications/NotificationLogic.js")
)

const CRITICAL = 2

test("DND lets omarchy-action through, and notify-send only when critical", () => {
  assert.equal(n.shouldBypassDnd({ appName: "omarchy-action", urgency: 0 }, CRITICAL), true)
  assert.equal(n.shouldBypassDnd({ appName: "notify-send", urgency: CRITICAL }, CRITICAL), true)
  assert.equal(n.shouldBypassDnd({ appName: "notify-send", urgency: 1 }, CRITICAL), false)
  assert.equal(n.shouldBypassDnd({ appName: "Slack", urgency: CRITICAL }, CRITICAL), false)
  assert.equal(n.shouldBypassDnd(null, CRITICAL), false)
})

test("notify-send and omarchy-action toasts are feedback, not messages", () => {
  assert.equal(n.isEphemeralApp("notify-send"), true)
  assert.equal(n.isEphemeralApp("omarchy-action"), true)
  assert.equal(n.isEphemeralApp("Signal"), false)
  assert.equal(n.isEphemeralApp(null), false)
})

test("a glyph-prefixed summary is one character then two spaces", () => {
  assert.equal(n.summaryStartsWithGlyph("󰂄  Charging"), true)
  assert.equal(n.summaryStartsWithGlyph("  😀  Surrogate pair counts as one"), true)
  assert.equal(n.summaryStartsWithGlyph("A  B"), true)
  assert.equal(n.summaryStartsWithGlyph("Hi there"), false)
  assert.equal(n.summaryStartsWithGlyph(""), false)
  assert.equal(n.summaryStartsWithGlyph(null), false)
})

test("the compact glyph layout needs a glyph, no icon and a single line", () => {
  assert.equal(n.shouldRenderCompactGlyph("󰂄", "", true), true)
  assert.equal(n.shouldRenderCompactGlyph("󰂄", "file:///icon.png", true), false)
  assert.equal(n.shouldRenderCompactGlyph("󰂄", "", false), false)
  assert.equal(n.shouldRenderCompactGlyph("", "", true), false)
})

test("a refresh writes only when something the card draws changed", () => {
  const row = {
    app: "a",
    appIcon: "",
    summary: "s",
    body: "b",
    image: "",
    glyph: "",
    execArgv: "",
    urgency: 1,
    expireTimeout: 0,
    timestamp: 1
  }
  assert.equal(
    n.popupRowChanged(row, Object.assign({}, row, { timestamp: 2 })),
    false,
    "the timestamp is not drawn"
  )
  assert.equal(n.popupRowChanged(row, Object.assign({}, row, { body: "new" })), true)
  assert.equal(n.popupRowChanged(null, null), false)
  assert.ok(n.popupRoles().includes("summary"))
  assert.ok(!n.popupRoles().includes("timestamp"))
})

test("an update through replaces_id keeps the replaced popup's id and time", () => {
  const updated = n.replacementSnapshot(
    { id: 44, appName: "mail", summary: "2 new", body: "", hints: {} },
    7,
    1000
  )
  assert.equal(updated.id, 7)
  assert.equal(updated.originalId, 7)
  assert.equal(updated.timestamp, 1000)
  assert.equal(updated.summary, "2 new")
  assert.equal(n.popupFileName(updated), "1000-7.json")
})

test("toasts sit top-right, clearing the bar only on its own edge", () => {
  const top = n.popupPlacement("top", 40, 10)
  assert.deepEqual(top.anchors, { top: true, bottom: false, left: false, right: true })
  assert.deepEqual(top.margins, { top: 40, bottom: 10, left: 10, right: 10 })
  assert.deepEqual(n.popupPlacement("right", 40, 10).margins, {
    top: 10,
    bottom: 10,
    left: 10,
    right: 40
  })
  assert.deepEqual(n.popupPlacement("left", 40, 10).margins, {
    top: 10,
    bottom: 10,
    left: 10,
    right: 10
  })
  assert.deepEqual(n.popupPlacement("", "wide", NaN).margins, {
    top: 0,
    bottom: 0,
    left: 0,
    right: 0
  })
})
