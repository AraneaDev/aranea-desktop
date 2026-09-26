#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin="$repo_root/plugins/araneadev.notifications"

node - "$repo_root" <<'NODE'
const root = process.argv[2]
const inbox = require(`${root}/plugins/araneadev.notifications/InboxLogic.js`)
const assert = (cond, msg) => { if (!cond) throw new Error(msg) }
const DAY = 24 * 60 * 60 * 1000

// --- store decision (spec §1 lifecycle, last row)
assert(inbox.shouldStore(false, 1, false) === true, 'normal app/normal urgency must be stored')
assert(inbox.shouldStore(true, 0, false) === false, 'ephemeral low-urgency sender must not be stored')
assert(inbox.shouldStore(true, 1, false) === true, 'ephemeral sender at normal urgency must be stored')
assert(inbox.shouldStore(true, 2, false) === true, 'ephemeral sender at critical urgency must be stored')
assert(inbox.shouldStore(false, 1, true) === false, 'transient hint must never be stored')

// --- lifecycle outcome
assert(inbox.removesFromInbox('expire') === false, 'expired toast must stay in the inbox')
assert(inbox.removesFromInbox('dismiss') === true, 'dismissed toast must leave the inbox')
assert(inbox.removesFromInbox('invoke') === true, 'invoked toast must leave the inbox')

// --- replaces_id keeps one entry (Review Focus 2)
let rows = [{ fileName: 'b' }, { fileName: 'a' }]
rows = inbox.upsertOrder(rows, { fileName: 'a', summary: 'v2' })
assert(rows.length === 2 && rows[1].summary === 'v2', 'same fileName must update in place')
rows = inbox.upsertOrder(rows, { fileName: 'c' })
assert(rows.length === 3 && rows[0].fileName === 'c', 'new fileName must be prepended')

// --- pruning
const now = 1000 * DAY
const e = (name, ageDays, urgency, onScreen) =>
  ({ fileName: name, timestamp: now - ageDays * DAY, urgency: urgency, onScreen: !!onScreen })
let pruned = inbox.pruneInbox([e('old', 8, 1), e('oldCrit', 8, 2), e('fresh', 1, 1), e('oldLive', 9, 1, true)], now)
assert(pruned.drop.map(x => x.fileName).join() === 'old', 'only non-critical, off-screen entries age out')
assert(pruned.keep.map(x => x.fileName).join() === 'fresh,oldCrit,oldLive', 'keep must be newest-first')

const many = []
for (let i = 0; i < 103; i++) many.push({ fileName: 'n' + i, timestamp: now - i * 1000, urgency: i === 102 ? 2 : 1, onScreen: false })
pruned = inbox.pruneInbox(many, now)
assert(pruned.keep.length === 100, 'cap must hold 100 entries')
assert(pruned.keep.some(x => x.fileName === 'n102'), 'oldest critical must survive while non-critical can go')
assert(pruned.drop.map(x => x.fileName).sort().join() === 'n100,n101,n99', 'oldest non-critical dropped first')

const crits = []
for (let i = 0; i < 101; i++) crits.push({ fileName: 'c' + i, timestamp: now - i * 1000, urgency: 2, onScreen: false })
pruned = inbox.pruneInbox(crits, now)
assert(pruned.keep.length === 100 && pruned.drop[0].fileName === 'c100', 'criticals capped only when nothing else is left')

// --- swipe (Review Focus 4)
assert(inbox.swipeOutcome(140, 380, 0) === 'dismiss', '37% distance dismisses')
assert(inbox.swipeOutcome(100, 380, 0) === 'restore', '26% distance springs back')
assert(inbox.swipeOutcome(30, 380, 1200) === 'dismiss', 'fast rightward flick dismisses')
assert(inbox.swipeOutcome(-200, 380, -2000) === 'restore', 'leftward drag never dismisses')
assert(inbox.suppressesClick(5) === true && inbox.suppressesClick(-5) === true, 'drag beyond 4px suppresses click')
assert(inbox.suppressesClick(3) === false, 'tiny jitter still clicks')

