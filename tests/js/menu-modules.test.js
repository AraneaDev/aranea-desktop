// Contract for the menu facade siblings (MenuAppRows.js, MenuItemParsing.js,
// MenuGuardScript.js): each loads on its own, so it does not lean on a helper
// that only exists inside the generated MenuModel facade, and each answers
// exactly like the facade that inlines it.
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const root = path.join(__dirname, "..", "..")
const facade = loadPragma("plugins/araneadev.menu/MenuModel.js")
const appRows = loadPragma("plugins/araneadev.menu/MenuAppRows.js")
const parsing = loadPragma("plugins/araneadev.menu/MenuItemParsing.js")
const guards = loadPragma("plugins/araneadev.menu/MenuGuardScript.js")
const fixture = fs.readFileSync(path.join(root, "tests/qml/fixtures/omarchy-menu.jsonc"), "utf8")

/**
 * Round-trips a value through JSON so values from different vm realms compare.
 * @param {*} value - any JSON-able value
 * @returns {*} a plain copy
 */
function plain(value) {
  return JSON.parse(JSON.stringify(value === undefined ? null : value))
}

/**
 * Asserts that module and facade give the same answer for NAME(...args).
 * @param {object} module - the sibling module
 * @param {string} name - exported function name
 * @param {Array<*>} args - call arguments
 * @returns {void}
 */
function sameAsFacade(module, name, args) {
  assert.equal(typeof module[name], "function", `${name} is exported`)
  assert.deepEqual(plain(module[name](...args)), plain(facade[name](...args)), name)
}

test("MenuAppRows answers like the facade", () => {
  const twelve = Array.from({ length: 12 }, (_, i) => "app" + i)
  const rows = [
    { id: "apps.x", parent: "apps", kind: "app", appId: "x", label: "X" },
    { id: "apps.y", parent: "apps", kind: "app", appId: "y", label: "y" }
  ]
  sameAsFacade(appRows, "normalizeAppIds", [[" a ", "a", 3, {}, "b"], 2])
  sameAsFacade(appRows, "recordRecentApp", [["two", "one"], "three", 3])
  sameAsFacade(appRows, "toggleFavoriteApp", [["a"], "b", 12])
  sameAsFacade(appRows, "toggleFavoriteApp", [twelve, "extra", 12])
  sameAsFacade(appRows, "serializeAppHistory", [["a"], ["b"], 12, 12])
  sameAsFacade(appRows, "parseAppHistory", [
    facade.serializeAppHistory(["a"], ["b"], 12, 12),
    12,
    12
  ])
  sameAsFacade(appRows, "parseAppHistory", ["{broken", 12, 12])
  sameAsFacade(appRows, "pruneAppIds", [["a", "b"], ["b"]])
  sameAsFacade(appRows, "appRowsForIds", [rows, ["y", "x"], "apps.favorites", "apps.favorites"])
  sameAsFacade(appRows, "dedupeAppRows", [
    [
      { itemId: "apps.x", kind: "app", appId: "x" },
      { itemId: "apps.favorites.x", kind: "app", appId: "x" }
    ]
  ])
  sameAsFacade(appRows, "sortAppsMenu", [
    [
      { itemId: "apps.y", kind: "app", label: "y" },
      { itemId: "apps.recent", kind: "menu", label: "Recent" },
      { itemId: "apps.x", kind: "app", label: "X" },
      { itemId: "apps.favorites", kind: "menu", label: "Favorites" }
    ]
  ])
  sameAsFacade(appRows, "mergeAppRows", [{ apps: { id: "apps", parent: "" } }, ["apps"], rows])
})

test("MenuItemParsing answers like the facade", () => {
  const parsed = facade.parseMenuJsonc(fixture)
  sameAsFacade(parsing, "stripJsonc", ['{\n  // note\n  "a": 1,\n}'])
  sameAsFacade(parsing, "normalizeAliases", ["one, two"])
  sameAsFacade(parsing, "normalizeItem", [
    "setup.power",
    { label: "Power", description: "battery" }
  ])
  sameAsFacade(parsing, "parseMenuJsonc", [fixture])
  sameAsFacade(parsing, "mergeMenuSources", [
    parsed,
    facade.parseMenuJsonc('{"setup": {"label": "Settings"}}')
  ])
  const merged = facade.mergeMenuSources(parsed, [])
  sameAsFacade(parsing, "swapProviderRows", [
    merged.items,
    merged.itemOrder,
    "setup",
    [{ id: "setup.one", parent: "setup", kind: "action", label: "One" }]
  ])
})

test("MenuGuardScript answers like the facade", () => {
  const items = {
    a: {
      id: "a",
      when: "omarchy-cmd-present bash",
      checked: "[[ $(omarchy-default-browser) == x ]]"
    },
    b: { id: "b", when: "true" }
  }
  sameAsFacade(guards, "guardScript", [items])
  sameAsFacade(guards, "guardScript", [{}])
})

test("settings route is guarded, unique, and searchable under Setup", () => {
  const defaults = parsing.parseMenuJsonc(fixture)
  const merged = parsing.mergeMenuSources(defaults, [], true)
  const item = merged.items["aranea.settings"]
  assert.ok(item, "installed settings adds its route")
  assert.equal(item.parent, "setup")
  assert.equal(item.label, "Aranea settings")
  assert.equal(
    item.action,
    `omarchy-shell shell summon araneadev.settings '{"section":"appearance"}'`
  )
  assert.ok(item.when, "activation remains guarded")
  assert.equal(merged.itemOrder.at(-1), "aranea.settings", "settings appends to existing order")
  assert.equal(merged.itemOrder.filter((id) => id === "aranea.settings").length, 1)
  sameAsFacade(parsing, "mergeMenuSources", [defaults, [], true])
  assert.equal(parsing.mergeMenuSources(defaults, [], false).items["aranea.settings"], undefined)
})

test("settings route preserves user overrides and unrelated commands", () => {
  const custom = parsing.parseMenuJsonc(
    '{"aranea.settings":{"parent":"setup","label":"My settings","action":"custom-settings","when":"true"},"setup.custom":{"label":"Mine","action":"custom"}}'
  )
  const merged = parsing.mergeMenuSources(parsing.parseMenuJsonc(fixture), custom, true)
  assert.equal(merged.items["aranea.settings"].label, "My settings")
  assert.equal(merged.items["aranea.settings"].action, "custom-settings")
  assert.equal(merged.items["aranea.settings"].when, "true")
  assert.equal(merged.items["setup.custom"].action, "custom")
  assert.equal(merged.itemOrder.filter((id) => id === "aranea.settings").length, 1)
})
