#!/usr/bin/env bash
# Actual registration and profile persistence drive the real primary Start UI.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/qml-host.sh"
require_qml_host
checkout="$ARANEA_TEST_SANDBOX/development/project with spaces"
mkdir -p "$checkout" "$ARANEA_TEST_SANDBOX/bin" "$XDG_STATE_HOME/omarchy/current"
git init -q -b main "$checkout"
git -C "$checkout" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
sibling="$ARANEA_TEST_SANDBOX/development/project review"
git -C "$checkout" worktree add -qb review "$sibling"
manual="$ARANEA_TEST_SANDBOX/manual project"
git init -q -b main "$manual"
ln -s "$repo_root" "$XDG_STATE_HOME/omarchy/current/theme"
for tool in code kitty; do
  cat >"$ARANEA_TEST_SANDBOX/bin/$tool" <<'TRAP'
#!/usr/bin/env bash
printf 'unexpected application execution\n' >> "$ARANEA_TEST_SANDBOX/execution-trap"
exit 99
TRAP
  chmod +x "$ARANEA_TEST_SANDBOX/bin/$tool"
done
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
# Pin only sandbox defaults so installed host adapters cannot change the expected launch.
mkdir -p "$XDG_STATE_HOME/omarchy/defaults"
printf 'code\n' >"$XDG_STATE_HOME/omarchy/defaults/editor"
printf 'kitty.desktop\n' >"$XDG_CONFIG_HOME/xdg-terminals.list"
export ARANEA_FIRST_USE_PATH="$checkout" ARANEA_FIRST_USE_SIBLING="$sibling" ARANEA_FIRST_USE_MANUAL="$manual"
work=$(mktemp -d /tmp/aranea-flow.XXXXXX)
flow_pid=""
# Stop only the isolated acceptance owner and its scratch config.
cleanup_flow() {
  [[ -z "$flow_pid" ]] || {
    kill -- "-$flow_pid" 2>/dev/null || true
    wait "$flow_pid" 2>/dev/null || true
  }
  rm -rf "$work"
}
sandbox_on_exit cleanup_flow
mkdir -p "$work/cfg/plugins" "$work/run"
chmod 700 "$work/run"
ln -s "$qml_shell_dir/Commons" "$work/cfg/Commons"
ln -s "$qml_shell_dir/Ui" "$work/cfg/Ui"
ln -s "$repo_root/tests/qml/lib" "$work/cfg/lib"
for plugin in "$repo_root"/plugins/araneadev.*; do ln -s "$plugin" "$work/cfg/plugins/${plugin##*/}"; done
cp "$repo_root/tests/qml/fixtures/projects-profile-first-use.qml" "$work/cfg/shell.qml"
(cd "$work" && exec setsid env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$work/run" "$quickshell_bin" -p "$work/cfg") >"$work/log" 2>&1 &
flow_pid=$!
for ((attempt = 0; attempt < 150; attempt++)); do
  grep -q 'QMLTEST DONE\|Failed to load configuration' "$work/log" && break
  sleep 0.2
done
if ! grep -q 'QMLTEST DONE 0' "$work/log" || grep -Eq 'QMLTEST FAIL|TypeError|ReferenceError|Unable to assign|Binding loop' "$work/log"; then
  cat "$work/log"
  exit 1
fi
[[ ! -e "$ARANEA_TEST_SANDBOX/execution-trap" ]]
# Shared host Style can probe geometry only through sandbox guard stubs.
if [[ -f "$ARANEA_TEST_SANDBOX/guard.log" ]] && grep -Ev '^hyprctl -j getoption (general:gaps_out|decoration:rounding)$' "$ARANEA_TEST_SANDBOX/guard.log"; then
  exit 1
fi
echo 'projects first use: actual registration/preset and manual save enable exact visible primary passed'
