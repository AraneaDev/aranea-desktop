const assert = require("node:assert/strict")
const { test } = require("node:test")
const { actionRecords } = require("../../plugins/araneadev.menu/DesktopActionRecords.js")

test("changing DND preserves identity and distinguishes quiet hours from the manual preference", () => {
  const off = actionRecords({ dnd: { available: true, enabled: false, quietHours: true } })[0]
  const on = actionRecords({ dnd: { available: true, enabled: true, quietHours: true } })[0]
  assert.equal(off.key, "action:dnd")
  assert.equal(on.key, off.key)
  assert.match(off.label, /Enable/)
  assert.match(on.label, /Disable/)
  assert.match(off.detail, /quiet hours/i)
  assert.ok(off.aliases.includes("dnd"))
})

test("only available installed wallpaper and fresh audio targets become action records", () => {
  const rows = actionRecords({
    audio: {
      available: true,
      outputs: [
        { key: "7:speaker", label: "Studio Speakers", current: true },
        { key: "8:headset", label: "Headset", current: false }
      ]
    },
    wallpaper: {
      available: true,
      activeId: "night",
      scheduled: true,
      choices: [
        { id: "night", label: "Night", available: true },
        { id: "day", label: "Day", available: true },
        { id: "missing", label: "Missing", available: false }
      ]
    }
  })
  assert.deepEqual(
    rows.map((row) => row.key),
    [
      "action:audio:7:speaker",
      "action:audio:8:headset",
      "action:wallpaper:night",
      "action:wallpaper:day"
    ]
  )
  assert.match(rows[0].detail, /Current/)
  assert.match(rows[2].detail, /Current/)
  assert.match(rows[3].detail, /schedule/i)
  assert.deepEqual(rows[0].target, { actionId: "audio:7:speaker" })
  assert.deepEqual(
    actionRecords({
      audio: { available: false, outputs: [{ key: "7:speaker", label: "Speakers" }] }
    }),
    []
  )
})

test("missing and malformed capabilities do not create selectable defaults", () => {
  assert.deepEqual(actionRecords(null), [])
  assert.deepEqual(actionRecords({ dnd: { available: true, enabled: null } }), [])
  assert.deepEqual(
    actionRecords({ audio: { available: true, outputs: [{ key: "", label: "Unidentified" }] } }),
    []
  )
})
