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
grep -Fq 'KeyboardPanel' "$plugin/Panel.qml"
grep -Fq 'InboxLogic.flattenGroups' "$plugin/Panel.qml"
grep -Fq 'All caught up' "$plugin/Panel.qml"
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
grep -Fq 'InboxLogic.sortForCenter' "$plugin/Panel.qml"
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

# --- 4c: a hold on any screen pauses every copy of a toast
svc="$repo_root/plugins/araneadev.notifications/Service.qml"
grep -Fq 'property var popupHolds: ({})' "$svc"
grep -Fq 'function holdPopup(key: string, on: bool): void' "$svc"
grep -Fq '!cardSlot.svc.popupHeld(cardSlot.holdKey)' "$svc"
grep -Fq 'Component.onDestruction: if (cardSlot.held)' "$svc"

echo "notifications contract passed"
