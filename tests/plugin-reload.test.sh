#!/usr/bin/env bash
# Aranea native plugin reload, installed over an unchanged Omarchy host.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/qml-host.sh"
require_qml_host
work=$(mktemp -d /tmp/aranea-reload-test.XXXXXX)
qs_pid=""
# Stops the isolated test shell and removes its fixture.
cleanup_reload() {
  if [[ -n "$qs_pid" ]]; then
    kill "$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
sandbox_on_exit cleanup_reload
mkdir -p "$work/config/plugins" "$work/config/plugins/fixture.auth" "$work/installed/example.test"
ln -s "$repo_root/plugins/araneadev.shared" "$work/config/plugins/araneadev.shared"
ln -s "$repo_root/plugins/araneadev.bar" "$work/config/plugins/araneadev.bar"
ln -s "$qml_shell_dir/Commons" "$work/config/Commons"
ln -s "$qml_shell_dir/Ui" "$work/config/Ui"
cp "$repo_root/tests/qml/fixtures/native-plugin-reload/shell.qml" "$work/config/shell.qml"
cp "$repo_root/tests/qml/fixtures/native-plugin-reload/AuthOwners.qml" "$work/config/plugins/fixture.auth/AuthOwners.qml"
# Writes a distinct QML and imported JavaScript generation.
write_plugin() {
  cat >"$work/installed/example.test/Entry.qml" <<QML
import QtQuick
import "Logic.js" as Logic
QtObject { property string marker: "$1/" + Logic.marker() }
QML
  printf 'function marker() { return "%s" }\n' "$2" >"$work/installed/example.test/Logic.js"
}
write_plugin qml-one js-one
export ARANEA_RELOAD_TEST_PLUGIN_ROOT="$work/installed" QT_QPA_PLATFORM=offscreen QS_NO_RELOAD_POPUP=1
unset QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
"$quickshell_bin" -p "$work/config" --no-color >"$work/log" 2>&1 &
qs_pid=$!
# Calls the isolated fixture configuration.
ipc() { "$quickshell_bin" ipc --any-display -p "$work/config" call aranea.reload-test "$@"; }
# Waits for native engine handover to expose the requested generation.
wait_marker() {
  local marker="$1" state="" attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    state=$(ipc state 2>/dev/null || true)
    if jq -e --arg marker "$marker" '.marker == $marker' <<<"$state" >/dev/null 2>&1; then return 0; fi
    sleep 0.05
  done
  cat "$work/log" >&2
  printf 'Expected %s, got %s\n' "$marker" "$state" >&2
  exit 1
}
# Checks that guarded or irrelevant edits have not changed the generation.
assert_marker() {
  local state
  state=$(ipc state)
  jq -e --arg marker "$1" '.marker == $marker' <<<"$state" >/dev/null || {
    printf '%s\n' "$state" >&2
    cat "$work/log" >&2
    return 1
  }
}
wait_marker qml-one/js-one
initial_pid=$(ipc state | jq -r '.pid')
write_plugin qml-two js-two
wait_marker qml-two/js-two
[[ $(ipc state | jq -r '.pid') == "$initial_pid" ]]
printf 'ok - plugin watcher reloads QML and JavaScript in the same process\n'
printf 'function marker() { return "js-three" }\n' >"$work/installed/example.test/Logic.js"
wait_marker qml-two/js-three
printf 'ok - successive reload refreshes an imported JavaScript file\n'
ipc lock true
write_plugin qml-four js-four
sleep 0.3
assert_marker qml-two/js-three
ipc state | jq -e '.pending == true and .blocked == true' >/dev/null
ipc lock false
wait_marker qml-four/js-four
printf 'ok - shared guards defer a watched edit until unlock\n'
ipc authenticate true
write_plugin qml-five js-five
sleep 0.3
assert_marker qml-four/js-four
ipc authenticate false
wait_marker qml-five/js-five
printf 'ok - authentication completion applies a pending watched edit\n'
ipc promptReady false
write_plugin qml-six js-six
sleep 0.3
assert_marker qml-five/js-five
ipc state | jq -e '.pending == true and .blocked == true' >/dev/null
ipc promptReady true
wait_marker qml-six/js-six
printf 'ok - missing authentication owner defers reload until it returns\n'

current_generation=$(ipc state | jq -r '.generation')
mkdir -p "$work/installed/example.test/.git"
printf 'ignored\n' >"$work/installed/example.test/.git/HEAD"
sleep 0.2
ipc state | jq -e --arg generation "$current_generation" '.pending == false and .generation == $generation and .watchFiles == false' >/dev/null
[[ $(ipc state | jq -r '.pid') == "$initial_pid" ]]
printf 'ok - Git metadata does not reload the shell\n'

# A native reload failure keeps the old engine available for a repaired retry.
cp "$work/config/shell.qml" "$work/working-shell.qml"
printf 'invalid QML syntax\n' >"$work/config/shell.qml"
"$quickshell_bin" ipc --any-display -p "$work/config" call aranea.reload reload >/dev/null
sleep 0.3
assert_marker qml-six/js-six
cp "$work/working-shell.qml" "$work/config/shell.qml"
write_plugin qml-seven js-seven
wait_marker qml-seven/js-seven
printf 'ok - a failed configuration reload remains usable and accepts a repaired retry\n'
