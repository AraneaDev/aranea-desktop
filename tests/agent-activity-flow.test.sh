#!/usr/bin/env bash
# Removing native mapping, exact checkout association, durable headless reports,
# owner/client publication or no-repeat operation protection must fail this flow.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state" ARANEA_FLOW_ROOT="$repo_root"
cli="$repo_root/scripts/aranea"
hook="$repo_root/scripts/aranea-agent-hook"
store="$repo_root/scripts/aranea-agent-store"
checkout="$ARANEA_TEST_SANDBOX/project with spaces"
sibling="$ARANEA_TEST_SANDBOX/project review"
mkdir -p "$checkout" "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/providers"
git init -q "$checkout"
git -C "$checkout" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
git -C "$checkout" worktree add -qb review "$sibling"
"$cli" projects register --path "$checkout" --json >"$TMPDIR/register"
"$cli" projects register --path "$sibling" --json >/dev/null
project=$(jq -r 'select(.event=="completed")|.data.state.projects[0].id' "$TMPDIR/register")
# Real executable ancestry is retained; each fixture owns its native callbacks.
cat >"$TMPDIR/provider.sh" <<'PROVIDER'
#!/bin/bash
set -euo pipefail
while [[ ! -e "$4.stop" ]]; do
  if [[ -f "$4.event" ]]; then
    /bin/bash "$1" "$2" <"$4.event"
    rm "$4.event"
    touch "$4.done"
  fi
  sleep .02
done
PROVIDER
pids=()
for provider in claude codex; do
  cp /bin/bash "$ARANEA_TEST_SANDBOX/providers/$provider"
  "$ARANEA_TEST_SANDBOX/providers/$provider" "$TMPDIR/provider.sh" "$hook" "$provider" "$checkout" "$TMPDIR/$provider" &
  pids+=("$!")
