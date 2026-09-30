#!/usr/bin/env bash
# Contract for the QML surface: the bar window is transparent, every plugin
# entry point listed below exists and is repo-owned (not a system copy), and
# (when qmllint is available) tools/check --only qml passes strict lint
# against the shrink-only baseline for every tracked QML file.
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
  "$repo_root/plugins/araneadev.shared/OverlayChrome.qml"
  "$repo_root/plugins/araneadev.emojis/Emojis.qml"
  "$repo_root/plugins/araneadev.polkit/PolkitAgent.qml"
  "$repo_root/plugins/araneadev.notifications/Panel.qml"
  "$repo_root/plugins/araneadev.notifications/components/NotificationCard.qml"
  "$repo_root/plugins/araneadev.lock/Service.qml"
  "$repo_root/plugins/araneadev.lock/LockView.qml"
  "$repo_root/plugins/araneadev.menu/Menu.qml"
  "$repo_root/plugins/araneadev.menu/MenuGuards.qml"
  "$repo_root/plugins/araneadev.menu/MenuSources.qml"
  "$repo_root/plugins/araneadev.menu/MenuStyle.qml"
  "$repo_root/plugins/araneadev.menu/BarWidget.qml"
  "$repo_root/plugins/araneadev.osd/Osd.qml"
  # The windows and services the non-visual entries create (4f).
  "$repo_root/plugins/araneadev.clipboard/ClipboardWindow.qml"
  "$repo_root/plugins/araneadev.polkit/PolkitWindow.qml"
  "$repo_root/plugins/araneadev.polkit/PolkitAgentService.qml"
  "$repo_root/plugins/araneadev.menu/MenuWindow.qml"
  "$repo_root/plugins/araneadev.notifications/Toasts.qml"
  "$repo_root/plugins/araneadev.notifications/NotificationDaemon.qml"
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

# --- 4b: the bar renders exactly the configured layout
bar_qml="$repo_root/plugins/araneadev.bar/Bar.qml"
if grep -Eq 'property string profile|filterProfile|normalizeProfile|ARANEA_BAR_PROFILE' "$bar_qml"; then
  echo "bar profiles must not filter the layout" >&2
  exit 1
fi
[[ ! -e "$repo_root/scripts/aranea-bar-profile" ]] || {
  echo "aranea-bar-profile must be gone" >&2
  exit 1
}
if grep -Fq 'Bar profile' "$repo_root/scripts/aranea-about"; then
  echo "aranea-about must not report a bar profile" >&2
  exit 1
fi
grep -Fq 'setRequestedTransparency(BarModel.barTransparent(config))' "$bar_qml"
# CenterModules (gestures + hover) fills the horizontal bar under the side lists, as stock
horizontal="$(awk '/id: horizontalBar/ { on = 1 } on { print } on && /^    }$/ { exit }' "$bar_qml")"
grep -Fq 'CenterModules {' <<<"$horizontal"
if grep -Eq 'Style\.space\(190\)|id: (left|right|center)Surface' <<<"$horizontal"; then
  echo "the center gesture strip and invisible surfaces must be gone" >&2
  exit 1
fi
[[ "$(grep -n 'CenterModules {' <<<"$horizontal" | head -1 | cut -d: -f1)" -lt "$(grep -n 'LeftModules {' <<<"$horizontal" | cut -d: -f1)" ]] || {
  echo "CenterModules must come first so the side modules sit above it" >&2
  exit 1
}

# --- 4d: the lock date ticks with the clock; one state root for the lock
lock_view="$repo_root/plugins/araneadev.lock/LockView.qml"
grep -Fq 'dateText: root.dateText' "$lock_view"
grep -A6 -F 'function updateClock(): void' "$lock_view" | grep -Fq 'dateText = Qt.formatDate('
if grep -Fq 'XDG_STATE_HOME' "$lock_view"; then
  echo "LockView must use Omarchy's fixed state path, like Service.qml" >&2
  exit 1
fi
if grep -Eq 'function clearPassword|property int failedAttempts' "$lock_view"; then
  echo "dead LockView members are back" >&2
  exit 1
fi

# The QML contract is the tools/check qml stage: strict qmllint against the
# shrink-only baseline when Omarchy and Quickshell are present, syntax-only
# otherwise. Every tracked QML file is linted (not just the entry points).
if ! command -v qmllint >/dev/null 2>&1 && [[ ! -x /usr/lib/qt6/bin/qmllint ]]; then
  echo "SKIP: qmllint is not installed (CI runs QML checks in the Arch job)"
  exit 0
fi
"$repo_root/tools/check" --only qml
