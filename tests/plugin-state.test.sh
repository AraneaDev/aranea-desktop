#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node - "$repo_root" <<'NODE'
const root = process.argv[2]
const bar = require(`${root}/plugins/araneadev.bar/BarModel.js`)
const notifications = require(`${root}/plugins/araneadev.notifications/NotificationLogic.js`)
const menu = require(`${root}/plugins/araneadev.menu/MenuModel.js`)
const fs = require('fs')

for (const state of ['healthy', 'focus', 'attention', 'warning', 'error', 'muted', 'charging', 'privacy']) {
  if (!bar.semanticColor(state)) throw new Error(`missing semantic state: ${state}`)
}
if (bar.semanticColor('unknown') !== 'dark_foreground') throw new Error('unknown state must be muted')
if (bar.normalizeProfile('diagnostic') !== 'diagnostic') throw new Error('diagnostic profile missing')
if (bar.normalizeProfile('invalid') !== 'minimal') throw new Error('invalid profile must fall back to minimal')
if (bar.normalizePosition('left') !== 'left') throw new Error('bar position normalization failed')
if (bar.normalizePosition('diagonal') !== 'top') throw new Error('invalid bar position must fall back to top')
const normalizedLayout = bar.normalizeLayout({ left: [{ id: 'omarchy.clock' }], center: 'invalid' })
if (!Array.isArray(normalizedLayout.left) || normalizedLayout.left.length !== 1) throw new Error('left layout normalization failed')
if (!Array.isArray(normalizedLayout.center) || normalizedLayout.center.length !== 0) throw new Error('center layout fallback failed')
if (!Array.isArray(normalizedLayout.right) || normalizedLayout.right.length !== 0) throw new Error('right layout fallback failed')
if (!bar.profileAllows('minimal', 'omarchy.clock')) throw new Error('minimal profile hid the clock')
if (!bar.profileAllows('minimal', 'omarchy.microphone')) throw new Error('minimal profile hid microphone state')
if (bar.profileAllows('minimal', 'omarchy.weather')) throw new Error('minimal profile kept weather telemetry')
if (!bar.profileAllows('diagnostic', 'omarchy.weather')) throw new Error('diagnostic profile hid weather telemetry')
if (bar.filterProfile([{ id: 'omarchy.clock' }, { id: 'omarchy.weather' }], 'minimal').length !== 1) throw new Error('profile filter failed')

const grouped = notifications.groupNotifications([
  { app: 'browser', summary: 'One' },
  { app: 'browser', summary: 'Two' },
  { app: 'terminal', summary: 'Three' }
])
if (grouped.length !== 2 || grouped[0].count !== 2) throw new Error('notifications were not grouped by app')

const collapsed = notifications.collapseQuietHours([{ id: 1 }, { id: 2 }], true)
if (collapsed.visible.length !== 0 || collapsed.count !== 2) throw new Error('quiet-hours collapse failed')

const normalized = notifications.normalizeNotification({
  id: 'not-a-number',
  appName: null,
  summary: 42,
  body: null,
  urgency: 99,
  expireTimeout: 'not-a-number',
  hints: null
})
if (normalized.id !== 0 || normalized.appName !== '' || normalized.summary !== '42') throw new Error('notification fields were not normalized')
if (normalized.urgency !== 1 || normalized.expireTimeout !== 0) throw new Error('invalid notification values were not defaulted')
if (!normalized.hints || typeof normalized.hints !== 'object') throw new Error('notification hints were not normalized')

const malformedSnapshot = notifications.snapshotOf({ urgency: -1, hints: null }, 'invalid')
if (malformedSnapshot.urgency !== 1 || typeof malformedSnapshot.timestamp !== 'number' || !Number.isFinite(malformedSnapshot.timestamp)) {
  throw new Error('malformed notification snapshot was not stabilized')
}

const normalizedItem = menu.normalizeItem('tools.editor', {
  parent: 42,
  label: 7,
  aliases: ['edit', 12, null],
  target: 9,
  description: null
})
if (normalizedItem.parent !== '42' || normalizedItem.label !== '7' || normalizedItem.target !== '9') throw new Error('menu item fields were not normalized')
if (normalizedItem.aliases.length !== 2 || normalizedItem.aliases[1] !== '12') throw new Error('menu aliases were not normalized')
if (menu.normalizeItem('bad', []).label !== 'bad') throw new Error('invalid menu item did not get a stable fallback')

