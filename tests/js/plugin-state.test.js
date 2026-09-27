// Logic contract for the plugin-state modules (moved from tests/plugin-state.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")

test("plugin-state logic", () => {
  const root = path.join(__dirname, "..", "..")
  const bar = require(`${root}/plugins/araneadev.bar/BarModel.js`)
  const notifications = require(`${root}/plugins/araneadev.notifications/NotificationLogic.js`)
  const menu = require(`${root}/plugins/araneadev.menu/MenuModel.js`)
  const fs = require("fs")

  for (const state of [
    "healthy",
    "focus",
    "attention",
    "warning",
    "error",
    "muted",
    "charging",
    "privacy"
  ]) {
    if (!bar.semanticColor(state)) throw new Error(`missing semantic state: ${state}`)
  }
  if (bar.semanticColor("unknown") !== "dark_foreground")
    throw new Error("unknown state must be muted")
  if (bar.normalizePosition("left") !== "left") throw new Error("bar position normalization failed")
  if (bar.normalizePosition("diagonal") !== "top")
    throw new Error("invalid bar position must fall back to top")
  const normalizedLayout = bar.normalizeLayout({
    left: [{ id: "omarchy.clock" }],
    center: "invalid"
  })
  if (!Array.isArray(normalizedLayout.left) || normalizedLayout.left.length !== 1)
    throw new Error("left layout normalization failed")
  if (!Array.isArray(normalizedLayout.center) || normalizedLayout.center.length !== 0)
    throw new Error("center layout fallback failed")
  if (!Array.isArray(normalizedLayout.right) || normalizedLayout.right.length !== 0)
    throw new Error("right layout fallback failed")
  // 4b: no profile filtering; the bar shows every configured module
  for (const gone of ["normalizeProfile", "profileAllows", "filterProfile"])
    if (bar[gone] !== undefined) throw new Error("bar profile helper still exported: " + gone)
  // 4b: glass by default; only an explicit false gives the opaque bar
  if (bar.barTransparent({}) !== true) throw new Error("missing transparent must be glass")
  if (bar.barTransparent({ transparent: true }) !== true) throw new Error("true must be glass")
  if (bar.barTransparent({ transparent: false }) !== false) throw new Error("false must be opaque")
  if (bar.barTransparent(null) !== true) throw new Error("non-object config must be glass")
  if (bar.barTransparent({ transparent: "false" }) !== true)
    throw new Error("only the boolean false is opaque")

  const grouped = notifications.groupNotifications([
    { app: "browser", summary: "One" },
    { app: "browser", summary: "Two" },
    { app: "terminal", summary: "Three" }
  ])
  if (grouped.length !== 2 || grouped[0].count !== 2)
    throw new Error("notifications were not grouped by app")

  const collapsed = notifications.collapseQuietHours([{ id: 1 }, { id: 2 }], true)
  if (collapsed.visible.length !== 0 || collapsed.count !== 2)
    throw new Error("quiet-hours collapse failed")

  const normalized = notifications.normalizeNotification({
    id: "not-a-number",
    appName: null,
    summary: 42,
    body: null,
    urgency: 99,
    expireTimeout: "not-a-number",
    hints: null
  })
  if (normalized.id !== 0 || normalized.appName !== "" || normalized.summary !== "42")
    throw new Error("notification fields were not normalized")
  if (normalized.urgency !== 1 || normalized.expireTimeout !== 0)
    throw new Error("invalid notification values were not defaulted")
  if (!normalized.hints || typeof normalized.hints !== "object")
    throw new Error("notification hints were not normalized")

  const malformedSnapshot = notifications.snapshotOf({ urgency: -1, hints: null }, "invalid")
  if (
    malformedSnapshot.urgency !== 1 ||
    typeof malformedSnapshot.timestamp !== "number" ||
    !Number.isFinite(malformedSnapshot.timestamp)
  ) {
    throw new Error("malformed notification snapshot was not stabilized")
  }

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
  if (
    menu.recordRecentApp(["org.alpha", "org.beta"], "org.alpha", 3).join(",") !==
    "org.alpha,org.beta"
  )
    throw new Error("recent app was not moved to the front")
  if (menu.recordRecentApp(["a", "b", "c"], "d", 3).join(",") !== "d,a,b")
    throw new Error("recent app history was not bounded")
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
  if (
    menu.semanticDetail({ id: "apps", parent: "root", label: "Apps" }, "Applications") !==
    "FIND // LAUNCH // MANAGE"
  ) {
    throw new Error("root Apps semantic subtitle was not normalized")
  }
  if (menu.semanticDetail({ parent: "apps", label: "Apps" }, "Applications") !== "Applications") {
    throw new Error("submenu detail was unexpectedly rewritten")
  }

  const bounded = notifications.limitHistory([{ id: 1 }, { id: 2 }, { id: 3 }], 2)
  if (bounded.length !== 2 || bounded[0].id !== 1) throw new Error("history was not bounded")

  const late = new Date(2026, 8, 22, 23, 15)
  const early = new Date(2026, 8, 23, 6, 45)
  const day = new Date(2026, 8, 22, 12, 0)
  if (!notifications.isWithinQuietHours("22:00-07:00", late))
    throw new Error("quiet hours missed late window")
  if (!notifications.isWithinQuietHours("22:00-07:00", early))
    throw new Error("quiet hours missed overnight window")
  if (notifications.isWithinQuietHours("22:00-07:00", day))
    throw new Error("quiet hours captured daytime")

  const service = fs.readFileSync(`${root}/plugins/araneadev.notifications/Service.qml`, "utf8")
  if (!service.includes("ARANEA_QUIET_HOURS"))
    throw new Error("quiet-hours env is not wired into the service")
  if (!service.includes("service.quietHours"))
    throw new Error("quiet-hours state is not used by notification handling")

  const menuQml = fs.readFileSync(`${root}/plugins/araneadev.menu/Menu.qml`, "utf8")
  const lockQml = fs.readFileSync(`${root}/plugins/araneadev.lock/Service.qml`, "utf8")
  const lockViewQml = fs.readFileSync(`${root}/plugins/araneadev.lock/LockView.qml`, "utf8")
  const notificationsQml = service
  const inboxQml = fs.readFileSync(`${root}/plugins/araneadev.notifications/Inbox.qml`, "utf8")
  const healthQml = fs.readFileSync(`${root}/plugins/araneadev.health/Monitor.qml`, "utf8")
  const metricsQml = fs.readFileSync(`${root}/plugins/araneadev.health/Metrics.qml`, "utf8")
  const barQml = fs.readFileSync(`${root}/plugins/araneadev.bar/Bar.qml`, "utf8")
  const menuBarWidgetQml = fs.readFileSync(`${root}/plugins/araneadev.menu/BarWidget.qml`, "utf8")
  const notificationCardQml = fs.readFileSync(
    `${root}/plugins/araneadev.notifications/components/NotificationCard.qml`,
    "utf8"
  )
  if (!menuBarWidgetQml.includes("aranea-glyph.svg"))
    throw new Error("bar menu trigger is missing reduced Aranea glyph")
  if (!notificationCardQml.includes("aranea-glyph.svg"))
    throw new Error("notification card is missing reduced Aranea glyph")
  if (!lockViewQml.includes("unlock.png"))
    throw new Error("lock surface is missing canonical Aranea spider")
  if (!lockViewQml.includes("y: Math.max(32, inputField.y - height - 42)"))
    throw new Error("lock branding is not anchored to the live field")
  if (!lockViewQml.includes("y: inputField.y + inputField.height + 28"))
    throw new Error("lock clock is not anchored to the live field")
  if (!lockViewQml.includes("y: parent.height - height - 34"))
    throw new Error("lock footer is not anchored to the live viewport")
  /** Throws with a labelled message unless source contains the given typed function signature. */
  function requiresSignature(source, signature, name) {
    if (!source.includes(signature)) throw new Error(`missing typed scalar contract: ${name}`)
  }

  requiresSignature(
    menuQml,
    "function rowListHeight(_serial: int, _count: int, _filter: string, _divider: bool): int",
    "menu rowListHeight"
  )
  requiresSignature(
    menuQml,
    "function dmenuRowListHeight(_serial: int, _count: int, _filter: string): int",
    "menu dmenuRowListHeight"
  )
  requiresSignature(menuQml, "function depthFor(id: string): int", "menu depthFor")
  requiresSignature(menuQml, "function pathFor(id: string): string", "menu pathFor")
  requiresSignature(
    menuQml,
    "function isDescendantOf(id: string, ancestorId: string): bool",
    "menu isDescendantOf"
  )
  requiresSignature(menuQml, "function childCount(id: string): int", "menu childCount")
  requiresSignature(menuQml, "function searchScore(entry, query: string): real", "menu searchScore")
  requiresSignature(menuQml, "function setFilter(nextFilter: string)", "menu setFilter")
  requiresSignature(menuQml, "function open(payloadJson: string): void", "menu open")
  requiresSignature(menuQml, "function select(delta: int): void", "menu select")
  requiresSignature(
    menuQml,
    "function setActiveMenu(id: string, pushHistory: bool, fromPointer: bool): void",
    "menu setActiveMenu"
  )
  requiresSignature(
    menuQml,
    "function activateIndex(index: int, fromPointer: bool): void",
    "menu activateIndex"
  )
  requiresSignature(
    menuQml,
    "function applyDmenuSelection(value: string): void",
    "menu applyDmenuSelection"
  )
  requiresSignature(menuQml, "function resolveRoute(input: string): string", "menu resolveRoute")
  requiresSignature(
    menuQml,
    "function toggleFavoriteApp(appId: string): void",
    "menu favorite toggle"
  )
  requiresSignature(menuQml, "function recordRecentApp(appId: string): void", "menu recent history")
  requiresSignature(
    menuQml,
    "function recordRecentApp(appId: string): void {\n    root.recentAppIds",
    "menu recent history implementation"
  )
  if (
    !menuQml.includes(
      "root.recentAppIds = MenuModel.recordRecentApp(root.recentAppIds, appId, root.recentAppLimit)\n    root.saveAppHistory()\n    root.mergeAppRows()"
    )
  ) {
    throw new Error("recent app history must refresh visible rows immediately")
  }
  requiresSignature(menuQml, "id: localAppLibrary", "menu local app-library fallback")
  requiresSignature(menuQml, "DesktopEntries.applications.values", "menu DesktopEntries fallback")
  requiresSignature(menuQml, "function openRoute(initialMenu: string): void", "menu openRoute")
  requiresSignature(menuQml, "function goBack(): bool", "menu goBack")
  requiresSignature(menuQml, "function runAction(action): void", "menu runAction")
  requiresSignature(menuQml, "function rebuildDisplay(): void", "menu rebuildDisplay")
  requiresSignature(menuQml, "function revealCursor(): void", "menu revealCursor")
  requiresSignature(
    menuQml,
    "function rebuildItemsFromSources(): void",
    "menu rebuildItemsFromSources"
  )
  requiresSignature(menuQml, "function startNextProvider(): void", "menu startNextProvider")
  requiresSignature(menuQml, "function rebuildDmenuDisplay(): void", "menu rebuildDmenuDisplay")
  requiresSignature(menuQml, "function cancel(): void", "menu cancel")
  requiresSignature(lockQml, "function logEvent(event: string)", "lock logEvent")
  requiresSignature(lockQml, "function submitPassword(value: string)", "lock submitPassword")
  requiresSignature(lockQml, "function recoverStrandedLock(): void", "lock recoverStrandedLock")
  requiresSignature(lockQml, "function refreshBackground(): void", "lock refreshBackground")
  requiresSignature(lockQml, "function finishUnlock(): void", "lock finishUnlock")
  requiresSignature(lockQml, "function runWake(): void", "lock runWake")
  requiresSignature(lockQml, "function checkStrandedLock(): void", "lock checkStrandedLock")
  requiresSignature(
    lockQml,
    "function refreshFingerprintStatus(): void",
    "lock refreshFingerprintStatus"
  )
  requiresSignature(
    lockQml,
    "function resetAuthenticationState(): void",
    "lock resetAuthenticationState"
  )
  requiresSignature(lockQml, "function runBlank(): void", "lock runBlank")
  requiresSignature(
    lockQml,
    "function respondToPasswordPrompt(): void",
    "lock respondToPasswordPrompt"
  )
  requiresSignature(lockViewQml, "function updateClock(): void", "lock view updateClock")
  requiresSignature(lockQml, "function queueSessionLock(): void", "lock queueSessionLock")
  requiresSignature(lockQml, "function requestSessionLock(): void", "lock requestSessionLock")
  requiresSignature(lockQml, "function armBlankTimer(): void", "lock armBlankTimer")
  requiresSignature(
    notificationsQml,
    "function setDoNotDisturb(value: bool)",
    "notification setDoNotDisturb"
  )
  requiresSignature(
    notificationsQml,
    "function isTransient(notification): bool",
    "notification isTransient"
  )
  requiresSignature(
    notificationsQml,
    "function shouldStore(notification, snapshot): bool",
    "notification shouldStore"
  )
  requiresSignature(
    notificationsQml,
    "function dismissPopup(index: int)",
    "notification dismissPopup"
  )
  requiresSignature(
    notificationsQml,
    "function removePopup(index: int, reason: string)",
    "notification removePopup"
  )
  requiresSignature(notificationsQml, "function clearPopups(): void", "notification clearPopups")
  requiresSignature(
    notificationsQml,
    "function expirePopup(index: int): void",
    "notification expirePopup"
  )
  requiresSignature(
    notificationsQml,
    "function loadSettings(raw: string): void",
    "notification loadSettings"
  )
  requiresSignature(
    notificationsQml,
    "function scheduleSettingsSave(): void",
    "notification scheduleSettingsSave"
  )
  requiresSignature(
    notificationsQml,
    "function flushSettings(): void",
    "notification flushSettings"
  )
  requiresSignature(notificationsQml, "function toggleCenter(): void", "notification toggleCenter")
  requiresSignature(notificationsQml, "function clearInbox(): void", "notification clearInbox")
  requiresSignature(metricsQml, "function sample(): void", "metrics sample")
  requiresSignature(metricsQml, "function refreshSlow(): void", "metrics refreshSlow")
  requiresSignature(healthQml, "function reconcileNow(): void", "health reconcileNow")
  requiresSignature(healthQml, "function checkUnits(): void", "health checkUnits")
  requiresSignature(healthQml, "function checkDisk(): void", "health checkDisk")
  requiresSignature(healthQml, "function checkReboot(): void", "health checkReboot")
  requiresSignature(healthQml, "function startDocker(): void", "health startDocker")
  requiresSignature(inboxQml, "function upsert(entry: var): void", "inbox upsert")
  requiresSignature(inboxQml, "function remove(fileName: string): void", "inbox remove")
  requiresSignature(inboxQml, "function clear(): void", "inbox clear")
  requiresSignature(inboxQml, "function runNext(): void", "inbox runNext")
  requiresSignature(inboxQml, "function sweepOrphanImages(): void", "inbox sweepOrphanImages")
  requiresSignature(barQml, "function publicLayoutConfig(): var", "bar publicLayoutConfig")
  requiresSignature(barQml, "function slotScreenName(slot): string", "bar slotScreenName")
  requiresSignature(barQml, "function focusedScreenName(): string", "bar focusedScreenName")
  requiresSignature(
    barQml,
    "function isBarWidgetOpen(pluginId: string): bool",
    "bar isBarWidgetOpen"
  )
  requiresSignature(barQml, "function expandPath(path: string): string", "bar expandPath")
  requiresSignature(
    barQml,
    "function pluginBarApiUsed(pluginId: string): bool",
    "bar pluginBarApiUsed"
  )
  requiresSignature(barQml, "function moduleWidgets(pluginId: string): var", "bar moduleWidgets")
  requiresSignature(barQml, "function run(command): void", "bar run")
  requiresSignature(barQml, "function toggleTransparency(): void", "bar toggleTransparency")
  requiresSignature(
    barQml,
    "function setRequestedTransparency(value: bool): void",
    "bar setRequestedTransparency"
  )
  requiresSignature(
    barQml,
    "function syncAllPluginBarApiObjects(): void",
    "bar syncAllPluginBarApiObjects"
  )
  requiresSignature(barQml, "function clearTooltip(): void", "bar clearTooltip")
  requiresSignature(barQml, "function clearBarDrag(): void", "bar clearBarDrag")
  requiresSignature(barQml, "function clearBarMove(): void", "bar clearBarMove")
  requiresSignature(barQml, "function prunePluginBarApis(): void", "bar prunePluginBarApis")
  requiresSignature(barQml, "function applyBarConfig(): void", "bar applyBarConfig")
  requiresSignature(
    barQml,
    "function restoreForegroundAnimation(): void",
    "bar restoreForegroundAnimation"
  )
  requiresSignature(
    barQml,
    "function refreshTransparentForeground(): void",
    "bar refreshTransparentForeground"
  )
})

