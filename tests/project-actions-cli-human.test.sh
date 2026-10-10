#!/usr/bin/env bash
# Human action output retains failed journal text and exact partial/observer receipts.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
cli="$repo_root/scripts/aranea"
manager="$ARANEA_TEST_SANDBOX/manager"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo" "$manager"
for tool in systemd-run systemctl journalctl curl xdg-open; do ln -s "$repo_root/tests/fixtures/project-actions-manager.sh" "$ARANEA_TEST_SANDBOX/bin/$tool"; done
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
# Wait for only these bounded sandbox workers before deleting their state.
wait_workers() {
  for _ in {1..160}; do
    if ! compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null; then return; fi
    sleep .1
  done
  return 1
}
sandbox_on_exit wait_workers
git init -q "$ARANEA_TEST_SANDBOX/repo"
jq -cn --arg p "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
printf '%s\n' '{"name":"Checks","kind":"command","argv":["printf"],"cwdRelative":".","previewUrl":null}' | "$cli" projects actions configure "$project" --json-input --json >"$TMPDIR/configured"
action=$(jq -rs '.[-1].data.state.definitions[0].id' "$TMPDIR/configured")
failures=0
# Accumulate every missing piece rather than stopping at the first omitted field.
contains() {
  if ! grep -Fq -- "$2" "$1"; then
    echo "human output omitted $2" >&2
    failures=$((failures + 1))
  fi
}
echo failed >"$manager/mode"
status=0
"$cli" projects actions run "$project" "$action" --json >"$TMPDIR/failed" 2>"$TMPDIR/failed-error" || status=$?
[[ $status == 1 ]]
run=$(jq -rs '.[-1].data.runId' "$TMPDIR/failed")
unit=$(jq -rs '.[-1].data.run.unitName' "$TMPDIR/failed")
# 200 authentic filtered records reach the journal bound; the marker must remain literal.
jq -cn --arg u "$unit" 'range(200) | {_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:"APPLICATION FAILURE EVIDENCE <literal>"}' >"$manager/journal"
status=0
"$cli" projects runs logs "$run" >"$TMPDIR/logs" 2>"$TMPDIR/logs-error" || status=$?
[[ $status == 1 ]]
contains "$TMPDIR/logs" 'APPLICATION FAILURE EVIDENCE <literal>'
contains "$TMPDIR/logs" "$run"
contains "$TMPDIR/logs" 'failed'
contains "$TMPDIR/logs" 'Exit code: 7'
contains "$TMPDIR/logs" '[Output truncated]'
# Accepted native transport failure: human output must retain both recovery identifiers.
echo accepted-error >"$manager/mode"
request=req-00000000-0000-4000-8000-000000000071
status=0
"$cli" projects actions run "$project" "$action" --request-id "$request" >"$TMPDIR/partial" 2>"$TMPDIR/partial-error" || status=$?
[[ $status == 1 ]]
run=$(jq -r --arg q "$request" '.requests[]|select(.requestId==$q)|.runId' "$ARANEA_STATE_ROOT/project-actions.json")
contains "$TMPDIR/partial" "$run"
contains "$TMPDIR/partial" "$request"
contains "$TMPDIR/partial" 'unconfirmed'
contains "$TMPDIR/partial" 'Refresh'
"$cli" projects runs stop "$run" --json >"$TMPDIR/stopped"
# Main-process exit remains visible even when cleanup makes the result partial.
echo fast >"$manager/mode"
touch "$manager/stop-fails"
request=req-00000000-0000-4000-8000-000000000073
status=0
"$cli" projects actions run "$project" "$action" --request-id "$request" >"$TMPDIR/cleanup" 2>"$TMPDIR/cleanup-error" || status=$?
[[ $status == 1 ]]
run=$(jq -r --arg q "$request" '.requests[]|select(.requestId==$q)|.runId' "$ARANEA_STATE_ROOT/project-actions.json")
contains "$TMPDIR/cleanup" "$run"
contains "$TMPDIR/cleanup" "$request"
contains "$TMPDIR/cleanup" 'succeeded'
contains "$TMPDIR/cleanup" 'Exit code: 0'
contains "$TMPDIR/cleanup" STOP_UNCONFIRMED
contains "$TMPDIR/cleanup" 'Refresh'
rm "$manager/stop-fails"
"$cli" projects runs stop "$run" --json >"$TMPDIR/cleanup-stopped"
# A configured command timeout preserves the native exit signal and recovery text.
echo timeout >"$manager/mode"
status=0
"$cli" projects actions run "$project" "$action" >"$TMPDIR/command-timeout" 2>"$TMPDIR/command-timeout-error" || status=$?
[[ $status == 1 ]]
contains "$TMPDIR/command-timeout" TIMEOUT
contains "$TMPDIR/command-timeout" 'Exit signal: 15'
contains "$TMPDIR/command-timeout" 'Review'
# Real ten-second observer deadline expires while bounded sandbox cleanup is held.
echo fast >"$manager/mode"
echo 1.6 >"$manager/show-delay"
touch "$manager/stop-delays"
request=req-00000000-0000-4000-8000-000000000072
"$cli" projects actions run "$project" "$action" --request-id "$request" >"$TMPDIR/timeout" 2>"$TMPDIR/timeout-error" &
observer=$!
# shellcheck disable=SC2016
sandbox_on_exit 'wait "$observer" 2>/dev/null || true'
accepted=false
for _ in {1..100}; do
  if grep -Fq -- "$request" "$TMPDIR/timeout"; then
    accepted=true
    break
  fi
  sleep .05
done
[[ $accepted == true ]]
run=$(jq -r --arg q "$request" '.requests[]|select(.requestId==$q)|.runId' "$ARANEA_STATE_ROOT/project-actions.json")
contains "$TMPDIR/timeout" "$run"
contains "$TMPDIR/timeout" "$request"
status=0
wait "$observer" || status=$?
[[ $status == 1 ]]
contains "$TMPDIR/timeout" OBSERVATION_TIMEOUT
contains "$TMPDIR/timeout" "$run"
contains "$TMPDIR/timeout" "$request"
contains "$TMPDIR/timeout" 'Process:'
contains "$TMPDIR/timeout" 'Refresh'
wait_workers
jq -e --arg r "$run" 'any(.runs[];.id==$r and .processState=="succeeded" and .submissionUnconfirmed)' "$ARANEA_STATE_ROOT/project-actions.json" >/dev/null
[[ $(wc -l <"$manager/launches") == 5 ]]
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
((failures == 0))
echo 'human action CLI: failed journal, truncation, partial and early/timeout receipts retained'
