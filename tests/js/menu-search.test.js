const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const search = loadPragma("plugins/araneadev.menu/MenuSearch.js")

test("menu search normalizes names and matches aliases and descriptions", () => {
  const entry = {
    id: "system.power-save",
    label: "Power Saver",
    aliases: ["battery_mode"],
    description: "Reduce battery usage"
  }

  assert.equal(search.searchableToken("battery_mode"), "battery mode")
  assert.equal(search.leafIdFor(entry.id), "power-save")
  assert.match(search.nameSearchText(entry), /battery mode/)
  assert.equal(search.matchesQuery(entry, "power", true), true)
  assert.equal(search.matchesQuery(entry, "battery usage", true), true)
  assert.equal(search.matchesQuery(entry, "usag", true), false)
})

test("menu search scores exact labels ahead of descriptions", () => {
  const items = {
    root: { id: "root" },
    exact: { id: "exact", parent: "root", label: "Power", kind: "action", order: 0 },
    description: {
      id: "description",
      parent: "root",
      label: "Battery",
      description: "power management",
      kind: "action",
      order: 1
    }
  }

  assert.ok(
    search.searchScore(items, items.exact, "power") <
      search.searchScore(items, items.description, "power")
  )
})
