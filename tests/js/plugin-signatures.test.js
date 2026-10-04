// Logic contract for the plugin QML typed-signature and manifest markers
// (split from plugin-state.test.js). Run with `node --test tests/js/`
// (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")
const fs = require("fs")

const root = path.join(__dirname, "..", "..")

const service = fs.readFileSync(`${root}/plugins/araneadev.notifications/Service.qml`, "utf8")
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

/** Throws with a labelled message unless source contains the given typed function signature. */
function requiresSignature(source, signature, name) {
  if (!source.includes(signature)) throw new Error(`missing typed scalar contract: ${name}`)
}

test("notification quiet-hours markers are wired into Service.qml", () => {
  if (!service.includes("ARANEA_QUIET_HOURS"))
    throw new Error("quiet-hours env is not wired into the service")
  if (!service.includes("service.quietHours"))
    throw new Error("quiet-hours state is not used by notification handling")
})

test("bar and notification surfaces use the shared brand mark, lock surface keeps its spider art", () => {
  if (!menuBarWidgetQml.includes("RuntimePaths.brandUrl"))
    throw new Error("bar menu trigger is missing the shared brand mark")
  if (!notificationCardQml.includes("RuntimePaths.glyphUrl"))
    throw new Error("notification card is missing the shared brand mark")
  if (!lockViewQml.includes("RuntimePaths.brandUrl"))
    throw new Error("lock surface is missing the canonical brand mark")
  if (!lockViewQml.includes("y: Math.max(32, inputField.y - height - 49)"))
    throw new Error("lock branding is not anchored to the live field")
  if (!lockViewQml.includes("y: inputField.y + inputField.height + 19"))
    throw new Error("lock clock is not anchored to the live field")
  if (!lockViewQml.includes("y: parent.height - height - 54"))
    throw new Error("lock footer is not anchored to the live viewport")
})

test("menu QML exposes its typed function signatures", () => {
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
  requiresSignature(menuQml, "function setFilter(nextFilter: string)", "menu setFilter")
  requiresSignature(menuQml, "function open(payloadJson: string): void", "menu open")
  requiresSignature(menuQml, "function select(delta: int): void", "menu select")
  requiresSignature(
    menuQml,
    "function setActiveMenu(id: string, pushHistory: bool): void",
    "menu setActiveMenu"
  )
  requiresSignature(menuQml, "function activateIndex(index: int): void", "menu activateIndex")
  requiresSignature(
    menuQml,
    "function activateKey(index: int, key: string): bool",
    "menu activateKey"
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
  const menuHistoryQml = fs.readFileSync(
    `${root}/plugins/araneadev.menu/MenuAppHistory.qml`,
    "utf8"
  )
  requiresSignature(
    menuQml,
    "function recordRecentApp(appId: string): void {\n    history.recordRecent(appId)",
    "menu recent history forwards to MenuAppHistory"
  )
  if (
    !menuHistoryQml.includes(
      "history.recentAppIds = MenuModel.recordRecentApp(history.recentAppIds, appId, history.recentAppLimit)\n    history.saveAppHistory()\n    history.updated()"
    )
  )
    throw new Error("recent app history must refresh visible rows immediately")
  requiresSignature(menuHistoryQml, "function rowsFor(library: var): var", "menu app rows")
  requiresSignature(menuQml, "id: localAppLibrary", "menu local app-library fallback")
  const menuAppLibraryQml = fs.readFileSync(
    `${root}/plugins/araneadev.menu/MenuAppLibrary.qml`,
    "utf8"
  )
  requiresSignature(
    menuAppLibraryQml,
    "DesktopEntries.applications.values",
    "menu DesktopEntries fallback"
  )
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
  const menuProvidersQml = fs.readFileSync(
    `${root}/plugins/araneadev.menu/MenuProviders.qml`,
    "utf8"
  )
  requiresSignature(
    menuProvidersQml,
    "function startNextProvider(): void",
    "menu providers startNextProvider"
  )
  requiresSignature(menuQml, "function rebuildDmenuDisplay(): void", "menu rebuildDmenuDisplay")
  requiresSignature(menuQml, "function cancel(): void", "menu cancel")

  for (const wrapper of [
    "stripJsonc",
    "normalizeAliases",
    "normalizeItem",
    "parseMenuJsonc",
    "slugify",
    "depthFor",
    "pathFor",
    "parentPathFor",
    "isDescendantOf",
    "childCount",
    "isVisible",
    "labelFor",
    "searchableToken",
    "leafIdFor",
    "nameSearchText",
    "termInSearchWords",
    "descriptionTextMatches",
    "matchesQuery",
    "searchScore",
    "displayRow"
  ]) {
    if (menuQml.includes(`function ${wrapper}(`))
      throw new Error(`menu wrapper ${wrapper} is back; call MenuModel.${wrapper} directly`)
  }
})

test("lock and lock-view QML expose their typed function signatures", () => {
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
})

test("notification QML exposes its typed function signatures", () => {
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
})

test("metrics and health QML expose their typed function signatures", () => {
  requiresSignature(metricsQml, "function sample(): void", "metrics sample")
  requiresSignature(metricsQml, "function refreshSlow(): void", "metrics refreshSlow")
  requiresSignature(healthQml, "function reconcileNow(): void", "health reconcileNow")
  requiresSignature(healthQml, "function checkUnits(): void", "health checkUnits")
  requiresSignature(healthQml, "function checkDisk(): void", "health checkDisk")
  requiresSignature(healthQml, "function checkReboot(): void", "health checkReboot")
  requiresSignature(healthQml, "function startDocker(): void", "health startDocker")
})

test("inbox QML exposes its typed function signatures", () => {
  requiresSignature(inboxQml, "function upsert(entry: var): void", "inbox upsert")
  requiresSignature(inboxQml, "function remove(fileName: string): void", "inbox remove")
  requiresSignature(inboxQml, "function clear(): void", "inbox clear")
  requiresSignature(inboxQml, "function runNext(): void", "inbox runNext")
  requiresSignature(inboxQml, "function sweepOrphanImages(): void", "inbox sweepOrphanImages")
})

test("bar QML exposes its typed function signatures", () => {
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