done
owner_pid=""
work=$(mktemp -d /tmp/aranea-activity-flow.XXXXXX)
# Only owned fixture/provider/heartbeat process groups are stopped.
cleanup_flow() {
  [[ -z "$owner_pid" ]] || {
    kill -- "-$owner_pid" 2>/dev/null || true
    wait "$owner_pid" 2>/dev/null || true
  }
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  for receipt in "$ARANEA_STATE_ROOT"/agent-heartbeats/*.json; do
    [[ -f "$receipt" ]] || continue
    kill "$(jq -r .pid "$receipt")" 2>/dev/null || true
  done
  if ((status != 0)); then
    cp "$work/log" /tmp/task7-flow-failure.log 2>/dev/null || true
    cp "$ARANEA_TEST_SANDBOX/guard.log" /tmp/task7-flow-guard.log 2>/dev/null || true
  fi
  rm -rf "$work"
}
sandbox_on_exit cleanup_flow
# Deliver actual native input and wait for the provider-owned callback completion.
deliver() {
  local provider=$1 session=12345678-1234-1234-1234-123456789abc
  [[ "$provider" != codex ]] || session=abcdef12-1234-1234-1234-123456789abc
  rm -f "$TMPDIR/$provider.done"
  jq -cn --arg cwd "$sibling" --arg session "$session" --argjson event "$2" '$event+{session_id:$session,cwd:$cwd}' >"$TMPDIR/$provider.event"
  for _ in {1..100}; do
    [[ ! -e "$TMPDIR/$provider.done" ]] || return 0
    sleep .05
  done
  echo 'FAIL native callback timed out'
  return 1
}
for provider in claude codex; do
  deliver "$provider" '{"hook_event_name":"SessionStart","source":"startup"}'
  deliver "$provider" '{"hook_event_name":"UserPromptSubmit","prompt_id":"one","turn_id":"one","prompt":"Flow task"}'
done
"$cli" agents list --json >"$TMPDIR/list"
jq -se --arg cwd "$sibling" 'last.data.tasks | length==2 and all(.[];.association.status=="registered" and .association.cwd==$cwd and .verification.status=="unknown" and .freshness=="connected") and (map(.provider)|sort)==["claude","codex"]' "$TMPDIR/list" >/dev/null
"$repo_root/scripts/aranea-project-store" snapshot >"$TMPDIR/projects"
jq -en --slurpfile list "$TMPDIR/list" --slurpfile projects "$TMPDIR/projects" --arg cwd "$sibling" '$projects[0].state.projects[0] as $p | $p.checkouts[] | select(.path==$cwd) | .id as $id | all($list[-1].data.tasks[];.association.projectId==$p.id and .association.checkoutId==$id)' >/dev/null
deliver claude '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_use_id":"question","tool_input":{"questions":[{"question":"Review which checkout?"}]}}'
deliver codex '{"hook_event_name":"Stop","turn_id":"one","last_assistant_message":"Codex result"}'
"$cli" agents list --json >"$TMPDIR/list"
jq -se 'last.data.tasks | any(.[];.provider=="claude" and .reportedState=="needs-input") and any(.[];.provider=="codex" and .reportedState=="ready-for-review" and .result=="Codex result" and .verification.status=="unknown")' "$TMPDIR/list" >/dev/null
# The explicit report uses the public schema and native epoch/sequence, not adapter internals.
"$store" snapshot >"$TMPDIR/state"
jq -cn --slurpfile state "$TMPDIR/state" '$state[0].state as $s | ($s.tasks[]|select(.provider=="codex")) as $t | ($s.sessions[]|select(.provider=="codex")) as $session | {schemaVersion:1,eventId:"explicit-verification",provider:$t.provider,providerSessionId:$t.providerSessionId,producerEpoch:$t.producerEpoch,sequence:($session.highWaterSequence+1),taskId:$t.taskId,kind:"verification",payload:{status:"reported-pass",summary:"Fixture verification passed",commands:["fixture-check"]}}' >"$TMPDIR/report"
"$cli" agents report --json-input --json <"$TMPDIR/report" >"$TMPDIR/reported"
deliver codex '{"hook_event_name":"SessionEnd","reason":"exit"}'
"$cli" agents list --json >"$TMPDIR/list"
jq -se 'last.data.tasks | any(.[];.provider=="codex" and .reportedState=="ready-for-review" and .result=="Codex result" and .verification.status=="reported-pass" and .freshness=="connection-lost")' "$TMPDIR/list" >/dev/null
quickshell_bin=""
while IFS= read -r candidate; do [[ "$candidate" == */tests/guard-bin/* ]] || {
  quickshell_bin="$candidate"
  break
}; done < <(type -ap quickshell)
[[ -n "$quickshell_bin" && -f /usr/share/omarchy/shell/Commons/qmldir ]]
mkdir -p "$work/cfg/plugins" "$work/run"
chmod 700 "$work/run"
ln -s /usr/share/omarchy/shell/Commons "$work/cfg/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/cfg/Ui"
ln -s "$repo_root/tests/qml/lib" "$work/cfg/lib"
for plugin in "$repo_root"/plugins/araneadev.*; do ln -s "$plugin" "$work/cfg/plugins/${plugin##*/}"; done
cp "$repo_root/tests/qml/fixtures/agent-activity-flow.qml" "$work/cfg/shell.qml"
export FLOW_BIN="$quickshell_bin" FLOW_CONFIG="$work/cfg" FLOW_RUNTIME="$work/run"
cat >"$ARANEA_TEST_SANDBOX/bin/omarchy-shell" <<'BRIDGE'
#!/bin/bash
set -euo pipefail
[[ "${FLOW_DISCONNECT:-0}" != 1 || "$2" != operation ]] || exit 1
exec env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$FLOW_RUNTIME" "$FLOW_BIN" ipc -p "$FLOW_CONFIG" call "$@"
BRIDGE
chmod +x "$ARANEA_TEST_SANDBOX/bin/omarchy-shell"
# Shared host Style probes have fixed fixture replies; all other desktop commands stay trapped.
cat >"$ARANEA_TEST_SANDBOX/bin/hyprctl" <<'DESKTOP'
#!/bin/bash
if [[ "$*" == '-j getoption general:gaps_out' || "$*" == '-j getoption decoration:rounding' ]]; then
  printf '{"int":0}\n'
  exit 0