const favoriteIds = menu.normalizeAppIds(['org.alpha', 'org.alpha', 7, null, ''], 3)
if (favoriteIds.length !== 2 || favoriteIds[1] !== '7') throw new Error('favorite app ids were not normalized')
if (menu.toggleFavoriteApp(favoriteIds, 'org.beta', 3).join(',') !== 'org.beta,org.alpha,7') throw new Error('favorite app was not added at the front')
if (menu.toggleFavoriteApp(['org.alpha', 'org.beta'], 'org.alpha', 3).join(',') !== 'org.beta') throw new Error('favorite app was not removed')
if (menu.recordRecentApp(['org.alpha', 'org.beta'], 'org.alpha', 3).join(',') !== 'org.alpha,org.beta') throw new Error('recent app was not moved to the front')
if (menu.recordRecentApp(['a', 'b', 'c'], 'd', 3).join(',') !== 'd,a,b') throw new Error('recent app history was not bounded')
const appRows = [
  { id: 'apps.alpha', appId: 'org.alpha', parent: 'apps', kind: 'app', label: 'Alpha' },
  { id: 'apps.beta', appId: 'org.beta', parent: 'apps', kind: 'app', label: 'Beta' }
]
const favoriteRows = menu.appRowsForIds(appRows, ['org.beta', 'missing'], 'apps.favorites', 'apps.favorites')
if (favoriteRows.length !== 1 || favoriteRows[0].id !== 'apps.favorites.org.beta' || favoriteRows[0].parent !== 'apps.favorites') {
  throw new Error('favorite app rows were not projected into their submenu')
}
const pinnedTile = menu.dynamicTileForAppRows(appRows, ['org.beta'], ['org.alpha'], 'workspace-1')
if (pinnedTile.source !== 'pinned' || pinnedTile.label !== 'Beta' || pinnedTile.detail !== 'PINNED') {
  throw new Error('favorite app did not win dynamic tile resolution')
}
const recentTile = menu.dynamicTileForAppRows(appRows, [], ['org.alpha'], 'workspace-1')
if (recentTile.source !== 'recent' || recentTile.label !== 'Alpha' || recentTile.detail !== 'RECENT') {
  throw new Error('recent app did not resolve dynamic tile')
}
const fallbackTile = menu.dynamicTileForAppRows([], [], [], 'workspace-1')
if (fallbackTile.source !== 'workspace' || fallbackTile.detail !== 'WORKSPACE' || !fallbackTile.label) {
  throw new Error('dynamic tile fallback was not stable')
}
if (menu.semanticDetail({ parent: 'root', label: 'Apps' }, 'Applications') !== 'FIND // LAUNCH // MANAGE') {
  throw new Error('root Apps semantic subtitle was not normalized')
}
if (menu.semanticDetail({ parent: 'apps', label: 'Apps' }, 'Applications') !== 'Applications') {
  throw new Error('submenu detail was unexpectedly rewritten')
}

const bounded = notifications.limitHistory([{ id: 1 }, { id: 2 }, { id: 3 }], 2)
if (bounded.length !== 2 || bounded[0].id !== 1) throw new Error('history was not bounded')

const late = new Date(2026, 8, 22, 23, 15)
const early = new Date(2026, 8, 23, 6, 45)
const day = new Date(2026, 8, 22, 12, 0)
if (!notifications.isWithinQuietHours('22:00-07:00', late)) throw new Error('quiet hours missed late window')
if (!notifications.isWithinQuietHours('22:00-07:00', early)) throw new Error('quiet hours missed overnight window')
if (notifications.isWithinQuietHours('22:00-07:00', day)) throw new Error('quiet hours captured daytime')

const service = fs.readFileSync(`${root}/plugins/araneadev.notifications/Service.qml`, 'utf8')
if (!service.includes('ARANEA_QUIET_HOURS')) throw new Error('quiet-hours env is not wired into the service')
if (!service.includes('service.quietHours')) throw new Error('quiet-hours state is not used by notification handling')

