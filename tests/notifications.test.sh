#!/usr/bin/env bash
# Contract for the araneadev.notifications plugin: inbox-only design (no
# toast/history-replay/centerOpen/source-item era code left), the swipe and
# grouping wiring in NotificationCard/Panel/Service, health notifications
# stay out of this plugin (including migrating legacy inbox items), and the
# manifest declares both the bar-widget and service entry points.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
plugin="$repo_root/plugins/araneadev.notifications"

# Logic contract: tests/js/notifications.test.js (node:test; run by tests/js.test.sh).

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
  grep -Fq "$fn" "$plugin/Service.qml" || {
    echo "missing in Service.qml: $fn" >&2
    exit 1
  }
done

jq -e '(.kinds | index("bar-widget")) and .entryPoints.barWidget == "Panel.qml" and .barWidget.defaultSection == "right"' \
  "$plugin/manifest.json" >/dev/null
jq -e '(.kinds | index("service")) and .entryPoints.service == "Service.qml"' "$plugin/manifest.json" >/dev/null
test -f "$plugin/Panel.qml"
grep -Fq 'Aranea.KeyboardPanelFrame {' "$plugin/Panel.qml"
grep -Fq 'onUnhandledKey:' "$plugin/Panel.qml"
grep -Fq 'InboxLogic.dndClick(' "$plugin/Panel.qml"
grep -Fq 'InboxLogic.dndEcho(' "$plugin/Panel.qml"
# The list cap counts the card's padding and border (the footer stays inside).
grep -Fq 'InboxLogic.listHeight(list.contentHeight, panel.fittedContentHeight(panel.screenH, panel.screenH * 0.6) - panel.verticalContentInset' "$plugin/Panel.qml"
if grep -Eq 'PanelKeyCatcher|^  KeyboardPanel \{' "$plugin/Panel.qml"; then
  echo "Panel.qml must use the shared Aranea keyboard frame" >&2
  exit 1
fi
grep -Fq 'InboxLogic.centerRows(service.inbox.snapshot' "$plugin/Panel.qml"
grep -Fq 'NotificationCenterContent {' "$plugin/Panel.qml"
grep -Fq 'All caught up' "$plugin/NotificationCenterContent.qml"
grep -Fq 'NotificationList {' "$plugin/Panel.qml"
grep -Fq 'NotificationCard {' "$plugin/NotificationList.qml"
grep -Fq 'ServiceBridge.current()' "$plugin/Panel.qml"
grep -Fq 'ServiceBridge.publish(service)' "$plugin/Service.qml"
grep -Fq 'ServiceBridge.retract(service)' "$plugin/Service.qml"
grep -Fq 'property bool compact' "$plugin/components/NotificationCard.qml"

if grep -Eq 'stackLayout|overflowPill|centerOpen|writeSilenced|restorePopups' "$plugin/Service.qml"; then
  echo "toast-era code must be gone from Service.qml" >&2
  exit 1
fi
grep -Fq 'function refreshInbox' "$plugin/Service.qml"
grep -Fq 'inboxRefs' "$plugin/Service.qml"
if grep -Eq 'setOnScreen|onScreen' "$plugin/Inbox.qml"; then
  echo "onScreen must be gone from Inbox.qml" >&2
  exit 1
fi
grep -Fq 'merge' "$plugin/Inbox.qml"

grep -Fq 'InboxLogic.badgeState' "$plugin/Panel.qml"
# The center reads the inbox's plain snapshot, never its live model
# (live model objects in a binding feeding a view loop that binding).
if grep -Fq 'inbox.model' "$plugin/Panel.qml"; then
  echo "Panel.qml must read inbox.snapshot, not inbox.model" >&2
  exit 1
fi
grep -Fq 'cursorKey' "$plugin/Panel.qml"
if grep -Fq 'centerOpen' "$plugin/Panel.qml"; then
  echo "centerOpen must be gone from Panel.qml" >&2
  exit 1
fi

grep -Fq 'sourceKey' "$plugin/Inbox.qml"

if grep -Fq 'Health' "$plugin/Service.qml"; then
  echo "health moved out of the notifications plugin" >&2
  exit 1
fi

# Revision 1: health lives only in its dropdown. The keyed source API is gone
# and leftover 1.7.0 health items are deleted when the inbox loads.
if grep -Eq 'upsertSourceItem|resolveSourceItem|sourceItemKeys|sourceFileName' "$plugin/Service.qml"; then
  echo "source-item API must be gone" >&2
  exit 1
fi
grep -Fq 'legacy health item' "$plugin/Inbox.qml"

