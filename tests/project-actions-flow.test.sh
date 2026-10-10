#!/usr/bin/env bash
# Cross-component acceptance: real Git/store/public CLI and production UI/client.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
backend="$repo_root/scripts/aranea-project-actions"
cli="$repo_root/scripts/aranea"
source "$repo_root/tests/lib/qml-host.sh"
require_qml_host
shell_dir="$qml_shell_dir"
qs="$quickshell_bin"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo" "$ARANEA_TEST_SANDBOX/manager"
for tool in systemd-run systemctl journalctl curl xdg-open; do ln -s "$repo_root/tests/fixtures/project-actions-manager.sh" "$ARANEA_TEST_SANDBOX/bin/$tool"; done
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
manager="$ARANEA_TEST_SANDBOX/manager"
qs_pid=''
# Stop only our observer process group; no configured argv is ever executed.
cleanup_flow() {
  if [[ -n $qs_pid ]]; then
    kill -- "-$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  for _ in {1..160}; do
    compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null || return 0
    sleep .1
  done
}
sandbox_on_exit cleanup_flow
git init -q "$ARANEA_TEST_SANDBOX/repo"
git -C "$ARANEA_TEST_SANDBOX/repo" -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm initial
git -C "$ARANEA_TEST_SANDBOX/repo" worktree add -q -b review "$ARANEA_TEST_SANDBOX/worktree"
for path in "$ARANEA_TEST_SANDBOX/repo" "$ARANEA_TEST_SANDBOX/worktree"; do
  jq -cn --arg p "$path" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/registry"