test("bar model layout helpers (4b)", () => {
  const bar = require(path.join(__dirname, "..", "..", "plugins/araneadev.bar/BarModel.js"))
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  const layout = ["omarchy.a", { id: "omarchy.clock", format: "HH:mm" }, { id: "omarchy.b" }]
  eq(bar.entryId("omarchy.a"), "omarchy.a", "string id")
  eq(bar.entryId({ id: 7 }), "7", "object id")
  eq(bar.entryId({}), "", "no id")
  eq(bar.entrySettings({ id: "x", format: "y" }), { format: "y" }, "settings without id")
  eq(bar.moduleString(layout[1], "format", "?"), "HH:mm", "module string")
  eq(bar.moduleString(layout[1], "missing", "?"), "?", "module string fallback")
  eq(bar.entryIndex(layout, "omarchy.clock"), 1, "index")
  eq(bar.entriesBefore(layout, "omarchy.clock"), ["omarchy.a"], "before anchor")
  eq(bar.entriesAfter(layout, "omarchy.clock"), [{ id: "omarchy.b" }], "after anchor")
  eq(bar.entriesAfter(layout, "missing"), [], "after missing anchor")
  eq(
    bar.pinTrayToInner(["omarchy.tray", "a", "b"], "left"),
    ["a", "b", "omarchy.tray"],
    "tray inner on the left"
  )
  eq(bar.pinTrayToInner(["a", "omarchy.tray"], "right"), ["omarchy.tray", "a"], "tray inner right")
  eq(bar.expandPath("~/x", "/home/u"), "/home/u/x", "tilde")
  eq(bar.expandPath("$HOME/x", "/home/u"), "/home/u/x", "$HOME")
  eq(bar.customModuleSafeName("../evil"), false, "unsafe name")
  eq(bar.customModuleType({ id: "x", exec: "date" }), "command", "command module")
  eq(bar.customModuleType({ id: "x", source: "a.qml" }), "qml", "qml module")
  eq(
    bar.customModulePath({ id: "clock2" }, "/h", "/c"),
    "/c/bar/modules/clock2.qml",
    "default path"
  )
  eq(bar.isDrawnSlot({ visible: true, width: 2, height: 2 }), true, "drawn slot")
  eq(bar.isDrawnSlot({ visible: false, width: 2, height: 2 }), false, "hidden slot")
})

test("menu model (4b)", () => {
  const menu = require(path.join(__dirname, "..", "..", "plugins/araneadev.menu/MenuModel.js"))
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
    ["apps.recent.firefox", "apps.favorites", "setup.x", "apps.files"],
    "dedupe keeps first per app"
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
    ["apps.recent", "apps.favorites", "apps.alpha", "apps.zed"],
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