// --- groups
const g = (app, t) => ({ app: app, timestamp: t, fileName: app + t })
const groups = inbox.groupView([g('Slack', 9), g('Build', 8), g('Slack', 7), g('Slack', 6)], {})
assert(groups.length === 2 && groups[0].app === 'Slack' && groups[1].app === 'Build', 'groups ordered by newest entry')
assert(groups[0].collapsed === true && groups[0].visible.length === 1 && groups[0].hidden === 2, 'group of 3 starts collapsed')
assert(groups[1].collapsed === false && groups[1].hidden === 0, 'small group starts expanded')
const opened = inbox.groupView([g('Slack', 9), g('Slack', 7), g('Slack', 6)], { Slack: true })
assert(opened[0].collapsed === false && opened[0].visible.length === 3, 'explicit expand wins')
const flat = inbox.flattenGroups(groups)
assert(flat.map(r => r.kind).join() === 'group,entry,more,group,entry', 'flattened rows follow group layout')

// --- labels
assert(inbox.badgeLabel(0) === '' && inbox.badgeLabel(9) === '9' && inbox.badgeLabel(10) === '9+', 'badge labels')
assert(inbox.tooltipText(1, 0, false, false) === '1 notification · DND off', 'singular tooltip')
assert(inbox.tooltipText(4, 0, true, false) === '4 notifications · DND on', 'plural tooltip with DND')
assert(inbox.tooltipText(0, 0, false, true) === '0 notifications · Quiet hours', 'quiet-hours tooltip')
assert(inbox.bellGlyph(false) === '󰂚' && inbox.bellGlyph(true) === '󰂛', 'bell glyphs')
assert(inbox.needsClearConfirm(20) === false && inbox.needsClearConfirm(21) === true, 'confirm above 20')
assert(inbox.quietUntil('22:00-07:00') === '07:00' && inbox.quietUntil('bogus') === '', 'quiet-until label')
assert(inbox.relativeTime(now - 30000, now) === 'now', 'under a minute')
assert(inbox.relativeTime(now - 2 * 60000, now) === '2m', 'minutes')
assert(inbox.relativeTime(now - 3 * 3600000, now) === '3h', 'hours')
assert(inbox.relativeTime(now - 2 * DAY, now) === '2d', 'days')

// --- onScreen round-trip through the persisted format (Review Focus 1, 3)
const logic = require(`${root}/plugins/araneadev.notifications/NotificationLogic.js`)
const live = logic.popupEntry({ id: 3, originalId: 3, app: 'Slack', timestamp: 5, onScreen: true, deadline: 99 }, 1)
assert(live.onScreen === true && live.deadline === 99, 'onScreen and deadline must survive popupEntry')
const parsed = logic.parsePopupFiles(logic.serializePopup({ id: 4, originalId: 4, timestamp: 6, onScreen: false }, 1), 1)
assert(parsed.length === 1 && parsed[0].onScreen === false, 'onScreen=false must survive serialize/parse')
const legacy = logic.popupEntry({ id: 5, originalId: 5, timestamp: 7 }, 1)
assert(legacy.onScreen === undefined, 'legacy entries carry no onScreen; Inbox.qml treats them as on screen')
assert(typeof logic.historyRows === 'undefined', 'history replay helper must be gone')

// --- the bell must survive the default (minimal) Aranea bar profile
const barModel = require(`${root}/plugins/araneadev.bar/BarModel.js`)
assert(barModel.profileAllows('minimal', 'araneadev.notifications') === true, 'minimal bar profile must allow the notification bell')

// --- service bridge: the Aranea bar hands widgets a service-less facade, so
// the panel finds its own plugin's service through a shared library module.
const bridgeSrc = require('fs').readFileSync(`${root}/plugins/araneadev.notifications/ServiceBridge.js`, 'utf8')
assert(bridgeSrc.startsWith('.pragma library'), 'bridge must be a shared library module')
const bridge = {}
new Function('exports', bridgeSrc.replace('.pragma library', '') +
  '\nexports.publish = publish; exports.current = current; exports.retract = retract')(bridge)
const svcA = { name: 'a' }, svcB = { name: 'b' }
assert(bridge.current() === null, 'no service before publish')
bridge.publish(svcA)
assert(bridge.current() === svcA, 'published service is current')
bridge.publish(svcB)
bridge.retract(svcA)
assert(bridge.current() === svcB, 'retracting a stale service keeps the newer one')
bridge.retract(svcB)
assert(bridge.current() === null, 'retracting the current service clears it')