# --- 4f: the service is non-visual; the toasts and the notification server
# are separate parts it creates, so tests run it offscreen and off the bus.
# Behaviour (holds on two screens, clear during load, prune releases the
# sender, DND flushed on destruction): tests/qml/notifications.qml, run
# offscreen by tests/qml-behaviour.test.sh.
svc="$repo_root/plugins/araneadev.notifications/Service.qml"
toasts_qml="$repo_root/plugins/araneadev.notifications/Toasts.qml"
if grep -Eq 'PanelWindow|NotificationServer \{' "$svc"; then
  echo "Service.qml must stay non-visual; windows go in Toasts.qml" >&2
  exit 1
fi
grep -Fq 'service.toasts = service.createPart("Toasts.qml")' "$svc"
grep -Fq 'service.server = service.createPart("NotificationDaemon.qml")' "$svc"
grep -Fq 'server.root.handleNotification(notification)' "$repo_root/plugins/araneadev.notifications/NotificationDaemon.qml"
grep -Fq 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' "$toasts_qml"

# --- 4c: a hold on any screen pauses every copy of a toast (the window wiring)
grep -Fq '!cardSlot.svc.popupHeld(cardSlot.holdKey)' "$toasts_qml"
grep -Fq 'Component.onDestruction: if (cardSlot.held)' "$toasts_qml"

# --- 4c: the JSON goes through stdin (argv is limited to 128 KiB per arg);
# a job whose process never starts still finishes and the queue moves on
inbox_qml="$repo_root/plugins/araneadev.notifications/Inbox.qml"
grep -Fq 'IFS= read -r json' "$inbox_qml"
if grep -Fq 'NotificationLogic.serializePopup(record, normalUrgency), NotificationLogic.popupFileName(record)]' "$inbox_qml"; then
  echo "the notification JSON must not travel as an argument" >&2
  exit 1
fi
grep -Fq 'fileProc.write(inbox.runningStdin + "\n")' "$inbox_qml"
grep -Fq 'if (!running && !inbox.runningStarted)' "$inbox_qml"

# --- 4c: pruning is timed and releases senders; the model shows persisted images;
# changes during the startup read are applied after it; timestamps are capped
# (the release and the clear during load: tests/qml/notifications.qml)
grep -Fq 'signal pruned(string fileName)' "$inbox_qml"
grep -Fq 'interval: 3600000' "$inbox_qml"
grep -Fq 'InboxLogic.mergeLoaded(' "$inbox_qml"
grep -Fq 'NotificationLogic.clampTimestamp(' "$inbox_qml"
grep -Fq 'onPruned' "$svc"
grep -Fq 'critical notifications stay until dismissed' "$repo_root/README.md"

# --- 4c: quiet hours follow a minute-aligned clock; a pending DND save is flushed
grep -Fq 'precision: SystemClock.Minutes' "$svc"
grep -Fq 'NotificationLogic.isWithinQuietHours(quietHoursWindow, quietClock.date)' "$svc"
if grep -Fq 'quietHoursTick' "$svc"; then
  echo "quiet hours must not use the unaligned tick" >&2
  exit 1
fi
grep -Fq 'onReloaded: service.reloadedSettings = true' "$svc"

# --- 4c: Delete on "+N more" expands; Shift+Delete clears the group; the panel says so
panel_qml="$repo_root/plugins/araneadev.notifications/Panel.qml"
grep -Fq 'InboxLogic.dismissAction(' "$panel_qml"
grep -Fq 'InboxLogic.centerKeyHint(root.count)' "$panel_qml"
grep -Fq 'InboxLogic.centerCaption(root.count, root.quiet, root.quietUntilText)' "$panel_qml"
grep -Fq 'centerContent.disarmPointer()' "$panel_qml"

# --- 4c: dead restore code and unused card properties stay gone
if grep -Eq 'restoredPopups|isRestoredRow|keepFileName' "$svc"; then
  echo "dead restored-popup code is back" >&2
  exit 1
fi
card_qml="$repo_root/plugins/araneadev.notifications/components/NotificationCard.qml"
if grep -Eq 'accentColor|property double timestamp' "$card_qml"; then
  echo "unused card properties are back" >&2
  exit 1
fi

# --- 4c final review: updates compare live snapshots; only copied images are
# swapped in; new art under the same persisted path is not served from cache
grep -Fq 'property var liveSnapshots: ({})' "$svc"
grep -Fq 'NotificationLogic.shownImages(' "$inbox_qml"
grep -Fq 'prints each copied target' "$inbox_qml"
grep -Fq 'cache: false' "$card_qml"

# --- 4c final review: after Delete/Enter expands a group the cursor lands on
# the first revealed entry; migrated future entries keep distinct times
grep -Fq 'function expandAt(index: int): void' "$panel_qml"
grep -Fq 'fixed.timestamp = now - f' "$inbox_qml"

echo "notifications contract passed"
