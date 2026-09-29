// Logic contract for the MenuModel module (split from plugin-state.test.js).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const menu = loadPragma("plugins/araneadev.menu/MenuModel.js")
const history = loadPragma("plugins/araneadev.menu/MenuHistory.js")

test("menu history owns recent-app ordering", () => {
  if (
    JSON.stringify(history.recordRecentApp(["two", "one"], "three", 3)) !==
    JSON.stringify(["three", "two", "one"])
  )
    throw new Error("recent-app ordering")
})

test("menu model normalizeItem coerces mismatched types and falls back for invalid items", () => {
  const normalizedItem = menu.normalizeItem("tools.editor", {
    parent: 42,
    label: 7,
    aliases: ["edit", 12, null],
    target: 9,
    description: null
  })
  if (
    normalizedItem.parent !== "42" ||
    normalizedItem.label !== "7" ||
    normalizedItem.target !== "9"
  )
    throw new Error("menu item fields were not normalized")
  if (normalizedItem.aliases.length !== 2 || normalizedItem.aliases[1] !== "12")
    throw new Error("menu aliases were not normalized")
  if (menu.normalizeItem("bad", []).label !== "bad")
    throw new Error("invalid menu item did not get a stable fallback")
})

test("menu model favorites: normalize ids, add, remove and refuse beyond the limit", () => {
  const favoriteIds = menu.normalizeAppIds(["org.alpha", "org.alpha", 7, null, ""], 3)
  if (favoriteIds.length !== 2 || favoriteIds[1] !== "7")
    throw new Error("favorite app ids were not normalized")
  const added = menu.toggleFavoriteApp(favoriteIds, "org.beta", 3)
  if (added.ids.join(",") !== "org.beta,org.alpha,7" || added.refused)
    throw new Error("favorite app was not added at the front")
  const removed = menu.toggleFavoriteApp(["org.alpha", "org.beta"], "org.alpha", 3)
  if (removed.ids.join(",") !== "org.beta" || removed.refused)
    throw new Error("favorite app was not removed")
  const full = menu.toggleFavoriteApp(["a", "b", "c"], "d", 3)
  if (full.ids.join(",") !== "a,b,c" || full.refused !== true)
    throw new Error("a pin beyond the limit must be refused, not drop the oldest")
})

test("menu model recordRecentApp moves apps to the front and bounds history", () => {
  if (
    menu.recordRecentApp(["org.alpha", "org.beta"], "org.alpha", 3).join(",") !==
    "org.alpha,org.beta"
  )
    throw new Error("recent app was not moved to the front")
  if (menu.recordRecentApp(["a", "b", "c"], "d", 3).join(",") !== "d,a,b")
    throw new Error("recent app history was not bounded")
})

test("menu model appRowsForIds projects favorite app ids into their submenu rows", () => {
  const appRows = [
    { id: "apps.alpha", appId: "org.alpha", parent: "apps", kind: "app", label: "Alpha" },
    { id: "apps.beta", appId: "org.beta", parent: "apps", kind: "app", label: "Beta" }
  ]
  const favoriteRows = menu.appRowsForIds(
    appRows,
    ["org.beta", "missing"],
    "apps.favorites",
    "apps.favorites"
  )
  if (
    favoriteRows.length !== 1 ||
    favoriteRows[0].id !== "apps.favorites.org.beta" ||
    favoriteRows[0].parent !== "apps.favorites"
  ) {
    throw new Error("favorite app rows were not projected into their submenu")
  }
})

test("menu model semanticDetail rewrites the root Apps subtitle only", () => {
  if (
    menu.semanticDetail({ id: "apps", parent: "root", label: "Apps" }, "Applications") !==
    "FIND // LAUNCH // MANAGE"
  ) {
    throw new Error("root Apps semantic subtitle was not normalized")
  }
  if (menu.semanticDetail({ parent: "apps", label: "Apps" }, "Applications") !== "Applications") {
    throw new Error("submenu detail was unexpectedly rewritten")
  }
})

