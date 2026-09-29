// Logic contract for the menu tree (MenuModel.js): reading the JSONC menu
// files, resolving routes, walking the tree, search and the display rows.
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const menu = loadPragma("plugins/araneadev.menu/MenuModel.js")

// A small menu: a shipped file and a user file overriding one label.
const shipped = `{
  // top-level sections
  "items": {
    "system": { "label": "System", "icon": "S", "aliases": ["power_menu"] },
    "system.lock": { "label": "Lock", "action": "omarchy-lock-screen", "description": "lock the screen now" },
    "setup": { "label": "Setup", "aliases": "settings" },
    "setup.power": { "label": "Power Profile", "description": "battery or performance" },
    "setup.power.saver": { "label": "Saver", "action": "powerprofilesctl set power-saver", "checked": "true" },
    "setup.wifi": { "label": "Wi-Fi", "action": "omarchy-launch-wifi", "when": "omarchy-cmd-present iwctl" },
    "shortcut": { "label": "Power", "target": "setup.power" },
    "empty": { "label": "Empty" },
    "not-an-entry": [1, 2],
  },
}`
const user = `{ "setup.power.saver": { "label": "Battery Saver", "action": "powerprofilesctl set power-saver", "checked": "true" } }`
const { items, itemOrder } = menu.mergeMenuSources(
  menu.parseMenuJsonc(shipped),
  menu.parseMenuJsonc(user)
)

test("stripJsonc drops whole-line comments and trailing commas", () => {
  assert.equal(menu.stripJsonc('{\n  // note\n  "a": [1, 2,],\n}'), '{\n  "a": [1, 2]\n}')
  assert.equal(menu.stripJsonc(null), "")
})

test("parseMenuJsonc reads an items map or a top-level map and skips non-objects", () => {
  const parsed = menu.parseMenuJsonc(shipped)
  assert.equal(
    JSON.stringify(parsed.map((x) => x.id)),
    JSON.stringify([
      "system",
      "system.lock",
      "setup",
      "setup.power",
      "setup.power.saver",
      "setup.wifi",
      "shortcut",
      "empty"
    ])
  )
  assert.deepEqual(menu.parseMenuJsonc(user)[0].label, "Battery Saver")
})

test("parseMenuJsonc derives parents from dotted ids and kinds from the fields", () => {
  const byId = Object.fromEntries(menu.parseMenuJsonc(shipped).map((x) => [x.id, x]))
  assert.equal(byId["setup.power.saver"].parent, "setup.power")
  assert.equal(byId.system.parent, "root")
  assert.equal(byId["system.lock"].kind, "action")
  assert.equal(byId.shortcut.kind, "link")
  assert.equal(byId.setup.kind, "menu")
  assert.equal(JSON.stringify(byId.setup.aliases), JSON.stringify(["settings"]))
})

test("parseMenuJsonc returns nothing for empty, invalid or non-object text", () => {
  assert.equal(JSON.stringify(menu.parseMenuJsonc("")), "[]")
  assert.equal(JSON.stringify(menu.parseMenuJsonc("{ not json")), "[]")
  assert.equal(JSON.stringify(menu.parseMenuJsonc("42")), "[]")
})

test("mergeMenuSources lets the user file override a shipped item and adds a root", () => {
  assert.equal(items["setup.power.saver"].label, "Battery Saver")
  assert.equal(itemOrder[0], "root")
  assert.equal(items.root.label, "Go")
  assert.equal(items.system.order, itemOrder.indexOf("system"))
  assert.equal(itemOrder.filter((id) => id === "setup.power.saver").length, 1)
})

test("resolveRoute prefers ids, then aliases, and never routes to an app", () => {
  const withApp = Object.assign({}, items, {
    "apps.htop": { id: "apps.htop", kind: "app", parent: "apps", aliases: ["setup"] }
  })
  const order = itemOrder.concat(["apps.htop"])
  assert.equal(menu.resolveRoute(withApp, order, "setup"), "setup")
  assert.equal(menu.resolveRoute(withApp, order, "Power_Menu"), "system")
  assert.equal(menu.resolveRoute(withApp, order, "settings"), "setup")
  assert.equal(menu.resolveRoute(withApp, order, "menu"), "root")
  assert.equal(menu.resolveRoute(withApp, order, ""), "root")
  assert.equal(menu.resolveRoute(withApp, order, "Nowhere"), "nowhere")
})

