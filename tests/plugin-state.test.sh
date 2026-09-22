#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node - "$repo_root" <<'NODE'
const root = process.argv[2]
const bar = require(`${root}/plugins/araneadev.bar/BarModel.js`)
const notifications = require(`${root}/plugins/araneadev.notifications/NotificationLogic.js`)
const fs = require('fs')

for (const state of ['healthy', 'focus', 'attention', 'warning', 'error', 'muted', 'charging', 'privacy']) {
  if (!bar.semanticColor(state)) throw new Error(`missing semantic state: ${state}`)
}
if (bar.semanticColor('unknown') !== 'dark_foreground') throw new Error('unknown state must be muted')

const grouped = notifications.groupNotifications([
  { app: 'browser', summary: 'One' },
  { app: 'browser', summary: 'Two' },
  { app: 'terminal', summary: 'Three' }
])
if (grouped.length !== 2 || grouped[0].count !== 2) throw new Error('notifications were not grouped by app')

const collapsed = notifications.collapseQuietHours([{ id: 1 }, { id: 2 }], true)
if (collapsed.visible.length !== 0 || collapsed.count !== 2) throw new Error('quiet-hours collapse failed')

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
