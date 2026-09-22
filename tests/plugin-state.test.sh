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
NODE

echo "plugin state contract passed"
