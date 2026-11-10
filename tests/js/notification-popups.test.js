// Logic contract for the toast side of NotificationLogic.js: DND bypass,
// feedback senders, compact glyph cards, in-place updates and placement.
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const n = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")

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
  const same = (actual, expected) => assert.equal(JSON.stringify(actual), JSON.stringify(expected))
  const top = n.popupPlacement("top", 40, 10)
  same(top.anchors, { top: true, bottom: false, left: false, right: true })
  same(top.margins, { top: 40, bottom: 10, left: 10, right: 10 })
  same(n.popupPlacement("right", 40, 10).margins, {
    top: 10,
    bottom: 10,
    left: 10,
    right: 40
  })
  same(n.popupPlacement("left", 40, 10).margins, {
    top: 10,
    bottom: 10,
    left: 10,
    right: 10
  })
  same(n.popupPlacement("", "wide", NaN).margins, {
    top: 0,
    bottom: 0,
    left: 0,
    right: 0
  })
})

test("action hints are validated and refreshed without changing popup identity", () => {
  const hint =
    '[{"label":"Open","argv":["xdg-open","/tmp/a b.mp4"]},{"label":"Omacut","argv":["omarchy-launch-omacut","/tmp/a b.mp4"]}]'
  const row = n.snapshotOf({ id: 3, hints: { "omarchy-actions": hint } }, 10)
  assert.equal(row.execActions, hint)
  const next = n.replacementSnapshot({ id: 99, hints: { "omarchy-actions": "invalid" } }, 3, 10)
  assert.equal(next.execActions, "")
  assert.equal(next.originalId, 3)
  assert.equal(next.timestamp, 10)
  assert.equal(n.popupRowChanged(row, Object.assign({}, row, { execActions: "" })), true)
})

for (const module of ["NotificationPresentation", "NotificationLogic"]) {
  test(`${module}: sender buttons exclude default/settings and bound sender data`, () => {
    const p = loadPragma(`plugins/araneadev.notifications/${module}.js`)
    const actions = [
      null,
      { identifier: "default", text: "Default" },
      { identifier: "open", text: "Open" },
      { identifier: "settings", text: "Preferences" },
      { identifier: "prefs", text: "sEtTiNgS" },
      { identifier: "SETTINGS", text: "Preferences" },
      { identifier: "cut", text: "Omacut" },
      { identifier: "", text: "Empty" },
      { identifier: "x".repeat(257), text: "Too long" },
      { identifier: "fallback" }
    ]
    assert.deepEqual(JSON.parse(JSON.stringify(p.senderActionButtons(actions))), [
      { identifier: "open", label: "Open" },
      { identifier: "cut", label: "Omacut" },
      { identifier: "fallback", label: "fallback" }
    ])
    assert.equal(
      p.senderActionButtons([{ identifier: "x", text: "a".repeat(257) }])[0].label.length,
      256
    )
    assert.equal(p.senderActionButtons(Array(17).fill({ identifier: "x" })).length, 16)
    assert.equal(p.senderActionButtons(null).length, 0)
  })
}

test("popup restore keeps generations sharing an id and skips torn writes", () => {
  const rows = n.parsePopupFiles(
    '\n{"originalId":7,"timestamp":10,"summary":"Older"}\n' +
      '{"originalId":7,"timestamp":30,"summary":"Newest"}\n' +
      '{"originalId":8,"timestamp":20,"summary":"Middle"}\n' +
      '{"originalId":9,\nnull\n42\n',
    1
  )
  assert.deepEqual(
    JSON.parse(JSON.stringify(rows.map((row) => [row.originalId, row.timestamp, row.summary]))),
    [
      [7, 30, "Newest"],
      [8, 20, "Middle"],
      [7, 10, "Older"]
    ]
  )
  assert.equal(n.parsePopupFiles(null, 1).length, 0)
})

test("malformed sender values fail closed without discarding other hints", () => {
  const hints = {
    "omarchy-glyph": "ready",
    get "omarchy-exec-argv"() {
      throw new Error("sender disconnected")
    }
  }
  assert.equal(n.execArgvFromHints(hints), "")
  assert.equal(n.glyphFromHints(hints), "ready")
  const circularArgv = ["open"]
  circularArgv.push(circularArgv)
  assert.equal(n.parseExecArgv(circularArgv), null)
  assert.equal(n.localImageFile("file:///tmp/broken%zz.png"), "/tmp/broken%zz.png")
})