const menuQml = fs.readFileSync(`${root}/plugins/araneadev.menu/Menu.qml`, 'utf8')
const lockQml = fs.readFileSync(`${root}/plugins/araneadev.lock/Service.qml`, 'utf8')
const lockViewQml = fs.readFileSync(`${root}/plugins/araneadev.lock/LockView.qml`, 'utf8')
const notificationsQml = service
const barQml = fs.readFileSync(`${root}/plugins/araneadev.bar/Bar.qml`, 'utf8')
const menuBarWidgetQml = fs.readFileSync(`${root}/plugins/araneadev.menu/BarWidget.qml`, 'utf8')
const notificationCardQml = fs.readFileSync(`${root}/plugins/araneadev.notifications/components/NotificationCard.qml`, 'utf8')
if (!menuBarWidgetQml.includes('aranea-glyph.svg')) throw new Error('bar menu trigger is missing reduced Aranea glyph')
if (!notificationCardQml.includes('aranea-glyph.svg')) throw new Error('notification card is missing reduced Aranea glyph')
if (!lockViewQml.includes('unlock.png')) throw new Error('lock surface is missing canonical Aranea spider')
if (!lockViewQml.includes('y: Math.max(32, inputField.y - height - 42)')) throw new Error('lock branding is not anchored to the live field')
if (!lockViewQml.includes('y: inputField.y + inputField.height + 28')) throw new Error('lock clock is not anchored to the live field')
if (!lockViewQml.includes('y: parent.height - height - 34')) throw new Error('lock footer is not anchored to the live viewport')
function requiresSignature(source, signature, name) {
  if (!source.includes(signature)) throw new Error(`missing typed scalar contract: ${name}`)
}