test("slugify joins alphanumeric runs with dashes", () => {
  assert.equal(menu.slugify("  Zen Browser (beta) "), "zen-browser-beta")
  assert.equal(menu.slugify("!!!"), "item")
})

test("depth, path and ancestry follow the parents", () => {
  assert.equal(menu.depthFor(items, "setup"), 0)
  assert.equal(menu.depthFor(items, "setup.power.saver"), 2)
  assert.equal(menu.pathFor(items, "setup.power.saver"), "Setup › Power Profile › Battery Saver")
  assert.equal(menu.parentPathFor(items, "setup.power.saver"), "Setup › Power Profile")
  assert.equal(menu.parentPathFor(items, "setup"), "")
  assert.equal(menu.isDescendantOf(items, "setup.power.saver", "setup"), true)
  assert.equal(menu.isDescendantOf(items, "system.lock", "setup"), false)
  assert.equal(menu.isDescendantOf(items, "system", "root"), true)
  assert.equal(menu.isDescendantOf(items, "root", "root"), false)
  assert.equal(menu.childCount(items, itemOrder, "setup"), 2)
  assert.equal(menu.item(items, "missing"), null)
})

test("a menu is visible only while something under it is", () => {
  const visible = (id, when) => menu.isVisible(items, itemOrder, when || {}, items[id])
  assert.equal(visible("setup"), true)
  assert.equal(visible("empty"), false)
  assert.equal(visible("shortcut"), true, "a link is visible through its target")
  assert.equal(
    visible("setup.wifi", { "setup.wifi": false }),
    false,
    "a failed when: hides the row"
  )
  assert.equal(visible("setup.wifi", { "setup.wifi": true }), true)
  assert.equal(menu.isVisible(items, itemOrder, {}, null), false)
})

test("labelFor marks checked rows", () => {
  assert.equal(
    menu.labelFor(items["setup.power.saver"], { "setup.power.saver": true }),
    "Battery Saver ✓"
  )
  assert.equal(menu.labelFor(items["setup.power.saver"], {}), "Battery Saver")
  assert.equal(menu.labelFor(null, {}), "")
})

test("search matches names by substring and descriptions by whole word", () => {
  const lock = items["system.lock"]
  assert.equal(menu.matchesQuery(lock, "loc", true), true)
  assert.equal(menu.matchesQuery(lock, "screen", true), true, "a description word")
  assert.equal(menu.matchesQuery(lock, "scree", true), false, "descriptions need whole words")
  assert.equal(menu.matchesQuery(lock, "lock", false), false, "hidden rows never match")
  assert.equal(menu.matchesQuery(items.root, "go", true), false, "the root never matches")
  assert.equal(menu.matchesQuery(items.system, "power menu", true), true, "aliases are searched")
})

test("search scores an exact label above a prefix, a substring and a description", () => {
  const score = (id, q) => menu.searchScore(items, items[id], q)
  assert.ok(score("system.lock", "lock") < score("setup.power", "power"))
  assert.ok(score("setup.power", "power") < score("setup.power.saver", "saver"))
  assert.ok(score("setup.power.saver", "saver") < score("system.lock", "screen"))
  const app = {
    id: "apps.zen",
    kind: "app",
    label: "Zen Browser",
    parent: "apps",
    aliases: [],
    order: 99
  }
  assert.ok(
    menu.searchScore(items, app, "zen") < score("setup.power.saver", "saver"),
    "a whole-word app name wins"
  )
})

test("displayRow shows the target's children for a link and a tagline at the top", () => {
  const link = menu.displayRow(items, itemOrder, {}, items.shortcut, "detail")
  assert.equal(link.target, "setup.power")
  assert.equal(link.childCount, 1)
  const setup = menu.displayRow(items, itemOrder, {}, items.setup, "fallback", 7, "drilldown")
  assert.equal(setup.detail, "SYSTEM // DEVICES // PREFERENCES")
  assert.equal(setup.score, 7)
  assert.equal(setup.section, "drilldown")
  const saver = menu.displayRow(
    items,
    itemOrder,
    { "setup.power.saver": true },
    items["setup.power.saver"],
    "d"
  )
  assert.equal(saver.label, "Battery Saver ✓")
  assert.equal(saver.path, "Setup › Power Profile › Battery Saver")
  assert.equal(saver.childCount, 0)
  assert.equal(saver.detail, "d")
})