// --- bell-only badge (Revision 1)
let b = inbox.badgeState(0, 0, false)
assert(b.tone === 'none' && b.label === '', 'empty inbox has no badge')
b = inbox.badgeState(7, 0, false)
assert(b.tone === 'normal' && b.label === '7', 'normal badge shows total')
b = inbox.badgeState(7, 2, false)
assert(b.tone === 'critical' && b.label === '2', 'critical badge shows critical count')
b = inbox.badgeState(12, 11, true)
assert(b.tone === 'critical' && b.label === '9+', 'critical shows through DND, capped')
b = inbox.badgeState(5, 0, true)
assert(b.tone === 'none', 'DND hides the normal badge')
assert(inbox.tooltipText(7, 2, false, false) === '7 notifications · 2 critical · DND off', 'tooltip with critical')
assert(inbox.tooltipText(1, 0, true, false) === '1 notification · DND on', 'tooltip without critical')
const sorted = inbox.sortForCenter([{ fileName: 'a', timestamp: 3, urgency: 1 }, { fileName: 'b', timestamp: 1, urgency: 2 }, { fileName: 'c', timestamp: 2, urgency: 1 }])
assert(sorted.map(x => x.fileName).join() === 'b,a,c', 'critical first, then newest')
// --- cursor follows the item (Important #5)
const before = inbox.flattenGroups(inbox.groupView([g('Build', 8)], {}))
const key = inbox.rowKey(before[1])
const after = inbox.flattenGroups(inbox.groupView([g('Slack', 9), g('Build', 8)], {}))
assert(inbox.indexOfKey(after, key) === 3, 'cursor key re-resolves after a new group arrives on top')
assert(inbox.indexOfKey(after, 'e:gone') === -1, 'missing key resolves to -1')
assert(typeof inbox.stackSplit === 'undefined', 'toast stack rules are gone')

console.log('inbox logic contract passed')
NODE

test -f "$plugin/Inbox.qml"
grep -Fq 'inbox/' "$plugin/Inbox.qml"
if grep -Eq 'historyDir|showRecentHistory|replayHistory' "$plugin/Service.qml"; then
  echo "history replay must be removed from Service.qml" >&2
  exit 1
fi
grep -Fq 'Inbox {' "$plugin/Service.qml"

grep -Fq 'DragHandler' "$plugin/components/NotificationCard.qml"
grep -Fq 'InboxLogic.swipeOutcome' "$plugin/components/NotificationCard.qml"
grep -Fq 'InboxLogic.suppressesClick' "$plugin/components/NotificationCard.qml"

for fn in 'function dismissInbox' 'function dismissGroup' 'function invokeInbox' 'function center(): string' 'function count(): string'; do
  grep -Fq "$fn" "$plugin/Service.qml" || { echo "missing in Service.qml: $fn" >&2; exit 1; }
done

jq -e '(.kinds | index("bar-widget")) and .entryPoints.barWidget == "Panel.qml" and .barWidget.defaultSection == "right"' \
  "$plugin/manifest.json" >/dev/null
jq -e '(.kinds | index("service")) and .entryPoints.service == "Service.qml"' "$plugin/manifest.json" >/dev/null
test -f "$plugin/Panel.qml"
grep -Fq 'KeyboardPanel' "$plugin/Panel.qml"
grep -Fq 'InboxLogic.flattenGroups' "$plugin/Panel.qml"
grep -Fq 'All caught up' "$plugin/Panel.qml"
grep -Fq 'ServiceBridge.current()' "$plugin/Panel.qml"
grep -Fq 'ServiceBridge.publish(service)' "$plugin/Service.qml"
grep -Fq 'ServiceBridge.retract(service)' "$plugin/Service.qml"
grep -Fq 'property bool compact' "$plugin/components/NotificationCard.qml"

if grep -Eq 'stackLayout|overflowPill|centerOpen|writeSilenced|restorePopups' "$plugin/Service.qml"; then
  echo "toast-era code must be gone from Service.qml" >&2; exit 1
fi
grep -Fq 'function refreshInbox' "$plugin/Service.qml"
grep -Fq 'inboxRefs' "$plugin/Service.qml"
if grep -Eq 'setOnScreen|onScreen' "$plugin/Inbox.qml"; then echo "onScreen must be gone from Inbox.qml" >&2; exit 1; fi
grep -Fq 'merge' "$plugin/Inbox.qml"

echo "notifications contract passed"
