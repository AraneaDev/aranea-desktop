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

test("command center groups software and configuration without losing routes", () => {
  const defaults = parsing.parseMenuJsonc(
    JSON.stringify(
      Object.fromEntries(
        [
          "apps",
          "learn",
          "trigger",
          "style",
          "setup",
          "install",
          "remove",
          "update",
          "about",
          "system"
        ].map((id) => [id, { label: id }])
      )
    )
  )
  defaults.push(parsing.normalizeItem("install.package", { action: "install-package" }))
  const merged = parsing.mergeMenuSources(defaults, [], true)
  assert.deepEqual(
    plain(facade.mergeMenuSources(defaults, [], true)),
    plain(merged),
    "public facade preserves grouped routes"
  )
  const withoutSettings = facade.mergeMenuSources(defaults, [], false)
  assert.equal(
    withoutSettings.items.about.parent,
    "learn",
    "Help retains About when Settings is unavailable"
  )
  assert.equal(
    withoutSettings.items["aranea.settings"],
    undefined,
    "unavailable Settings is not injected"
  )
  const roots = merged.itemOrder.filter((id) => merged.items[id].parent === "root")
  assert.deepEqual(plain(roots), ["apps", "trigger", "software", "settings", "learn", "system"])
  assert.equal(merged.items.trigger.label, "Actions")
  assert.equal(merged.items.learn.label, "Help")
  for (const id of ["install", "remove", "update"])
    assert.equal(merged.items[id].parent, "software")
  assert.equal(merged.items["aranea.settings"].label, "Aranea")
  for (const id of ["style", "setup", "aranea.settings"])
    assert.equal(merged.items[id].parent, "settings")
  assert.equal(merged.items["install.package"].action, "install-package")
  assert.equal(facade.resolveRoute(merged.items, merged.itemOrder, "install"), "install")
  assert.equal(
    facade.resolveRoute(merged.items, merged.itemOrder, "aranea-settings"),
    "aranea.settings"
  )
  const custom = parsing.parseMenuJsonc(
    '{"about":{"action":"custom-about"},"settings":{"action":"custom-settings"}}'
  )
  const overridden = parsing.mergeMenuSources(defaults, custom, true)
  assert.deepEqual(
    plain(facade.mergeMenuSources(defaults, custom, true)),
    plain(overridden),
    "public facade respects custom group destinations"
  )
  assert.ok(overridden.items.about, "custom About action stays available")
  assert.equal(overridden.items.about.action, "custom-about")
  assert.equal(overridden.items.style.parent, "root", "action destinations cannot contain menus")
  assert.equal(overridden.items.install.parent, "root", "skip folding when a group collides")
})

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

