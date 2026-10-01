// Logic contract for the screenshot stand-in names
// (plugins/araneadev.shared/ShowcaseLogic.js), used by the Network and
// Bluetooth dropdowns so README captures never show real network or device
// names. Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const path = require("node:path")
const { test } = require("node:test")

const logic = require(path.join(__dirname, "..", "..", "plugins/araneadev.shared/ShowcaseLogic.js"))

test("parseNames reads a JSON array of strings", () => {
  assert.deepEqual(logic.parseNames('["Aranea-Home","Cafe-Guest"]'), ["Aranea-Home", "Cafe-Guest"])
  assert.deepEqual(logic.parseNames("[]"), [])
})

test("parseNames refuses anything but a JSON array of strings", () => {
  assert.equal(logic.parseNames("not json"), null)
  assert.equal(logic.parseNames('{"a":1}'), null)
  assert.equal(logic.parseNames('"Aranea"'), null)
  assert.equal(logic.parseNames('["ok", 3]'), null)
  assert.equal(logic.parseNames(undefined), null)
})

test("without names the rows are handed back untouched", () => {
  const rows = [{ key: "a", label: "Real-SSID" }]
  assert.equal(logic.showcaseLabels(rows, [], "Network"), rows)
  assert.equal(logic.showcaseLabels(rows, undefined, "Network"), rows)
  assert.equal(logic.showcaseLabels(rows, "x", "Network"), rows)
})

test("names replace the labels in display order, on copies", () => {
  const rows = [
    { key: "a", label: "Real-A", connected: true },
    { key: "b", label: "Real-B" }
  ]
  const out = logic.showcaseLabels(rows, ["One", "Two", "Three"], "Network")
  assert.deepEqual(out, [
    { key: "a", label: "One", connected: true },
    { key: "b", label: "Two" }
  ])
  assert.equal(rows[0].label, "Real-A")
  assert.notEqual(out[0], rows[0])
})

test("an offset continues the names after an earlier section", () => {
  const rows = [{ key: "s", label: "Real-Saved" }]
  assert.deepEqual(logic.showcaseLabels(rows, ["One", "Two"], "Network", 1), [
    { key: "s", label: "Two" }
  ])
})

test("rows past the names get a generic numbered label, never the real one", () => {
  const rows = [
    { key: "a", label: "Real-A" },
    { key: "b", label: "Real-B" },
    { key: "c", label: "Real-C" }
  ]
  assert.deepEqual(
    logic.showcaseLabels(rows, ["One", ""], "Device", 1).map((r) => r.label),
    ["Device 2", "Device 3", "Device 4"]
  )
  assert.deepEqual(logic.showcaseLabels(null, ["One"], "Device"), [])
})

test("connectedLabel names the connected row, or nothing", () => {
  assert.equal(logic.connectedLabel([{ label: "One" }, { label: "Two", connected: true }]), "Two")
  assert.equal(logic.connectedLabel([{ label: "One" }]), "")
  assert.equal(logic.connectedLabel(undefined), "")
})
