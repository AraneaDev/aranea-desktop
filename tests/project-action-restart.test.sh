#!/usr/bin/env bash
# Actual backend/store/Git revision fencing at both sides of exact-run Stop.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
backend="$repo_root/scripts/aranea-project-actions"
manager="$ARANEA_TEST_SANDBOX/manager"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo" "$manager"
for tool in systemd-run systemctl journalctl curl xdg-open; do ln -s "$repo_root/tests/fixtures/project-actions-manager.sh" "$ARANEA_TEST_SANDBOX/bin/$tool"; done
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
git init -q "$ARANEA_TEST_SANDBOX/repo"
jq -cn --arg path "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$path]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
checkout=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/project")
# Retain envelopes, including refusals, through the real shared backend.
call() { "$backend" "$1" >"$TMPDIR/result" || true; }
# Assert an authoritative refusal and print useful RED evidence when it differs.
refusal() {
  jq -e --arg code "$1" '.ok==false and .error.code==$code' "$TMPDIR/result" >/dev/null || {
    cat "$TMPDIR/result" >&2
    exit 1
  }
}
jq -cn --arg p "$project" '{projectId:$p,definition:{name:"Restart review",kind:"command",argv:["printf","one"],cwdRelative:".",timeoutSeconds:30,previewUrl:null}}' >"$TMPDIR/config"
call configure <"$TMPDIR/config"
action=$(jq -r '.state.definitions[0].id' "$TMPDIR/result")
jq --arg a "$action" '.definition.id=$a' "$TMPDIR/config" >"$TMPDIR/edit"
jq -cn --arg p "$project" --arg c "$checkout" --arg a "$action" '{projectId:$p,checkoutId:$c,actionId:$a,requestId:"req-00000000-0000-4000-8000-000000000001"}' >"$TMPDIR/start"
call start <"$TMPDIR/start"
run=$(jq -r '.run.id' "$TMPDIR/result")
call configure <"$TMPDIR/edit"
jq -cn --arg r "$run" '{runId:$r,requestId:"req-00000000-0000-4000-8000-000000000002",expectedDefinitionRevision:1}' | call restart
refusal ACTION_CONFLICT
[[ ! -e "$manager/stops" && $(wc -l <"$manager/launches") == 1 ]]
jq -cn --arg r "$run" '{runId:$r}' | call stop
jq '.requestId="req-00000000-0000-4000-8000-000000000003"' "$TMPDIR/start" | call start
run=$(jq -r '.run.id' "$TMPDIR/result")
jq -cn --arg r "$run" '{runId:$r,requestId:"req-00000000-0000-4000-8000-000000000004",expectedDefinitionRevision:2}' >"$TMPDIR/restart"
call restart <"$TMPDIR/restart"
jq -e '.ok and .run.definitionRevision==2 and .run.processState=="running"' "$TMPDIR/result" >/dev/null
accepted=$(jq -r '.run.id' "$TMPDIR/result")
launches=$(wc -l <"$manager/launches") stops=$(wc -l <"$manager/stops")
call configure <"$TMPDIR/edit"
call restart <"$TMPDIR/restart"
jq -e --arg id "$accepted" '.ok and .reused and .run.id==$id and .run.definitionRevision==2' "$TMPDIR/result" >/dev/null
[[ $(wc -l <"$manager/launches") == "$launches" && $(wc -l <"$manager/stops") == "$stops" ]]
jq '.expectedDefinitionRevision=0 | .requestId="req-00000000-0000-4000-8000-000000000007"' "$TMPDIR/restart" | call restart
refusal INVALID_REQUEST
jq -cn --arg r "$accepted" '{runId:$r}' | call stop
jq '.requestId="req-00000000-0000-4000-8000-000000000005"' "$TMPDIR/start" | call start
run=$(jq -r '.run.id' "$TMPDIR/result")
launches=$(wc -l <"$manager/launches")
# Hold only the isolated reset transport after terminal proof has persisted.
# A direct local store writer represents an edit racing the next fresh start.
touch "$manager/reset-hold"
jq -cn --arg r "$run" '{runId:$r,requestId:"req-00000000-0000-4000-8000-000000000006",expectedDefinitionRevision:3}' >"$TMPDIR/restart-race"
"$backend" restart <"$TMPDIR/restart-race" >"$TMPDIR/race-result" &
restart_pid=$!
# Cleanup waits for this bounded isolated worker before deleting its state root.
cleanup_restart() {
  rm -f "$manager/reset-hold"
  wait "$restart_pid" 2>/dev/null || true
}
sandbox_on_exit cleanup_restart
for ((attempt = 0; attempt < 200; attempt++)); do
  [[ -e "$manager/reset-entered" ]] && break
  sleep .01
done
[[ -e "$manager/reset-entered" ]] || {
  echo 'Restart never reached final cleanup barrier' >&2
  exit 1
}
jq -e --arg id "$run" 'any(.runs[];.id==$id and .processState=="stopped" and (.submissionUnconfirmed|not))' "$ARANEA_STATE_ROOT/project-actions.json" >/dev/null
jq '{action:"configure",args:{projectId,definition}}' "$TMPDIR/edit" | "$repo_root/scripts/aranea-project-action-store" mutate >"$TMPDIR/local-edit"
rm "$manager/reset-hold"
wait "$restart_pid" || true
cp "$TMPDIR/race-result" "$TMPDIR/result"
refusal ACTION_CONFLICT
[[ $(wc -l <"$manager/launches") == "$launches" ]]
jq -e 'all(.requests[];.requestId!="req-00000000-0000-4000-8000-000000000006")' "$ARANEA_STATE_ROOT/project-actions.json" >/dev/null
