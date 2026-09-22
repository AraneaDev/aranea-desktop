#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
qml_files=(
  "$repo_root/plugins/araneadev.bar/Bar.qml"
  "$repo_root/plugins/araneadev.notifications/Service.qml"
  "$repo_root/plugins/araneadev.notifications/components/NotificationCard.qml"
  "$repo_root/plugins/araneadev.lock/Service.qml"
  "$repo_root/plugins/araneadev.lock/LockView.qml"
  "$repo_root/plugins/araneadev.menu/Menu.qml"
  "$repo_root/plugins/araneadev.menu/BarWidget.qml"
)

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

if ! command -v qmllint >/dev/null 2>&1; then
  echo "qmllint unavailable; skipped optional QML validation"
  exit 0
fi

qmllint --ignore-settings "${qml_files[@]}"
echo "QML type validation passed"
