#!/usr/bin/env bash
# Real native heartbeat wins a stale fixture report; only that refusal may retry.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
store="$repo_root/scripts/aranea-agent-store"
report="$repo_root/tests/lib/agent-adapter-fixture-report.sh"
mkdir -p "$ARANEA_TEST_SANDBOX/provider"
cp /bin/bash "$ARANEA_TEST_SANDBOX/provider/claude"
cat >"$TMPDIR/provider.sh" <<'PROVIDER'
#!/bin/bash
set -euo pipefail
printf '%s\n' '{"session_id":"fixture-report","hook_event_name":"SessionStart","cwd":"/tmp"}' | /bin/bash "$1" claude
printf '%s\n' '{"session_id":"fixture-report","hook_event_name":"UserPromptSubmit","prompt_id":"one","prompt":"Fixture report","cwd":"/tmp"}' | /bin/bash "$1" claude
touch "$2.ready"
while [[ ! -e "$2.go" ]]; do sleep .05; done
printf '%s\n' '{"session_id":"fixture-report","hook_event_name":"SessionEnd","cwd":"/tmp"}' | /bin/bash "$1" claude
PROVIDER
"$ARANEA_TEST_SANDBOX/provider/claude" "$TMPDIR/provider.sh" "$repo_root/scripts/aranea-agent-hook" "$TMPDIR/provider" >"$TMPDIR/provider.stdout" 2>"$TMPDIR/provider.stderr" &
provider_pid=$!
# Kill only this inert sandbox provider if any assertion fails.
# shellcheck disable=SC2016
sandbox_on_exit 'kill "$provider_pid" 2>/dev/null || true; wait "$provider_pid" 2>/dev/null || true'
for _ in {1..100}; do
  [[ ! -e "$TMPDIR/provider.ready" ]] || break
  sleep .05
done
[[ -e "$TMPDIR/provider.ready" ]]
"$store" snapshot >"$TMPDIR/before"
jq -e '.state.sessions[] | select(.providerSessionId=="fixture-report") | .provenance != null and .nativeMetadata.currentTaskId != null' "$TMPDIR/before" >/dev/null
sequence=$(jq '.state.sessions[] | select(.providerSessionId=="fixture-report") | .highWaterSequence' "$TMPDIR/before")
# Wait outside the original adapter ready deadline for an authentic next tick.
heartbeat_won=false
for _ in {1..200}; do
  "$store" snapshot >"$TMPDIR/current"
  if jq -e --argjson sequence "$sequence" '.state.sessions[] | select(.providerSessionId=="fixture-report") | any(.receipts[];.sequence > $sequence and (.eventId | startswith("AraneaHeartbeat:")))' "$TMPDIR/current" >/dev/null; then
    heartbeat_won=true
    break
  fi
  sleep .1
done
[[ "$heartbeat_won" == true ]]
jq -c '.state.sessions[] | select(.providerSessionId=="fixture-report") | {action:"report",args:{schemaVersion:1,eventId:"SubagentStop:forged:receipt",provider:"claude",providerSessionId:.providerSessionId,producerEpoch:.producerEpoch,sequence:(.highWaterSequence+1),taskId:.nativeMetadata.currentTaskId,kind:"diagnostic",payload:{summary:"Explicit report"}}}' "$TMPDIR/before" >"$TMPDIR/request"
/bin/bash "$report" "$store" "$TMPDIR/attempts" <"$TMPDIR/request" >"$TMPDIR/accepted"
jq -se '.[0].error.code=="STALE_SEQUENCE" and .[-1].ok and ([.[] | select(.ok)] | length)==1' "$TMPDIR/attempts" >/dev/null
jq -e '.state.sessions[] | select(.providerSessionId=="fixture-report") | ([.receipts[] | select(.eventId=="SubagentStop:forged:receipt")] | length)==1 and (.nativeMetadata.observedHooks | index("SubagentStop")==null)' "$TMPDIR/accepted" >/dev/null
"$repo_root/scripts/aranea-agent-adapter" status claude | jq -e 'all(.state.capabilities.optionalHooks[];.runtimeObserved==false and .available==false)' >/dev/null
# Finish the authentic provider and wait for its heartbeat writer to exit before
# asserting immutable state. A scheduling pause cannot race a legitimate next tick.
touch "$TMPDIR/provider.go"
wait "$provider_pid"
for _ in {1..170}; do
  if ! compgen -G "$XDG_STATE_HOME/aranea/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .1
done
if compgen -G "$XDG_STATE_HOME/aranea/agent-heartbeats/*.json" >/dev/null; then exit 1; fi
# A different error remains fatal on its first attempt, with state unchanged.
"$store" snapshot >"$TMPDIR/error-before"
cp "$XDG_STATE_HOME/aranea/agent-activity.json" "$TMPDIR/error-state-before"
jq '.args.eventId="invalid-task-report" | .args.taskId="fixture-task-missing" | .args.sequence=100000' "$TMPDIR/request" >"$TMPDIR/bad-request"
if /bin/bash "$report" "$store" "$TMPDIR/errors" <"$TMPDIR/bad-request" >"$TMPDIR/error-result" 2>"$TMPDIR/error-stderr"; then exit 1; fi
jq -se 'length==1 and .[0].error.code=="TASK_NOT_FOUND"' "$TMPDIR/errors" >/dev/null
cmp "$XDG_STATE_HOME/aranea/agent-activity.json" "$TMPDIR/error-state-before"
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
echo 'adapter fixture report: authentic heartbeat refusal, single acceptance and other-error rejection passed'