fi
printf 'unexpected desktop call: %s\n' "$*" >> "$ARANEA_TEST_SANDBOX/guard.log"
exit 99
DESKTOP
chmod +x "$ARANEA_TEST_SANDBOX/bin/hyprctl"
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
# Start/restart actual production IPC owner; initial historical reports remain visible.
start_owner() {
  (cd "$work" && exec setsid env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$work/run" "$quickshell_bin" -p "$work/cfg") >"$work/log" 2>&1 &
  owner_pid=$!
  for _ in {1..100}; do
    if omarchy-shell fixture snapshot 2>/dev/null | jq -e '.owner.availability.ready and .client.revision==.owner.revision' >/dev/null 2>&1; then return 0; fi
    sleep .1
  done
  cat "$work/log"
  return 1
}
# Assert owner → actual client → production rows against literal user-visible outcomes.
assert_views() {
  omarchy-shell fixture snapshot >"$TMPDIR/view"
  jq -e '.owner.tasks|length==3' "$TMPDIR/view" >/dev/null
  jq -e '.rows | any(.[];.providerLabel=="Codex" and .verificationLabel=="Verification reported passed" and .reportedLabel=="Ready for review") and any(.[];.providerLabel=="Claude Code" and .stateLabel=="Needs input" and .attention==true) and any(.[];.summary=="Headless retained result" and .primary.kind=="inspect-result")' "$TMPDIR/view" >/dev/null
  jq -e '.owner.tasks==.client.tasks' "$TMPDIR/view" >/dev/null
}
start_owner
owner_before=$(omarchy-shell aranea.activity snapshot | jq -r .ownerId)
# Shut owner down, then report through the headless public interface.
kill -- "-$owner_pid"
wait "$owner_pid" || true
owner_pid=""
"$cli" agents register --json-input --json <<<'{"provider":"claude","providerSessionId":"manual","producerEpoch":"manual-epoch","tasks":[]}' >/dev/null
"$cli" agents report --json-input --json <<EOF_REPORT >/dev/null
{"schemaVersion":1,"eventId":"manual-result","provider":"claude","providerSessionId":"manual","producerEpoch":"manual-epoch","sequence":1,"taskId":"headless","kind":"snapshot","payload":{"cwd":"$checkout","reportedState":"finished","description":"Headless retained result","result":"Saved while owner stopped"}}
EOF_REPORT
start_owner
[[ "$(omarchy-shell aranea.activity snapshot | jq -r .ownerId)" != "$owner_before" ]]
assert_views
omarchy-shell fixture inspect headless | jq -e '.selected.key=="headless" and .resultText=="Saved while owner stopped"' >/dev/null
claude_task=$(jq -r '.owner.tasks[]|select(.provider=="claude" and .source=="native")|.taskId' "$TMPDIR/view")
# A disconnected observer keeps the accepted ID; reconnect/reobserve must never launch again.
rc=0
FLOW_DISCONNECT=1 "$cli" agents reopen "$claude_task" --json >"$TMPDIR/events" 2>"$TMPDIR/disconnected" || rc=$?
[[ "$rc" == 1 ]]
op=$(jq -r 'select(.event=="completed")|.operationId' "$TMPDIR/events")
[[ -n "$op" && "$op" != null ]]
sleep .2
rc=0
"$cli" agents operation "$op" --json >"$TMPDIR/events" || rc=$?
[[ "$rc" == 1 ]]
jq -se 'last.data.outcome=="partial" and (last.data.operation.steps|length>0)' "$TMPDIR/events" >/dev/null
rc=0
"$cli" agents operation "$op" --reobserve --json >"$TMPDIR/events" || rc=$?
[[ "$rc" == 1 ]]
omarchy-shell fixture snapshot | jq -e '.launches==1' >/dev/null
# Manual provenance and a removed exact checkout cannot authorize a provider launch.
rc=0
"$cli" agents reopen headless --json >"$TMPDIR/refused" || rc=$?
[[ "$rc" == 1 ]]
jq -se 'last.code=="RESUME_UNAVAILABLE" and last.data.outcome=="failed"' "$TMPDIR/refused" >/dev/null
omarchy-shell aranea.activity request '{"action":"focus","taskId":"removed-task"}' | jq -e '.ok==false and .error.code=="TASK_NOT_FOUND"' >/dev/null
omarchy-shell fixture snapshot | jq -e '.launches==1' >/dev/null
# Removing registration makes retained checkout actions stale, never substituting its sibling.
"$cli" projects remove "$project" --json >/dev/null
omarchy-shell fixture refresh >/dev/null
for _ in {1..100}; do
  if omarchy-shell aranea.activity snapshot | jq -e 'all(.tasks[];.association.status=="unavailable")' >/dev/null; then break; fi
  sleep .05
done
rc=0
"$cli" agents reopen "$claude_task" --json >"$TMPDIR/stale" || rc=$?
[[ "$rc" == 1 ]]
jq -se 'last.code=="PROJECT_UNASSIGNED" and last.data.outcome=="failed"' "$TMPDIR/stale" >/dev/null
omarchy-shell fixture snapshot | jq -e '.launches==1' >/dev/null
omarchy-shell fixture finish >/dev/null
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
if rg -q 'QMLTEST FAIL|TypeError|ReferenceError|Unable to assign|Binding loop|Failed to load configuration' "$work/log"; then
  cat "$work/log"
  exit 1
fi
echo 'PASS native Claude/Codex → exact Git checkout/store/CLI → IPC owner/client/Tasks, headless restart, verification/result/disconnect, stale refusal and reconnect no relaunch'
# Preserve the existing real owner/client identity/late acceptance regressions in this boundary run.
ARANEA_CHECK_REQUIRE_ALL=1 bash "$repo_root/tests/qml-behaviour.test.sh" activity-controller activity-client activity-resume activity-late-launch activity-stale-callback
