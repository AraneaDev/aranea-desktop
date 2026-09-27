#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
qml_files=(
  "$repo_root/plugins/araneadev.bar/Bar.qml"
  "$repo_root/plugins/araneadev.notifications/Service.qml"
  "$repo_root/plugins/araneadev.notifications/Inbox.qml"
  "$repo_root/plugins/araneadev.health/Monitor.qml"
  "$repo_root/plugins/araneadev.health/Service.qml"
  "$repo_root/plugins/araneadev.health/Metrics.qml"
  "$repo_root/plugins/araneadev.health/Panel.qml"
  "$repo_root/plugins/araneadev.clipboard/Clipboard.qml"
  "$repo_root/plugins/araneadev.clipboard/OverlayChrome.qml"
  "$repo_root/plugins/araneadev.emojis/Emojis.qml"
  "$repo_root/plugins/araneadev.polkit/PolkitAgent.qml"
  "$repo_root/plugins/araneadev.notifications/Panel.qml"
  "$repo_root/plugins/araneadev.notifications/components/NotificationCard.qml"
  "$repo_root/plugins/araneadev.lock/Service.qml"
  "$repo_root/plugins/araneadev.lock/LockView.qml"
  "$repo_root/plugins/araneadev.menu/Menu.qml"
  "$repo_root/plugins/araneadev.menu/BarWidget.qml"
  "$repo_root/plugins/araneadev.osd/Osd.qml"
)

grep -Fq 'color: "transparent"' "$repo_root/plugins/araneadev.bar/Bar.qml"
grep -Fq 'surfaceFormat.opaque: false' "$repo_root/plugins/araneadev.bar/Bar.qml"

for qml_file in "${qml_files[@]}"; do
  [[ -f "$qml_file" ]] || {
    echo "missing QML entry point: $qml_file" >&2
    exit 1
  }
  [[ "$qml_file" != /usr/share/omarchy/* ]] || {
    echo "system-owned QML must not be checked by this contract" >&2
    exit 1
  }
done

# The QML contract is the tools/check qml stage: strict qmllint against the
# shrink-only baseline when Omarchy and Quickshell are present, syntax-only
# otherwise. Every tracked QML file is linted (not just the entry points).
"$repo_root/tools/check" --only qml
