#!/usr/bin/env bash
# Real sandbox Git/store and production live-owner state machine, fake desktop only.
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
cli="$repo_root/scripts/aranea"
"$cli" projects register --path "$checkout" --json >"$ARANEA_TEST_SANDBOX/register.jsonl"
project=$(jq -r 'select(.event=="completed")|.data.state.projects[0].id' "$ARANEA_TEST_SANDBOX/register.jsonl")
"$cli" projects register --path "$sibling" --json >/dev/null
# Exercise nullable legacy choices through the actual locked migration and owner.
# Registration used the default state root; resolve it through the shared helper.
source "$repo_root/scripts/lib/paths.sh"
registry="$(aranea_state_root)/projects.json"
jq '.schemaVersion=1 | .projects |= map(del(.profiles,.lastProfileId,.environments,.openRoles) | .tools={editorId:null,terminalId:null})' "$registry" >"$ARANEA_TEST_SANDBOX/legacy.json"
cp "$ARANEA_TEST_SANDBOX/legacy.json" "$registry"
"$repo_root/scripts/aranea-project-store" snapshot | jq -e '.state.projects[0].profiles[0].tools=={editorId:null,terminalId:null,agentId:null}' >/dev/null

"$cli" projects inspect "$project" --json >"$ARANEA_TEST_SANDBOX/inspect.jsonl"
jq -se --arg path "$checkout" 'last.data.project.checkouts[0].path==$path' "$ARANEA_TEST_SANDBOX/inspect.jsonl" >/dev/null
git -C "$checkout" switch -qc feature
export ARANEA_FLOW_PATH="$checkout" ARANEA_FLOW_SIBLING="$sibling"
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
cp "$repo_root/tests/qml/fixtures/projects-environments-flow.qml" "$work/cfg/shell.qml"
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
sed -n 's/.*FLOW_SNAPSHOT //p' "$work/log" >"$ARANEA_TEST_SANDBOX/owner.json"
"$repo_root/scripts/aranea-project-store" snapshot >"$ARANEA_TEST_SANDBOX/store.json"
# Fake launches never open windows, so the first environment's workspace stays free.
jq -e '.state.projects[0] | (.environments|length==2) and (.environments[0].id != .environments[1].id) and (.environments|map(.workspaceId)) == [2,2] and (.associations|length==0) and .checkouts[0].branch=="main" and .environments[0].checkoutSnapshot.branch=="feature" and .environments[1].checkoutSnapshot.branch=="after-launch"' "$ARANEA_TEST_SANDBOX/store.json" >/dev/null
jq -en --slurpfile store "$ARANEA_TEST_SANDBOX/store.json" --slurpfile owner "$ARANEA_TEST_SANDBOX/owner.json" '$store[0].state.projects==$owner[0].projects' >/dev/null
if [[ -e "$ARANEA_TEST_SANDBOX/execution-trap" || -s "$ARANEA_TEST_SANDBOX/guard.log" ]]; then
  cat "$ARANEA_TEST_SANDBOX/guard.log"
  exit 1
fi
echo 'projects environments flow: real Git/store and independently accepted native environments passed'