requiresSignature(menuQml, 'function rowListHeight(_serial: int, _count: int, _filter: string, _divider: bool): int', 'menu rowListHeight')
requiresSignature(menuQml, 'function dmenuRowListHeight(_serial: int, _count: int, _filter: string): int', 'menu dmenuRowListHeight')
requiresSignature(menuQml, 'function depthFor(id: string): int', 'menu depthFor')
requiresSignature(menuQml, 'function pathFor(id: string): string', 'menu pathFor')
requiresSignature(menuQml, 'function isDescendantOf(id: string, ancestorId: string): bool', 'menu isDescendantOf')
requiresSignature(menuQml, 'function childCount(id: string): int', 'menu childCount')
requiresSignature(menuQml, 'function searchScore(entry, query: string): real', 'menu searchScore')
requiresSignature(menuQml, 'function setFilter(nextFilter: string)', 'menu setFilter')
requiresSignature(menuQml, 'function open(payloadJson: string): void', 'menu open')
requiresSignature(menuQml, 'function select(delta: int): void', 'menu select')
requiresSignature(menuQml, 'function setActiveMenu(id: string, pushHistory: bool, fromPointer: bool): void', 'menu setActiveMenu')
requiresSignature(menuQml, 'function activateIndex(index: int, fromPointer: bool): void', 'menu activateIndex')
requiresSignature(menuQml, 'function applyDmenuSelection(value: string): void', 'menu applyDmenuSelection')
requiresSignature(menuQml, 'function resolveRoute(input: string): string', 'menu resolveRoute')
requiresSignature(menuQml, 'function toggleFavoriteApp(appId: string): void', 'menu favorite toggle')
requiresSignature(menuQml, 'function recordRecentApp(appId: string): void', 'menu recent history')
requiresSignature(menuQml, 'function recordRecentApp(appId: string): void {\n    root.recentAppIds', 'menu recent history implementation')
if (!menuQml.includes('root.recentAppIds = MenuModel.recordRecentApp(root.recentAppIds, appId, root.recentAppLimit)\n    root.saveAppHistory()\n    root.mergeAppRows()')) {
  throw new Error('recent app history must refresh visible rows immediately')
}
requiresSignature(menuQml, 'id: localAppLibrary', 'menu local app-library fallback')
requiresSignature(menuQml, 'DesktopEntries.applications.values', 'menu DesktopEntries fallback')
requiresSignature(menuQml, 'function openRoute(initialMenu: string): void', 'menu openRoute')
requiresSignature(menuQml, 'function goBack(): void', 'menu goBack')
requiresSignature(menuQml, 'function rebuildDisplay(): void', 'menu rebuildDisplay')
requiresSignature(menuQml, 'function revealCursor(): void', 'menu revealCursor')
requiresSignature(menuQml, 'function rebuildItemsFromSources(): void', 'menu rebuildItemsFromSources')
requiresSignature(menuQml, 'function startNextProvider(): void', 'menu startNextProvider')
requiresSignature(menuQml, 'function rebuildDmenuDisplay(): void', 'menu rebuildDmenuDisplay')
requiresSignature(menuQml, 'function cancel(): void', 'menu cancel')
requiresSignature(lockQml, 'function logEvent(event: string)', 'lock logEvent')
requiresSignature(lockQml, 'function submitPassword(value: string)', 'lock submitPassword')
requiresSignature(lockQml, 'function recoverStrandedLock(): void', 'lock recoverStrandedLock')
requiresSignature(lockQml, 'function refreshBackground(): void', 'lock refreshBackground')
requiresSignature(lockQml, 'function finishUnlock(): void', 'lock finishUnlock')
requiresSignature(lockQml, 'function runWake(): void', 'lock runWake')
requiresSignature(lockQml, 'function checkStrandedLock(): void', 'lock checkStrandedLock')
requiresSignature(lockQml, 'function refreshFingerprintStatus(): void', 'lock refreshFingerprintStatus')
requiresSignature(lockQml, 'function resetAuthenticationState(): void', 'lock resetAuthenticationState')
requiresSignature(lockQml, 'function runBlank(): void', 'lock runBlank')
requiresSignature(lockQml, 'function respondToPasswordPrompt(): void', 'lock respondToPasswordPrompt')
requiresSignature(lockViewQml, 'function updateClock(): void', 'lock view updateClock')
requiresSignature(lockQml, 'function queueSessionLock(): void', 'lock queueSessionLock')
requiresSignature(lockQml, 'function requestSessionLock(): void', 'lock requestSessionLock')
requiresSignature(lockQml, 'function armBlankTimer(): void', 'lock armBlankTimer')
requiresSignature(notificationsQml, 'function setDoNotDisturb(value: bool)', 'notification setDoNotDisturb')
requiresSignature(notificationsQml, 'function isEphemeral(notification): bool', 'notification isEphemeral')
requiresSignature(notificationsQml, 'function dismissPopup(index: int)', 'notification dismissPopup')
requiresSignature(notificationsQml, 'function removePopup(index: int, reason: string)', 'notification removePopup')
requiresSignature(notificationsQml, 'function replayHistory(raw: string)', 'notification replayHistory')
requiresSignature(notificationsQml, 'function clearPopups(): void', 'notification clearPopups')
requiresSignature(notificationsQml, 'function expirePopup(index: int): void', 'notification expirePopup')
requiresSignature(notificationsQml, 'function clearHistory(): void', 'notification clearHistory')
requiresSignature(notificationsQml, 'function loadSettings(raw: string): void', 'notification loadSettings')
requiresSignature(notificationsQml, 'function startHistoryRead(): void', 'notification startHistoryRead')
requiresSignature(notificationsQml, 'function runNextPopupFileJob(): void', 'notification runNextPopupFileJob')
requiresSignature(notificationsQml, 'function scheduleSettingsSave(): void', 'notification scheduleSettingsSave')
requiresSignature(notificationsQml, 'function flushSettings(): void', 'notification flushSettings')
requiresSignature(notificationsQml, 'function enqueueHistoryRead(): void', 'notification enqueueHistoryRead')
requiresSignature(notificationsQml, 'function sweepOrphanImages(): void', 'notification sweepOrphanImages')
requiresSignature(notificationsQml, 'function showRecentHistory(): void', 'notification showRecentHistory')
requiresSignature(notificationsQml, 'function liveRowsForReplay(): var', 'notification liveRowsForReplay')
requiresSignature(barQml, 'function publicLayoutConfig(): var', 'bar publicLayoutConfig')
requiresSignature(barQml, 'function slotScreenName(slot): string', 'bar slotScreenName')
requiresSignature(barQml, 'function focusedScreenName(): string', 'bar focusedScreenName')
requiresSignature(barQml, 'function isBarWidgetOpen(pluginId: string): bool', 'bar isBarWidgetOpen')
requiresSignature(barQml, 'function expandPath(path: string): string', 'bar expandPath')
requiresSignature(barQml, 'function pluginBarApiUsed(pluginId: string): bool', 'bar pluginBarApiUsed')
requiresSignature(barQml, 'function moduleWidgets(pluginId: string): var', 'bar moduleWidgets')
requiresSignature(barQml, 'function run(command: string): void', 'bar run')
requiresSignature(barQml, 'function toggleTransparency(): void', 'bar toggleTransparency')
requiresSignature(barQml, 'function setRequestedTransparency(value: real): void', 'bar setRequestedTransparency')
requiresSignature(barQml, 'function syncAllPluginBarApiObjects(): void', 'bar syncAllPluginBarApiObjects')
requiresSignature(barQml, 'function clearTooltip(): void', 'bar clearTooltip')
requiresSignature(barQml, 'function clearBarDrag(): void', 'bar clearBarDrag')
requiresSignature(barQml, 'function clearBarMove(): void', 'bar clearBarMove')
requiresSignature(barQml, 'function prunePluginBarApis(): void', 'bar prunePluginBarApis')
requiresSignature(barQml, 'function applyBarConfig(): void', 'bar applyBarConfig')
requiresSignature(barQml, 'function restoreForegroundAnimation(): void', 'bar restoreForegroundAnimation')
requiresSignature(barQml, 'function refreshTransparentForeground(): void', 'bar refreshTransparentForeground')
NODE

echo "plugin state contract passed"