test("menu model (4b)", () => {
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  // state file
  eq(menu.parseAppHistory("", 12), { favorites: [], recent: [] }, "missing file")
  eq(menu.parseAppHistory("not json", 12), { favorites: [], recent: [] }, "corrupt file")
  eq(menu.parseAppHistory("[]", 12), { favorites: [], recent: [] }, "array")
  eq(menu.parseAppHistory('{"favorites":"x"}', 12), { favorites: [], recent: [] }, "wrong type")
  eq(
    menu.parseAppHistory('{"favorites":["a"," a ","b",7,""],"recent":["c"]}', 12),
    { favorites: ["a", "b", "7"], recent: ["c"] },
    "normalized"
  )
  const many = JSON.stringify({ favorites: Array.from({ length: 20 }, (_, i) => "app" + i) })
  eq(menu.parseAppHistory(many, 12).favorites.length, 12, "limit")
  eq(
    JSON.parse(menu.serializeAppHistory(["a", "a"], ["b"], 12)),
    { favorites: ["a"], recent: ["b"] },
    "serialize"
  )
  eq(menu.pruneAppIds(["a", "gone", "b"], ["b", "a"]), ["a", "b"], "prune uninstalled")
  eq(menu.pruneAppIds(["a"], null), ["a"], "unknown library keeps ids")
  // search shows each app once
  const rows = [
    { kind: "app", appId: "firefox", itemId: "apps.recent.firefox" },
    { kind: "menu", appId: "", itemId: "apps.favorites" },
    { kind: "app", appId: "firefox", itemId: "apps.firefox" },
    { kind: "action", appId: "", itemId: "setup.x" },
    { kind: "app", appId: "files", itemId: "apps.files" }
  ]
  eq(
    menu.dedupeAppRows(rows).map((r) => r.itemId),
    ["apps.favorites", "apps.firefox", "setup.x", "apps.files"],
    "dedupe keeps the real row per app"
  )
  // Apps: menus first in their order, apps by label
  eq(
    menu
      .sortAppsMenu([
        { kind: "app", label: "zed", itemId: "apps.zed", order: 0 },
        { kind: "menu", label: "Recent", itemId: "apps.recent", order: 0 },
        { kind: "app", label: "Alpha", itemId: "apps.alpha", order: 3 },
        { kind: "menu", label: "Favorites", itemId: "apps.favorites", order: 1 }
      ])
      .map((r) => r.itemId),
    ["apps.favorites", "apps.recent", "apps.alpha", "apps.zed"],
    "apps sort"
  )
  // hints
  const h = (s) =>
    menu.hintText(
      Object.assign(
        { root: false, filter: false, dmenu: false, input: false, count: 0, appRow: false },
        s
      )
    )
  eq(h({ root: true }), "SYSTEM // READY", "root")
  eq(h({ filter: true }), "ESC CLEAR  ·  ENTER OPEN", "filter")
  eq(h({}), "⌫ BACK  ·  ENTER OPEN  ·  ESC CLOSE", "submenu")
  eq(h({ appRow: true }), "⌫ BACK  ·  ENTER OPEN  ·  ^P PIN  ·  ESC CLOSE", "app row")
  eq(h({ dmenu: true, input: true }), "TYPE TO FILTER  ·  ESC CANCEL", "dmenu input")
  eq(h({ dmenu: true, count: 4 }), "4 RESULTS  ·  ENTER SELECT  ·  ESC CANCEL", "dmenu select")
  // empty state
  eq(menu.emptyState({ loading: true, error: false, filter: "" }).text, "Loading…", "loading")
  eq(
    menu.emptyState({ loading: false, error: true, filter: "" }).text,
    "Couldn’t load this list",
    "error"
  )
  eq(
    menu.emptyState({ loading: true, error: true, filter: "fox" }).text,
    "No matches for “fox”",
    "search wins"
  )
  eq(
    menu.emptyState({ loading: false, error: false, filter: "" }).text,
    "Nothing here yet",
    "empty"
  )
  // taglines by id
  eq(
    menu.semanticDetail({ id: "system", parent: "root", label: "System" }, "desc"),
    "SLEEP // RESTART // SHUTDOWN",
    "system tagline"
  )
  eq(
    menu.semanticDetail({ id: "install", parent: "root", label: "Install" }, "desc"),
    "desc",
    "other roots keep description"
  )
  // merges do not mutate their input
  const incoming = [{ id: "apps.x", kind: "app" }]
  menu.mergeAppRows({}, [], incoming)
  eq(incoming[0].order, undefined, "mergeAppRows mutated its input")
  const provided = [{ id: "fonts.a", kind: "action" }]
  menu.swapProviderRows({}, [], "fonts", provided)
  eq(provided[0].providerMenu, undefined, "swapProviderRows mutated its input")
  eq(menu.dynamicTileForAppRows, undefined, "dead tile helper removed")
})

test("menu model final review fixes (4b)", () => {
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  // I1: the real apps.<id> row wins even when a Recent/Favorites copy ranks higher
  eq(
    menu
      .dedupeAppRows([
        { kind: "app", appId: "zen", itemId: "apps.recent.zen" },
        { kind: "app", appId: "zen", itemId: "apps.favorites.zen" },
        { kind: "app", appId: "vim", itemId: "apps.recent.vim" },
        { kind: "app", appId: "zen", itemId: "apps.zen" }
      ])
      .map((r) => r.itemId),
    ["apps.recent.vim", "apps.zen"],
    "real row preferred, copies without a real row kept once"
  )
  // m4: each list has its own limit
  const long = Array.from({ length: 20 }, (_, i) => "a" + i)
  const parsed = menu.parseAppHistory(JSON.stringify({ favorites: long, recent: long }), 12, 16)
  eq([parsed.favorites.length, parsed.recent.length], [12, 16], "separate parse limits")
  const saved = JSON.parse(menu.serializeAppHistory(long, long, 12, 16))
  eq([saved.favorites.length, saved.recent.length], [12, 16], "separate save limits")
  // m5: only strings and finite numbers are ids
  eq(menu.normalizeAppIds(["a", {}, [], null, NaN, 7, true], 12), ["a", "7"], "id types")
})
