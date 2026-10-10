#!/usr/bin/env bash
# Cleanup protection and faithful journal JSON regressions through the real backend.
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
jq -cn --arg p "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
checkout=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/project")
failures=0
# Accumulate independent review failures so both findings have real RED evidence.
check() {
  local label=$1 filter=$2
  if ! jq -e "$filter" "$TMPDIR/result" >/dev/null; then
    echo "$label" >&2
    jq -c '{ok,error,runId:.run.id,processState:.run.processState,submissionUnconfirmed:.run.submissionUnconfirmed,exitCode:.run.exitCode,truncated,output}' "$TMPDIR/result" >&2
    failures=$((failures + 1))
  fi
}
# Retain one real JSON envelope even for intentionally unsuccessful operations.
call() { "$backend" "$1" >"$TMPDIR/result" || true; }
# Create a definition and an explicit request for this exact real checkout.
configure() {
  jq -cn --arg p "$project" '{projectId:$p,definition:{name:"Review",kind:"command",argv:["printf","literal"],cwdRelative:".",timeoutSeconds:30,previewUrl:null}}' | call configure
  action=$(jq -r '.state.definitions[-1].id' "$TMPDIR/result")
  jq -cn --arg p "$project" --arg c "$checkout" --arg a "$action" '{projectId:$p,checkoutId:$c,actionId:$a,requestId:"req-00000000-0000-4000-8000-000000000001"}' >"$TMPDIR/start"
}
configure
echo fast >"$manager/mode"
touch "$manager/stop-fails"
call start <"$TMPDIR/start"
check 'cleanup failed but receipt became unprotected' '.ok==false and .run.processState=="succeeded" and .run.exitCode==0 and .run.submissionUnconfirmed and .run.outcome=="partial"'
run=$(jq -r .run.id "$TMPDIR/result")
unit=$(jq -r .run.unitName "$TMPDIR/result")
jq -cn --arg r "$run" '{runId:$r}' >"$TMPDIR/run"
jq '.requestId="req-00000000-0000-4000-8000-000000000002"' "$TMPDIR/start" | call start
check 'new start replaced unresolved terminal cleanup' ".reused and .run.id==\"$run\""
call refresh <"$TMPDIR/run"
check 'refresh discarded cleanup uncertainty' '.ok==false and .run.submissionUnconfirmed and .run.exitCode==0'
call stop <"$TMPDIR/run"
check 'stop incorrectly succeeded while release failed' '.ok==false and .error.code=="STOP_UNCONFIRMED" and .run.submissionUnconfirmed and .run.exitCode==0'
jq '.requestId="req-00000000-0000-4000-8000-000000000003"' "$TMPDIR/run" | call restart
check 'restart launched through failed cleanup' '.ok==false and .error.code=="STOP_UNCONFIRMED"'
if [[ $(wc -l <"$manager/launches") != 1 ]]; then
  echo 'cleanup uncertainty allowed duplicate units' >&2
  failures=$((failures + 1))
fi
call deactivate </dev/null
check 'deactivate falsely forgot active/exited unit' '.ok==false and .run.submissionUnconfirmed and .run.exitCode==0'
if [[ ! -f $ARANEA_STATE_ROOT/project-actions.json ]]; then
  echo 'deactivate erased protected cleanup evidence' >&2
  failures=$((failures + 1))
fi
rm "$manager/stop-fails"
if [[ -f $ARANEA_STATE_ROOT/project-actions.json ]]; then
  call stop <"$TMPDIR/run"
  check 'successful cleanup failed to preserve and release exit result' '.ok and .run.processState=="succeeded" and .run.exitCode==0 and (.run.submissionUnconfirmed|not)'