test("settings route is guarded, unique, and searchable on the root", () => {
  const defaults = parsing.parseMenuJsonc(fixture)
  const merged = parsing.mergeMenuSources(defaults, [], true)
  const item = merged.items["aranea.settings"]
  assert.ok(item, "installed settings adds its route")
  assert.equal(item.parent, "root")
  assert.equal(item.label, "Settings")
  assert.equal(
    item.icon,
    "aranea-brand",
    "settings has a monochrome brand icon instead of an empty icon slot"
  )
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

test("root Settings replaces About in its original command position", () => {
  const defaults = parsing.parseMenuJsonc(
    '{"apps":{"label":"Apps"},"setup":{"label":"Setup"},"about":{"label":"About","action":"about"},"system":{"label":"System"}}'
  )
  const merged = parsing.mergeMenuSources(defaults, [], true)
  assert.equal(merged.items.about, undefined)
  assert.deepEqual(plain(merged.itemOrder), ["root", "apps", "setup", "aranea.settings", "system"])
  assert.equal(merged.items["aranea.settings"].parent, "root")
  assert.equal(merged.items["aranea.settings"].label, "Settings")
  assert.equal(parsing.mergeMenuSources(defaults, [], false).items.about.action, "about")
  sameAsFacade(parsing, "mergeMenuSources", [defaults, [], true])
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

for (const [name, model] of [
  ["module", parsing],
  ["facade", facade]
]) {
  test(`${name} merges partial overrides without changing first-seen order or input items`, () => {
    const defaults = [
      { id: "apps", parent: "root", label: "Apps", provider: "apps", aliases: ["launch"] },
      { id: "root", parent: "", label: "Custom root" },
      { id: "apps", description: "Applications" },
      { id: "", label: "Ignored" }
    ]
    const user = [
      { id: "apps", label: "Launch" },
      { id: "extra", parent: "root" }
    ]
    const before = JSON.stringify([defaults, user])
    const result = model.mergeMenuSources(defaults, user)
    assert.deepEqual(plain(result.itemOrder), ["apps", "root", "extra"])
    assert.deepEqual(plain(result.items.apps), {
      id: "apps",
      parent: "root",
      label: "Launch",
      provider: "apps",
      aliases: ["launch"],
      description: "Applications",
      order: 0
    })
    assert.equal(result.items.root.label, "Custom root")
    assert.equal(result.items.root.order, 1)
    assert.equal(result.items.extra.order, 2)
    assert.equal(JSON.stringify([defaults, user]), before)
  })

  test(`${name} exempts custom stock IDs from regrouping and relabeling`, () => {
    const defaults = parsing.parseMenuJsonc(`{
      "apps": {}, "learn": {}, "trigger": {}, "style": {}, "setup": {},
      "install": {}, "remove": {}, "update": {}, "about": {}, "system": {},
      "install.package": {"action": "install-package"}
    }`)
    const user = ["learn", "trigger", "style", "setup", "install", "remove", "update"].map(
      (id) => ({ id, label: `My ${id}`, parent: "apps" })
    )
    user.push(
      { id: "aranea.settings", label: "My Aranea", parent: "apps" },
      { id: "about", label: "My About", parent: "apps" }
    )
    const before = JSON.stringify([defaults, user])
    const result = model.mergeMenuSources(defaults, user, true, true)
    assert.deepEqual(plain(result.itemOrder), [
      "root",
      "apps",
      "trigger",
      "software",
      "settings",
      "learn",
      "system",
      "style",
      "setup",
      "install",
      "remove",
      "update",
      "about",
      "install.package",
      "aranea.settings",
      "aranea.projects"
    ])
    for (const item of user) {
      assert.equal(result.items[item.id].label, item.label)
      assert.equal(result.items[item.id].parent, "apps")
    }
    assert.equal(result.items["install.package"].parent, "install")
    assert.equal(result.items["install.package"].action, "install-package")
    assert.equal(JSON.stringify([defaults, user]), before)
    for (const [index, id] of result.itemOrder.entries())
      assert.equal(result.items[id].order, index)
  })

  test(`${name} injects missing plugin destinations and preserves existing Projects`, () => {
    const result = model.mergeMenuSources([], [], true, true)
    assert.deepEqual(plain(result.itemOrder), ["root", "aranea.settings", "aranea.projects"])
    assert.equal(result.items["aranea.projects"].parent, "root")
    assert.equal(
      result.items["aranea.projects"].action,
      "omarchy-shell shell summon araneadev.projects"
    )
    assert.equal(
      result.items["aranea.projects"].when,
      'test -f "$HOME/.config/omarchy/plugins/araneadev.projects/manifest.json"'
    )
    assert.deepEqual(plain(model.mergeMenuSources([], []).itemOrder), ["root"])
    const custom = [{ id: "aranea.projects", parent: "apps", action: "my-projects" }]
    const overridden = model.mergeMenuSources(
      custom,
      [{ id: "aranea.projects", label: "Mine" }],
      false,
      true
    )
    assert.deepEqual(plain(overridden.itemOrder), ["root", "aranea.projects"])
    assert.equal(overridden.items["aranea.projects"].action, "my-projects")
    assert.equal(overridden.items["aranea.projects"].label, "Mine")
    assert.equal(overridden.items["aranea.projects"].parent, "apps")
  })
}
