#!/usr/bin/env bash
# Public agents JSON boundary uses the real store and an isolated IPC executable.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
cli="$repo_root/scripts/aranea"
export ACTIVITY_CALLS="$ARANEA_TEST_SANDBOX/calls" ACTIVITY_MODE=observed
mkdir -p "$ARANEA_TEST_SANDBOX/bin"
cat >"$ARANEA_TEST_SANDBOX/bin/omarchy-shell" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$ACTIVITY_CALLS"
case "$1 $2" in
 'aranea.activity request'|'aranea.activity reobserve') echo '{"ok":true,"operationId":"op-1","ownerId":"owner"}' ;;
 'aranea.activity operation')
   [[ "$ACTIVITY_MODE" != disconnected ]] || exit 1
   [[ "$3" == op-1 ]] || { echo '{"error":{"code":"OPERATION_LOST","message":"Gone","recovery":"Inspect"}}'; exit; }
   jq -cn --arg outcome "$ACTIVITY_MODE" '{id:"op-1",ownerId:(if $outcome=="restarted" then "other" else "owner" end),state:"completed",outcome:$outcome,steps:[],error:null}' ;;
 'aranea.projects snapshot') echo '{"sessionId":"project-owner","availability":{},"projects":[]}' ;;
 *) exit 1 ;;
esac
FAKE
chmod +x "$ARANEA_TEST_SANDBOX/bin/omarchy-shell"
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
# All events must be schema1; the final event owns the exit/result contract.
run_cli() {
  local expected=$1 rc=0
  shift
  "$cli" "$@" >"$ARANEA_TEST_SANDBOX/events" 2>"$ARANEA_TEST_SANDBOX/err" || rc=$?
  [[ "$rc" == "$expected" ]] || {
    cat "$ARANEA_TEST_SANDBOX/events" "$ARANEA_TEST_SANDBOX/err"
    echo "unexpected exit $rc, expected $expected"
    return 1
  }
  jq -es 'length>0 and all(.[];.schema==1) and .[-1].event=="completed"' "$ARANEA_TEST_SANDBOX/events" >/dev/null
}
run_cli 0 agents list --json
run_cli 2 agents focus --help --json
[[ ! -f "$ACTIVITY_CALLS" ]]
register='{"action":"register","args":{"provider":"claude","providerSessionId":"session","producerEpoch":"epoch","tasks":[]}}'
"$repo_root/scripts/aranea-agent-store" mutate <<<"$register" >/dev/null
event=$(jq -cn --arg cwd "$ARANEA_TEST_SANDBOX" '{schemaVersion:1,eventId:"e1",provider:"claude",providerSessionId:"session",producerEpoch:"epoch",sequence:1,taskId:"task",kind:"snapshot",payload:{cwd:$cwd,reportedState:"working",description:"Real report"}}')
run_cli 0 agents report --json-input --json <<<"$event"
run_cli 0 agents inspect task --json
jq -es '.[-1].data.task.description=="Real report" and .[-1].data.task.verification.status=="unknown"' "$ARANEA_TEST_SANDBOX/events" >/dev/null
run_cli 1 agents report --json-input --json <<<"$event $event"
run_cli 0 agents focus task --json
[[ $(rg -c 'aranea.activity request' "$ACTIVITY_CALLS") == 1 ]]
export ACTIVITY_MODE=partial
run_cli 1 agents operation op-1 --json
run_cli 1 agents operation op-1 --reobserve --json
[[ $(rg -c 'aranea.activity request' "$ACTIVITY_CALLS") == 1 ]]
export ACTIVITY_MODE=restarted
run_cli 1 agents reopen task --json
jq -es '.[-1].code=="OPERATION_LOST" and .[-1].data.outcome=="partial"' "$ARANEA_TEST_SANDBOX/events" >/dev/null
export ACTIVITY_MODE=disconnected
run_cli 1 agents reopen task --json
jq -es '.[-1].operationId=="op-1" and .[-1].data.outcome=="partial"' "$ARANEA_TEST_SANDBOX/events" >/dev/null
[[ $(rg -c 'aranea.activity request' "$ACTIVITY_CALLS") == 3 ]]
run_cli 0 agents adapter status claude --json
run_cli 0 agents adapter install claude --json
[[ -f "$HOME/.claude/settings.json" ]]
run_cli 0 agents adapter remove claude --json
run_cli 0 capabilities --json
jq -es '.[-1].data | any(.operations[];.name=="projects.operation") and any(.operations[];.name=="agents.operation") and .activity.schemaVersion==1' "$ARANEA_TEST_SANDBOX/events" >/dev/null
run_cli 2 agents reopen task --command evil --json
run_cli 0 agents register --json-input --json <<<"$(jq '.args | .producerEpoch="next-epoch"' <<<"$register")"
run_cli 0 agents list --json
jq -es '.[-1].data.tasks|length==0' "$ARANEA_TEST_SANDBOX/events" >/dev/null
echo 'PASS real report/store, schema1, strict syntax, operation reconnection, adapter sandbox and retained capabilities'

unset CODEX_HOME
run_cli 0 agents adapter install codex --json
[[ -f "$HOME/.codex/hooks.json" ]]
run_cli 0 capabilities --json
jq -es '.[-1].data.activity.providers|index("codex")!=null' "$ARANEA_TEST_SANDBOX/events" >/dev/null
run_cli 0 agents adapter remove codex --json
echo 'PASS public Codex adapter and capabilities'