fi
call deactivate </dev/null
call activate </dev/null
configure
# A stop acknowledgment without inactive proof must also remain protected.
touch "$manager/stop-no-change"
call start <"$TMPDIR/start"
check 'active unit after stop acknowledgment escaped protection' '.ok==false and .run.submissionUnconfirmed and .run.exitCode==0'
jq '{runId:.run.id}' "$TMPDIR/result" >"$TMPDIR/run"
cleanup_unit=$(jq -r .run.unitName "$TMPDIR/result")
sed -i 's/InvocationID=.*/InvocationID=22222222222222222222222222222222/' "$manager/$cleanup_unit"
call refresh <"$TMPDIR/run"
check 'cleanup identity mismatch erased main exit protection' '.ok==false and .error.code=="RUN_IDENTITY_LOST" and .run.submissionUnconfirmed and .run.exitCode==0 and .run.processState=="succeeded"'
sed -i 's/InvocationID=.*/InvocationID=11111111111111111111111111111111/' "$manager/$cleanup_unit"
touch "$manager/unavailable"
call refresh <"$TMPDIR/run"
check 'unavailable cleanup observation erased main exit protection' '.ok==false and .error.code=="OBSERVATION_UNAVAILABLE" and .run.submissionUnconfirmed and .run.exitCode==0'
rm "$manager/unavailable"
rm "$manager/stop-no-change"
call refresh <"$TMPDIR/run"
check 'refresh failed to resolve later proven cleanup' '.ok and (.run.submissionUnconfirmed|not) and .run.exitCode==0'
# A timed-out release still retains main exit evidence and blocks replacement.
touch "$manager/stop-delays"
jq '.requestId="req-00000000-0000-4000-8000-000000000004"' "$TMPDIR/start" | call start
check 'timed-out release escaped protection' '.ok==false and .run.submissionUnconfirmed and .run.exitCode==0'
jq '{runId:.run.id}' "$TMPDIR/result" >"$TMPDIR/run"
rm "$manager/stop-delays"
call stop <"$TMPDIR/run"
check 'stop failed to resolve timed-out cleanup' '.ok and (.run.submissionUnconfirmed|not)'
# Keep a proved current invocation for independent journal encoding assertions.
echo running >"$manager/mode"
jq '.requestId="req-00000000-0000-4000-8000-000000000005"' "$TMPDIR/start" | call start
unit=$(jq -r .run.unitName "$TMPDIR/result")
jq '{runId:.run.id}' "$TMPDIR/result" >"$TMPDIR/run"
jq -cn --arg u "$unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:("x"*5000)}' >"$manager/journal"
call logs <"$TMPDIR/run"
check 'journal full fields were silently omitted' '.ok and (.output|length)==5000 and (.truncated|not)'
if ! tr '\0' '\n' <"$manager/journalctl.argv" | rg -qx -- '--all'; then
  echo 'journal argv omitted --all' >&2
  failures=$((failures + 1))
fi
jq -cn --arg u "$unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:[65,0,27,91,51,49,109,231,149,140,27,91,48,109,66]}' >"$manager/journal"
call logs <"$TMPDIR/run"
check 'journal byte array lost UTF-8/plaintext message' '.ok and .output=="A界B" and (.truncated|not)'
jq -cn --arg u "$unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:[65,194,162,240,159,152,128,66]}' >"$manager/journal"
call logs <"$TMPDIR/run"
check 'journal two/four-byte UTF-8 decoding changed text' '.ok and .output=="A¢😀B" and (.truncated|not)'

for value in null '[300]' '[[65]]' '{"wrong":"field"}' '[192,175]' '[237,160,128]' '[244,144,128,128]' '[240,159]'; do
  jq -cn --arg u "$unit" --argjson value "$value" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:$value}' >"$manager/journal"
  call logs <"$TMPDIR/run"
  check 'omitted journal message falsely claimed complete output' '.ok and .truncated'
done
jq -cn --arg u "$unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:[65,255,66]}' >"$manager/journal"
call logs <"$TMPDIR/run"
check 'invalid UTF-8 bytes disappeared without loss accounting' '.ok and .truncated and (.output|contains("A")) and (.output|contains("B"))'
jq -cn --arg u "$unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:"partial"}' >"$manager/journal"
touch "$manager/journal-fails" "$manager/journal-malformed"
call logs <"$TMPDIR/run"
check 'journal parse/transport loss falsely claimed complete output' '.ok and .truncated and (.output|contains("partial"))'
rm "$manager/journal-fails" "$manager/journal-malformed"
# Positive absence cannot resolve an accepted intent with no terminal evidence.
call stop <"$TMPDIR/run"
echo reject >"$manager/mode"
jq '.requestId="req-00000000-0000-4000-8000-000000000006"' "$TMPDIR/start" | call start
jq '{runId:.run.id}' "$TMPDIR/result" >"$TMPDIR/run"
call refresh <"$TMPDIR/run"
check 'absent unconfirmed submission was mistaken for completed cleanup' '.ok==false and .run.submissionUnconfirmed and .run.processState=="unconfirmed" and .run.exitCode==null'
call deactivate </dev/null
check 'deactivate forgot an absent unconfirmed submission' '.ok==false and .run.submissionUnconfirmed'
((failures == 0))
