const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const persistence = loadPragma("plugins/araneadev.notifications/NotificationSettings.js")

test("notification settings normalize persisted values", () => {
  assert.equal(
    JSON.stringify(persistence.parseSettings('{"dnd":true,"pending":[]}')),
    JSON.stringify({ error: false, dnd: true, legacy: true })
  )
  assert.equal(persistence.parseSettings("broken").error, true)
})

test("persisted button argv survives literally and legacy or invalid rows offer no buttons", () => {
  const n = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")
  const inbox = require("../../plugins/araneadev.notifications/InboxLogic.js")
  const raw = '[{"label":"Open","argv":["xdg-open","/tmp/a b.mp4","a\\"b","$(touch nope)","a;b"]}]'
  const row = n.snapshotOf({ id: 4, hints: { "omarchy-actions": raw } }, 100)
  const restored = n.parsePopupFiles(n.serializePopup(row, 1), 1)[0]
  assert.equal(restored.execActions, raw)
  assert.deepEqual(JSON.parse(restored.execActions), [
    { label: "Open", argv: ["xdg-open", "/tmp/a b.mp4", 'a"b', "$(touch nope)", "a;b"] }
  ])
  assert.equal(inbox.snapshotOf([{ ...restored, fileName: "100-4.json" }])[0].execActions, raw)
  assert.equal(n.popupEntry({}, 1).execActions, "")
  assert.equal(n.popupEntry({ execActions: '[{"label":"Open","argv":[]}]' }, 1).execActions, "")
})

test("Taildrop filenames and paths stay readable data through persistence", () => {
  const n = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")
  for (const body of [
    "holiday photo.png",
    "/home/test/Downloads/holiday photo.png",
    "$(touch nope); file.png"
  ]) {
    const row = n.snapshotOf(
      {
        id: 92,
        appName: "Taildrop",
        summary: "File received",
        body: body,
        image: "/missing/preview.png",
        urgency: 2
      },
      100
    )
    const restored = n.parsePopupFiles(n.serializePopup(row, 1), 1)[0]
    assert.equal(restored.body, body)
    assert.equal(n.styledBody(restored.body, restored.app, ""), body)
    assert.equal(n.parseExecArgv(restored.execArgv), null)
    assert.equal(restored.execActions, "")
    assert.equal(n.shownImages(restored, row, []).image, "/missing/preview.png")
  }
})
