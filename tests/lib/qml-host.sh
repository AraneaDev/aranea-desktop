#!/usr/bin/env bash
# Shared native acceptance preflight, sourced after the isolated test sandbox.

# Resolve the real Quickshell and pinned shell; strict checks cannot skip them.
# Supplies quickshell_bin and qml_shell_dir without invoking desktop commands.
require_qml_host() {
  qml_shell_dir="$(sandbox_inherited_value ARANEA_QML_SHELL_DIR)"
  qml_shell_dir="${qml_shell_dir:-/usr/share/omarchy/shell}"
  quickshell_bin=""
  local candidate
  while IFS= read -r candidate; do
    [[ "$candidate" == */tests/guard-bin/* ]] && continue
    quickshell_bin="$candidate"
    break
  done < <(type -ap quickshell 2>/dev/null || true)
  if [[ -z "$quickshell_bin" || ! -f "$qml_shell_dir/Commons/qmldir" || ! -f "$qml_shell_dir/Ui/qmldir" ]]; then
    printf 'SKIP: native acceptance needs Quickshell and Omarchy shell at %s\n' "$qml_shell_dir"
    [[ "$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)" != 1 ]] || exit 1
    exit 0
  fi
}
