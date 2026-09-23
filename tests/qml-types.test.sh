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

qmllint_bin="$(command -v qmllint 2>/dev/null || true)"
if [[ -z "$qmllint_bin" && -x /usr/lib/qt6/bin/qmllint ]]; then
  qmllint_bin=/usr/lib/qt6/bin/qmllint
fi
[[ -n "$qmllint_bin" ]] || {
  echo 'qmllint is required for QML validation' >&2
  exit 1
}

shell_dir="${ARANEA_QML_SHELL_DIR:-/usr/share/omarchy/shell}"
import_root=""
cleanup() {
  if [[ -n "$import_root" ]]; then rm -rf "$import_root"; fi
}
trap cleanup EXIT

qml_args=(--ignore-settings)
if [[ -d "$shell_dir/Commons" && -f "$shell_dir/Commons/qmldir" \
   && -d "$shell_dir/Ui" && -f "$shell_dir/Ui/qmldir" ]]; then
  import_root="$(mktemp -d)"
  mkdir "$import_root/qs"
  ln -s "$shell_dir/Commons" "$import_root/qs/Commons"
  ln -s "$shell_dir/Ui" "$import_root/qs/Ui"
  qml_args+=(-I "$import_root")
fi

"$qmllint_bin" "${qml_args[@]}" "${qml_files[@]}"
echo "QML type validation passed ($("$qmllint_bin" --version); import root: ${import_root:-default})"