done
project=$(jq -r '.state.projects[0].id' "$TMPDIR/registry")
checkout=$(jq -r --arg p "$ARANEA_TEST_SANDBOX/repo" '.state.projects[0].checkouts[]|select(.path==$p)|.id' "$TMPDIR/registry")
checkout2=$(jq -r --arg p "$ARANEA_TEST_SANDBOX/worktree" '.state.projects[0].checkouts[]|select(.path==$p)|.id' "$TMPDIR/registry")
# Collect actual public schema1 events for one operation.
call() { "$cli" projects "$@" --json >"$TMPDIR/events"; }
# Decode the final public event without bypassing its adapter.
last() { jq -rs '.[-1].data' "$TMPDIR/events"; }
# Require the public domain-failure exit and exact retained error code.
refuse() {
  local code=$1 status=0
  shift
  call "$@" 2>"$TMPDIR/expected-error" || status=$?
  [[ $status == 1 ]]
  jq -es --arg c "$code" '.[-1].code==$c' "$TMPDIR/events" >/dev/null
}
# The CLI configures while execution is unavailable; no launch is implicit.
touch "$manager/unavailable"
# shellcheck disable=SC2016
printf '%s\n' '{"name":"Literal checks","kind":"command","argv":["printf","literal $HOME %i ; $(touch NEVER)",""],"cwdRelative":".","timeoutSeconds":12,"previewUrl":null}' >"$TMPDIR/draft"
call actions configure "$project" --json-input <"$TMPDIR/draft"
action=$(last | jq -r '.state.definitions[0].id')
[[ ! -e $manager/launches ]]
# Execute a fixture through the real native production client, not an injected runner.
ui() {
  local phase=$1 run=${2:-} work waited=0
  work=$(mktemp -d /tmp/aranea-flow.XXXXXX)
  mkdir -p "$work/cfg/plugins" "$work/run"
  chmod 700 "$work/run"
  ln -s "$shell_dir/Commons" "$work/cfg/Commons"
  ln -s "$shell_dir/Ui" "$work/cfg/Ui"
  ln -s "$repo_root/tests/qml/lib" "$work/cfg/lib"
  for plugin in "$repo_root"/plugins/araneadev.*; do ln -s "$plugin" "$work/cfg/plugins/${plugin##*/}"; done
  cp "$repo_root/tests/qml/fixtures/project-actions-flow.qml" "$work/cfg/shell.qml"
  data=$(jq -c --arg c "$checkout" --arg a "$action" --arg r "$run" '{project:(.state.projects[0]+{lastCheckoutId:$c}),actionId:$a,runId:$r}' "$TMPDIR/registry")
  (cd "$work" && exec setsid env -u QT_QPA_PLATFORMTHEME -u QT_STYLE_OVERRIDE QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$work/run" ARANEA_ACTION_FLOW_DATA="$data" ARANEA_ACTION_FLOW_PHASE="$phase" ARANEA_ACTION_FLOW_ROOT="$repo_root" \
    "$qs" -p "$work/cfg") >"$work/log" 2>&1 &
  qs_pid=$!
  while ((waited < 200)); do
    grep -q 'QMLTEST DONE\|Failed to load configuration' "$work/log" && break
    kill -0 "$qs_pid" 2>/dev/null || break
    sleep .2
    waited=$((waited + 1))
  done
  cleanup_flow
  qs_pid=''
  cat "$work/log" | sed -n '/QMLTEST/p'
  if ! grep -q 'QMLTEST DONE 0' "$work/log" || grep -Eq 'QMLTEST FAIL|TypeError|ReferenceError|Cannot assign|Unable to assign|Binding loop detected|Failed to load configuration' "$work/log"; then
    cat "$work/log" >&2
    rm -rf "$work"
    return 1
  fi
  rm -rf "$work"
}
ui edit
[[ ! -e $manager/launches ]]
rm "$manager/unavailable"
ui run
[[ $(wc -l <"$manager/launches") == 1 ]]
run=$(jq -r '.runs[-1].id' "$ARANEA_STATE_ROOT/project-actions.json")
unit=$(jq -r '.runs[-1].unitName' "$ARANEA_STATE_ROOT/project-actions.json")
call runs inspect "$run"
jq -es --arg r "$run" '.[-1].data.run.id==$r and .[-1].data.run.definitionSnapshot.name=="Configured from production editor"' "$TMPDIR/events" >/dev/null
jq -cn --arg u "$unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:"\u001b[31m<b>literal output</b>\u001b[0m"}' >"$manager/journal"
ui logs-restart "$run"
[[ $(wc -l <"$manager/launches") == 2 ]]
replacement=$(jq -r '.runs[]|select(.processState=="running")|.id' "$ARANEA_STATE_ROOT/project-actions.json")
[[ $replacement != "$run" ]]
call runs inspect "$run"
jq -es '.[-1].data.run.processState=="stopped"' "$TMPDIR/events" >/dev/null
call runs stop "$replacement"
# Actual failures/timeouts cross public schema1 envelopes without a success claim.
for mode in failed timeout; do
  echo "$mode" >"$manager/mode"
  call actions run "$project" "$action" --checkout "$checkout" 2>"$TMPDIR/expected-error" && exit 1
  jq -es '.[-1].status=="failed" and .[-1].data.run.processState=="failed"' "$TMPDIR/events" >/dev/null
  if [[ $mode == timeout ]]; then jq -es '.[-1].data.run.error.code=="TIMEOUT" and .[-1].data.run.exitSignal==15' "$TMPDIR/events" >/dev/null; fi
done
# Post-acceptance uncertainty cannot repeat; destroying/reopening UI observes same unit.
echo accepted-error >"$manager/mode"
ui uncertain
uncertain=$(jq -r '.runs[]|select(.processState=="unconfirmed")|.id' "$ARANEA_STATE_ROOT/project-actions.json")
launches=$(wc -l <"$manager/launches")
ui recover-stop "$uncertain"
[[ $(wc -l <"$manager/launches") == "$launches" ]]
# Two worktrees have separate run identities; optional readiness stays independent.
echo running >"$manager/mode"
jq '.name="Preview" | .kind="service" | .timeoutSeconds=null | .previewUrl="http://127.0.0.1:8181/"' "$TMPDIR/draft" | call actions configure "$project" --json-input
service=$(last | jq -r '.state.definitions[-1].id')
touch "$manager/unreachable"
command_action=$action
action=$service
ui run
action=$command_action
service_run=$(jq -r --arg a "$service" ' .runs[]|select(.actionId==$a)|.id' "$ARANEA_STATE_ROOT/project-actions.json")
call runs inspect "$service_run"
service_unit=$(last | jq -r '.run.unitName')
jq -es '.[-1].data.run.processState=="running" and .[-1].data.run.readiness=="unreachable"' "$TMPDIR/events" >/dev/null
rm "$manager/unreachable"
call runs refresh "$service_run"
jq -es '.[-1].data.run.processState=="running" and .[-1].data.run.readiness=="reachable"' "$TMPDIR/events" >/dev/null
call actions run "$project" "$service" --checkout "$checkout2"
worktree_run=$(last | jq -r '.run.id')
[[ $worktree_run != "$service_run" ]]
# Invocation/manager/boot loss refuses control/read effects without another submission.
cp "$manager/$service_unit" "$TMPDIR/proof"
sed -i 's/InvocationID=.*/InvocationID=22222222222222222222222222222222/' "$manager/$service_unit"
stops=$(wc -l <"$manager/stops")
refuse RUN_IDENTITY_LOST runs stop "$service_run"
refuse RUN_IDENTITY_LOST runs logs "$service_run"
[[ $(wc -l <"$manager/stops") == "$stops" ]]
cp "$TMPDIR/proof" "$manager/$service_unit"
touch "$manager/unavailable"
refuse OBSERVATION_UNAVAILABLE runs refresh "$service_run"
rm "$manager/unavailable"
cp "$ARANEA_STATE_ROOT/project-actions.json" "$TMPDIR/state"
jq --arg r "$service_run" '(.runs[]|select(.id==$r)|.bootId)="00000000-0000-0000-0000-000000000000"' "$TMPDIR/state" >"$ARANEA_STATE_ROOT/project-actions.json"
refuse RUN_IDENTITY_LOST runs stop "$service_run"
cp "$TMPDIR/state" "$ARANEA_STATE_ROOT/project-actions.json"
call runs refresh "$service_run"
jq -cn --arg u "$service_unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:("界"*100000)}' >"$manager/journal"
call runs logs "$service_run"
jq -es '.[-1].data.truncated and (.[-1].data.output|utf8bytelength)<=262144' "$TMPDIR/events" >/dev/null
# Removed registry entries preserve exact run authority, while fresh Run refuses.
jq '.projects=[]' "$ARANEA_STATE_ROOT/projects.json" >"$TMPDIR/removed"
mv "$TMPDIR/removed" "$ARANEA_STATE_ROOT/projects.json"
call runs inspect "$service_run"
call runs stop "$service_run"
call runs stop "$worktree_run"
refuse PROJECT_NOT_FOUND actions run "$project" "$service" --checkout "$checkout"
# Actual teardown/reactivation retains stable coordination and fences old ingress.
generation=$(cat "$ARANEA_STATE_ROOT/project-actions.json.lock")
generation=${generation:-initial}
inodes=$(stat -c %i "$ARANEA_STATE_ROOT/project-actions.json.lock" "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock")
"$repo_root/scripts/uninstall.sh" --yes --scope integration >"$TMPDIR/uninstall"
[[ ! -e $ARANEA_STATE_ROOT/project-actions.json ]]
"$backend" activate </dev/null >/dev/null
[[ $(stat -c %i "$ARANEA_STATE_ROOT/project-actions.json.lock" "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock") == "$inodes" ]]
if ARANEA_ACTION_GENERATION="$generation" "$backend" snapshot </dev/null >"$TMPDIR/fenced"; then exit 1; fi
jq -e '.error.code=="ACTION_REMOVED"' "$TMPDIR/fenced" >/dev/null
[[ ! -e $ARANEA_TEST_SANDBOX/repo/NEVER && ! -e $ARANEA_TEST_SANDBOX/worktree/NEVER && ! -e $manager/opened ]]
echo 'PASS composed CLI → store → actual UI/client → backend → exact-run lifecycle acceptance'
# Keep representative capture guards/layouts in the mandatory composed suite.
for capture in 'empty wide' 'invalid-editor narrow' 'long-output large-font'; do
  read -r scene size <<<"$capture"
  ARANEA_QML_SHELL_DIR="$shell_dir" ARANEA_ACTION_PREVIEW_QUICKSHELL="$qs" "$repo_root/tools/render-project-actions-preview" \
    --output "$TMPDIR/$scene.png" --scene "$scene" --size "$size" --scroll bottom >"$TMPDIR/$scene-render.log"
  grep -q 'effects=0' "$TMPDIR/$scene-render.log"
  echo "PASS inert production capture $scene/$size with unchanged state and reachable controls"
done
