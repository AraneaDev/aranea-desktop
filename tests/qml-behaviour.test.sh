#!/usr/bin/env bash
# Runs the offscreen QML behaviour tests (tests/qml/*.qml) under quickshell
# with QT_QPA_PLATFORM=offscreen; passes when a test prints "QMLTEST DONE 0",
# no "QMLTEST FAIL" and loads cleanly. Skips (exit 0; 1 with
# ARANEA_CHECK_REQUIRE_ALL=1) without quickshell or the Omarchy shell.
#
# Usage: tests/qml-behaviour.test.sh [name...]
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Each test is the shell.qml of a throwaway config next to links to the
# host's Commons/Ui, the test helpers and every Aranea plugin.
shell_dir="$(sandbox_inherited_value ARANEA_QML_SHELL_DIR)"
timeout_s="$(sandbox_inherited_value ARANEA_QMLTEST_TIMEOUT)"
require_all="$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)"
shell_dir="${shell_dir:-/usr/share/omarchy/shell}"
timeout_s="${timeout_s:-30}"
# The real quickshell: the sandbox puts guard stubs (one is named quickshell)
# first on PATH, possibly already in a caller's sandbox too.
quickshell_bin=""
while IFS= read -r candidate; do
  [[ "$candidate" == */tests/guard-bin/* ]] && continue
  quickshell_bin="$candidate"
  break
done < <(type -ap quickshell 2>/dev/null || true)

if [[ -z "$quickshell_bin" || ! -f "$shell_dir/Commons/qmldir" ]]; then
  echo "SKIP: QML behaviour tests need quickshell and the Omarchy shell at $shell_dir"
  [[ "$require_all" == 1 ]] && exit 1
  exit 0
fi

run_dir=""
qs_pid=""
# Stops a still-running quickshell and removes the current run directory.
cleanup() {
  if [[ -n "$qs_pid" ]] && kill -0 "$qs_pid" 2>/dev/null; then
    kill "$qs_pid" 2>/dev/null || true
    sleep 0.5
    kill -9 "$qs_pid" 2>/dev/null || true
  fi
  qs_pid=""
  [[ -n "$run_dir" ]] && rm -rf "$run_dir"
  run_dir=""
}
sandbox_on_exit cleanup

# Runs one test file; prints its result and returns non-zero when it failed.
run_test() {
  local test_file="$1" name plugin waited=0 status=0
  name="$(basename "$test_file" .qml)"
  # Short path: the quickshell IPC socket path is limited to 108 bytes.
  run_dir="$(mktemp -d /tmp/aranea-qt.XXXXXX)"
  mkdir -p "$run_dir/cfg/plugins" "$run_dir/run"
  chmod 700 "$run_dir/run"
  ln -s "$shell_dir/Commons" "$run_dir/cfg/Commons"
  ln -s "$shell_dir/Ui" "$run_dir/cfg/Ui"
  ln -s "$repo_root/tests/qml/lib" "$run_dir/cfg/lib"
  ln -s "$repo_root/tests/qml/fixtures" "$run_dir/cfg/fixtures"
  for plugin in "$repo_root"/plugins/araneadev.*; do
    [[ -d "$plugin" ]] && ln -s "$plugin" "$run_dir/cfg/plugins/${plugin##*/}"
  done
  cp "$test_file" "$run_dir/cfg/shell.qml"
  # No display, compositor, session bus or desktop platform theme (the gtk3
  # theme aborts without a display).
  # From the run directory, so a relative path in a test can never write
  # into the repository.
  (cd "$run_dir" && exec env -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u HYPRLAND_INSTANCE_SIGNATURE \
    -u QT_QPA_PLATFORMTHEME -u QT_STYLE_OVERRIDE QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$run_dir/run" XDG_CACHE_HOME="$run_dir/cache" \
    "$quickshell_bin" -p "$run_dir/cfg") >"$run_dir/log" 2>&1 &
  qs_pid=$!
  while ((waited < timeout_s * 5)); do
    grep -q 'QMLTEST DONE' "$run_dir/log" && break
    grep -q 'Failed to load configuration' "$run_dir/log" && break
    kill -0 "$qs_pid" 2>/dev/null || break
    sleep 0.2
    waited=$((waited + 1))
  done
  local log
  log="$(sed 's/\x1b\[[0-9;]*m//g' "$run_dir/log")"
  cleanup
  if grep -q 'Failed to load configuration' <<<"$log"; then
    echo "qmltest: $name FAILED (did not load)"
    grep -E 'ERROR' <<<"$log" | grep -v 'quickshell.ipc' | sed 's/^/  /'
    return 1
  fi
  grep -E 'QMLTEST FAIL' <<<"$log" | sed 's/^.*QMLTEST FAIL/  QMLTEST FAIL/' && status=1
  if ! grep -q 'QMLTEST DONE' <<<"$log"; then
    echo "qmltest: $name FAILED (no QMLTEST DONE within ${timeout_s}s)"
    grep -E 'ERROR|TypeError|ReferenceError' <<<"$log" | grep -v 'quickshell.ipc' | sed 's/^/  /' | head -20
    return 1
  fi
  # A runtime error fails the test even when every check passed: it means
  # some code path the test drove threw.
  local errors
  errors="$(grep -E 'TypeError|ReferenceError|is not a function|Cannot read property|Unable to assign' <<<"$log" | grep -v 'quickshell.ipc' || true)"
  if [[ -n "$errors" ]]; then
    echo "qmltest: $name FAILED (runtime error)"
    head -20 <<<"$errors" | sed 's/^/  /'
    return 1
  fi
  if ((status)); then
    echo "qmltest: $name FAILED"
    return 1
  fi
  echo "qmltest: $name ok ($(grep -c 'QMLTEST PASS' <<<"$log") checks)"
}

tests=()
if (($#)); then
  for name in "$@"; do tests+=("$repo_root/tests/qml/$name.qml"); done
else
  for file in "$repo_root"/tests/qml/*.qml; do [[ -f "$file" ]] && tests+=("$file"); done
fi
failed=0
for file in "${tests[@]}"; do
  run_test "$file" || failed=1
done
exit "$failed"
