#!/usr/bin/env bash
# Actual CLI -> isolated production IPC endpoint -> owner contract regression.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
quickshell_bin=""
while IFS= read -r candidate; do
  [[ "$candidate" == */tests/guard-bin/* ]] && continue
  quickshell_bin="$candidate"
  break
done < <(type -ap quickshell 2>/dev/null || true)
[[ -n "$quickshell_bin" && -f /usr/share/omarchy/shell/Commons/qmldir ]]
checkout="$ARANEA_TEST_SANDBOX/repo with spaces"
mkdir -p "$checkout" "$ARANEA_TEST_SANDBOX/bin" "$XDG_STATE_HOME/omarchy/current"
git init -q "$checkout"
ln -s "$repo_root" "$XDG_STATE_HOME/omarchy/current/theme"
cli="$repo_root/scripts/aranea"
"$cli" projects register --path "$checkout" --json >"$ARANEA_TEST_SANDBOX/register"
project=$(jq -r 'select(.event=="completed")|.data.state.projects[0].id' "$ARANEA_TEST_SANDBOX/register")
"$cli" projects configure "$project" --editor code --terminal kitty --json >/dev/null
for tool in code kitty; do
  cat >"$ARANEA_TEST_SANDBOX/bin/$tool" <<'TRAP'
#!/usr/bin/env bash
echo unexpected >> "$ARANEA_TEST_SANDBOX/execution-trap"
exit 99
TRAP
  chmod +x "$ARANEA_TEST_SANDBOX/bin/$tool"
done
work=$(mktemp -d /tmp/aranea-cli.XXXXXX)
owner_pid=""
# Stop only the isolated endpoint process group and remove its socket directory.
cleanup_owner() {
  [[ -z "$owner_pid" ]] || {
    kill -- "-$owner_pid" 2>/dev/null || true
    wait "$owner_pid" 2>/dev/null || true
  }
  if ((status != 0)); then
    local diagnostic
    diagnostic=$(mktemp -d /tmp/aranea-cli-failure.XXXXXX)
    cp -r "$work" "$diagnostic/owner"
    printf 'Owner failure diagnostics: %s\n' "$diagnostic"
  fi
  rm -rf "$work"
}
sandbox_on_exit cleanup_owner
mkdir -p "$work/cfg/plugins" "$work/run"
chmod 700 "$work/run"
ln -s /usr/share/omarchy/shell/Commons "$work/cfg/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/cfg/Ui"
for plugin in "$repo_root"/plugins/araneadev.*; do ln -s "$plugin" "$work/cfg/plugins/${plugin##*/}"; done
cp "$repo_root/tests/qml/fixtures/projects-cli-owner.qml" "$work/cfg/shell.qml"
export CLI_OWNER_BIN="$quickshell_bin" CLI_OWNER_CONFIG="$work/cfg" CLI_OWNER_RUNTIME="$work/run" CLI_OWNER_CALLS="$work/calls"
cat >"$ARANEA_TEST_SANDBOX/bin/omarchy-shell" <<'BRIDGE'
#!/usr/bin/env bash
set -euo pipefail
jq -cn --args '$ARGS.positional' -- "$@" >> "$CLI_OWNER_CALLS"
cold_first=false
if [[ "${CLI_FORCE_COLD:-false}" == true && "$2" == request && ! -e "$CLI_OWNER_CALLS.cold" ]]; then
  cold_first=true
  touch "$CLI_OWNER_CALLS.cold"
  env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$CLI_OWNER_RUNTIME" "$CLI_OWNER_BIN" ipc -p "$CLI_OWNER_CONFIG" call fixture mode "${CLI_COLD_MODE:-readiness}" >/dev/null
fi
response=$(env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$CLI_OWNER_RUNTIME" "$CLI_OWNER_BIN" ipc -p "$CLI_OWNER_CONFIG" call "$@")
if [[ "$2" == request ]]; then printf '%s\n' "$response" >> "$CLI_OWNER_CALLS.responses"; fi
if [[ "$cold_first" == true ]]; then
  env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$CLI_OWNER_RUNTIME" "$CLI_OWNER_BIN" ipc -p "$CLI_OWNER_CONFIG" call fixture releaseRefresh >/dev/null
fi
printf '%s\n' "$response"
BRIDGE
chmod +x "$ARANEA_TEST_SANDBOX/bin/omarchy-shell"
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
(cd "$work" && exec setsid env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$work/run" "$quickshell_bin" -p "$work/cfg") >"$work/log" 2>&1 &
owner_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  if omarchy-shell aranea.projects snapshot 2>/dev/null | jq -e '.availability.ready' >/dev/null 2>&1; then break; fi
  sleep 0.1
done
# Assert the production owner terminal outcome and authoritative CLI exit status.
open_project() {
  local expected=$1 actual=0
  shift
  "$cli" projects open "$project" "$@" --json >"$work/events" || actual=$?
  [[ "$actual" == "$expected" ]] || {
    cat "$work/events" "$work/log"
    exit 1
  }
  jq -se 'last.event=="completed" and (last.operationId|type=="string" and length>0)' "$work/events" >/dev/null
}
# A real readiness refusal may retry each Open form, but acceptance submits only once.
cold_open() {
  local before
  before=$(wc -l <"$work/calls.responses")
  rm -f "$work/calls.cold"
  CLI_FORCE_COLD=true open_project "$@"
  # All retries precede the sole acceptance; a slow refresh can reject repeatedly.
  jq -se --argjson before "$before" '.[ $before: ] | length >= 2 and all(.[:-1][];.ok == false and .operationId == null and .error.code == "OWNER_NOT_READY") and (.[-1]|.ok == true and (.operationId|type == "string" and length > 0))' "$work/calls.responses" >/dev/null
  jq -se --slurpfile responses "$work/calls.responses" 'last.operationId == $responses[-1].operationId and last.status == "observed"' "$work/events" >/dev/null
}
for invalid in '{"newWindowRole":null}' '{"retryRole":null}' '{"reobserveRole":null}' '{"reobserveRole":"unknown"}' '{"reobserveRole":"editor","newWindowRole":"terminal"}' '{"reobserveRole":"terminal","retryRole":"editor"}'; do
  payload=$(jq -cn --arg project "$project" --argjson invalid "$invalid" '{projectId:$project}+$invalid')
  omarchy-shell aranea.projects request "$payload" | jq -e '.ok==false and .operationId==null and .error.code=="INVALID_REQUEST"' >/dev/null
done
"$cli" capabilities --json | jq -se 'last.data.operations | any(.name=="projects.open" and .arguments["reobserve-role"].enum==["editor","terminal"])' >/dev/null
omarchy-shell fixture mode failure >/dev/null
open_project 1
jq -se 'last.data.outcome=="partial" and any(last.data.operation.steps[];.role=="terminal" and .status=="failed")' "$work/events" >/dev/null
omarchy-shell fixture mode normal >/dev/null
cold_open 0 --retry-role terminal
cold_open 0 --new-window editor
cold_open 0
omarchy-shell fixture mode normal | jq -e '.launches==["editor","terminal","terminal","editor"]' >/dev/null
omarchy-shell fixture mode uncertain >/dev/null
open_project 1 --new-window terminal
omarchy-shell fixture mode normal >/dev/null
delayed_before=$(wc -l <"$work/calls.responses")
CLI_COLD_MODE=readiness-delayed cold_open 0 --reobserve-role terminal
# The delayed snapshot specifically exercises more than one readiness refusal.
jq -se --argjson before "$delayed_before" '.[$before:] | length > 2' "$work/calls.responses" >/dev/null
omarchy-shell fixture mode normal | jq -e '.launches==["editor","terminal","terminal","editor","terminal"]' >/dev/null
jq -se 'last.data.outcome=="observed" and any(last.data.operation.steps[];.role=="terminal" and .status=="observed")' "$work/events" >/dev/null
if grep -Eq 'TypeError|ReferenceError|Unable to assign|Binding loop|Failed to load configuration' "$work/log"; then
  cat "$work/log"
  exit 1
fi
[[ ! -e "$ARANEA_TEST_SANDBOX/execution-trap" && ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
echo 'projects CLI/owner: Open, new-window, retry, rejected readiness and re-observation passed'
