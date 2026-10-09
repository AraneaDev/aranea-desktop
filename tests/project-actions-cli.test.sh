#!/usr/bin/env bash
# Public routes preserve receipts and bounded outcomes through real stores/Git.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
cli="$repo_root/scripts/aranea"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo" "$ARANEA_TEST_SANDBOX/manager"
for tool in systemd-run systemctl journalctl curl xdg-open; do ln -s "$repo_root/tests/fixtures/project-actions-manager.sh" "$ARANEA_TEST_SANDBOX/bin/$tool"; done
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
manager="$ARANEA_TEST_SANDBOX/manager"
# A failed assertion must still let detached sandbox helpers finish before removal.
wait_observer_workers() {
  for _ in {1..160}; do
    if ! compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null; then return; fi
    sleep .1
  done
}
sandbox_on_exit wait_observer_workers
git init -q "$ARANEA_TEST_SANDBOX/repo"
jq -cn --arg p "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
checkout=$(jq -r '.state.projects[0].lastCheckoutId' "$TMPDIR/project")
# Run an actual public command and retain every schema1 event.
call() { "$cli" projects "$@" --json >"$TMPDIR/result"; }
# Assert exit mapping and final stable error without skipping the real boundary.
refuse() {
  local status=0 want=$1 code=$2
  shift 2
  call "$@" 2>"$TMPDIR/expected-error" || status=$?
  [[ $status == "$want" ]]
  jq -es --arg c "$code" '.[-1].schema==1 and (.[-1].code // "")==$c' "$TMPDIR/result" >/dev/null
}
# Configuration/listing are available without a manager and never execute.
touch "$manager/unavailable"
# Literal metacharacters must survive configuration unchanged.
# shellcheck disable=SC2016
printf '%s\n' '{"name":"Checks","kind":"command","argv":["printf","$HOME %i ; literal",""],"cwdRelative":".","previewUrl":null}' >"$TMPDIR/draft"
call actions configure "$project" --json-input <"$TMPDIR/draft"
jq -es '.[-1].status=="observed" and .[-1].data.state.definitions[0].argv[2]==""' "$TMPDIR/result" >/dev/null
action=$(jq -rs '.[-1].data.state.definitions[0].id' "$TMPDIR/result")
# Revision wrappers retain stale drafts and refuse before any dispatch.
jq --arg id "$action" '{definition:(.+{id:$id,name:"Edited checks"}),expectedRevision:0}' "$TMPDIR/draft" >"$TMPDIR/wrapper"
refuse 1 ACTION_CONFLICT actions configure "$project" --json-input <"$TMPDIR/wrapper"
jq '.expectedRevision=1' "$TMPDIR/wrapper" | call actions configure "$project" --json-input
jq -es '.[-1].data.state.definitions[0].revision==2' "$TMPDIR/result" >/dev/null
call actions list "$project"
jq -es '.[-1].data.definitions|length==1' "$TMPDIR/result" >/dev/null
[[ ! -e "$manager/launches" ]]
refuse 2 INVALID_USAGE actions run "$project" "$action" --checkout "$checkout" --checkout "$checkout"
refuse 2 INVALID_USAGE actions list "$project" --json
refuse 2 INVALID_USAGE actions run "$project" "$action" --definition-revision 0
refuse 1 EXECUTION_UNAVAILABLE actions run "$project" "$action"
rm "$manager/unavailable"
refuse 1 ACTION_CONFLICT actions run "$project" "$action" --definition-revision 1
[[ ! -e "$manager/launches" ]]
req='req-00000000-0000-4000-8000-000000000031'
call actions run "$project" "$action" --request-id "$req" --definition-revision 2
jq -es 'all(.[];.schema==1) and any(.[];.status=="accepted" and .data.runId!=null) and .[-1].status=="observed" and .[-1].data.run.processState=="running" and .[-1].data.run.checkoutId!=null' "$TMPDIR/result" >/dev/null
run=$(jq -rs '.[-1].data.run.id' "$TMPDIR/result")
# Accepted snapshot remains revision 2 even after revision 3 is saved.
jq --arg id "$action" '{definition:(.+{id:$id,name:"Edited after acceptance"})}' "$TMPDIR/draft" | call actions configure "$project" --json-input
call actions run "$project" "$action" --request-id "$req" --definition-revision 2
jq -es '.[-1].data.run.definitionRevision==2 and .[-1].data.state.definitions[0].revision==3' "$TMPDIR/result" >/dev/null
refuse 1 REQUEST_CONFLICT actions run "$project" a-00000000-0000-4000-8000-000000000099 --request-id "$req"
[[ $(wc -l <"$manager/launches") == 1 ]]
call runs list --project "$project"
jq -es --arg r "$run" '.[-1].data.runs[0].id==$r' "$TMPDIR/result" >/dev/null
call runs inspect "$run"
jq -es --arg r "$run" '.[-1].data.runId==$r' "$TMPDIR/result" >/dev/null
refuse 1 RUN_PROTECTED actions remove "$project" "$action"
call runs stop "$run"
echo failed >"$manager/mode"
refuse 1 '' actions run "$project" "$action"
jq -es '.[-1].status=="failed" and .[-1].data.run.exitCode==7' "$TMPDIR/result" >/dev/null
# A successful main command with unresolved cleanup remains partial/protected.
echo fast >"$manager/mode"
touch "$manager/stop-fails"
refuse 1 STOP_UNCONFIRMED actions run "$project" "$action"
jq -es '.[-1].status=="partial" and .[-1].data.run.processState=="succeeded" and .[-1].data.run.submissionUnconfirmed' "$TMPDIR/result" >/dev/null
partial=$(jq -rs '.[-1].data.run.id' "$TMPDIR/result")
rm "$manager/stop-fails"
call runs stop "$partial"
# Retained-ID transport uncertainty is partial, never a second submission.
echo accepted-error >"$manager/mode"
refuse 1 SUBMISSION_UNCONFIRMED actions run "$project" "$action"
uncertain=$(jq -rs '.[-1].data.run.id' "$TMPDIR/result")
[[ $uncertain == r-* ]]
call runs refresh "$uncertain"
call runs stop "$uncertain"
# Accepted receipt is emitted while the detached backend is still observing cleanup.
echo fast >"$manager/mode"
echo 1.6 >"$manager/show-delay"
touch "$manager/stop-delays"
started=$SECONDS
call actions run "$project" "$action" --request-id req-00000000-0000-4000-8000-000000000038 2>"$TMPDIR/observer-error" &
observer=$!
accepted=false
for _ in {1..100}; do
  if jq -es 'any(.[];.status=="accepted") and all(.[];.event!="completed")' "$TMPDIR/result" >/dev/null 2>&1; then
    accepted=true
    break
  fi
  sleep .05
done
[[ $accepted == true ]] || {
  echo 'acceptance was withheld until native observation finished' >&2
  exit 1
}
status=0
wait "$observer" || status=$?
[[ $status == 1 ]]
((SECONDS - started <= 12))
jq -es '.[-1].status=="partial" and .[-1].code=="OBSERVATION_TIMEOUT" and .[-1].data.runId!=null' "$TMPDIR/result" >/dev/null
slow=$(jq -rs '.[-1].data.runId' "$TMPDIR/result")
# CLI closure leaves the worker and its protected intent intact until completion.
for _ in {1..100}; do
  if ! compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null; then break; fi
  sleep .1
done
if compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null; then
  echo "detached observer artifacts were not released" >&2
  exit 1
fi
jq -e --arg r "$slow" 'any(.runs[];.id==$r and .submissionUnconfirmed and .processState=="succeeded")' "$ARANEA_STATE_ROOT/project-actions.json" >/dev/null
rm "$manager/show-delay" "$manager/stop-delays"
call runs stop "$slow"
# Explicit observer closure releases only its lease, never the accepted backend.
echo 1.6 >"$manager/show-delay"
touch "$manager/stop-delays"
"$cli" projects actions run "$project" "$action" --json >"$TMPDIR/cancel-events" 2>"$TMPDIR/cancel-error" &
observer=$!
accepted=false
for _ in {1..100}; do
  if jq -es 'any(.[];.status=="accepted")' "$TMPDIR/cancel-events" >/dev/null 2>&1; then
    accepted=true
    break
  fi
  sleep .05
done
[[ $accepted == true ]]
kill -TERM "$observer"
status=0
wait "$observer" || status=$?
[[ $status == 1 ]] || {
  echo "observer close exit $status did not preserve a partial result" >&2
  exit 1
}
jq -es '.[-1].status=="partial" and .[-1].code=="OBSERVER_CANCELLED" and .[-1].data.runId!=null' "$TMPDIR/cancel-events" >/dev/null
cancelled=$(jq -rs '.[-1].data.runId' "$TMPDIR/cancel-events")
for _ in {1..160}; do
  if ! compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null; then break; fi
  sleep .1
done
if compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null; then
  echo "detached observer artifacts were not released" >&2
  exit 1
fi
jq -e --arg r "$cancelled" 'any(.runs[];.id==$r and .submissionUnconfirmed and .processState=="succeeded")' "$ARANEA_STATE_ROOT/project-actions.json" >/dev/null
rm "$manager/show-delay" "$manager/stop-delays"
call runs stop "$cancelled"
# Services return observed running and independent preview evidence without waiting.
echo running >"$manager/mode"
touch "$manager/unreachable"
jq '.kind="service" | .name="Preview" | .previewUrl="http://127.0.0.1:8181/"' "$TMPDIR/draft" | call actions configure "$project" --json-input
service=$(jq -rs '.[-1].data.state.definitions[-1].id' "$TMPDIR/result")
started=$SECONDS
call actions run "$project" "$service"
((SECONDS - started <= 10))
jq -es '.[-1].status=="observed" and .[-1].data.run.processState=="running" and .[-1].data.run.readiness=="unreachable"' "$TMPDIR/result" >/dev/null
service_run=$(jq -rs '.[-1].data.run.id' "$TMPDIR/result")
call runs open-preview "$service_run"
[[ $(wc -l <"$manager/opened") == 1 ]]
service_unit=$(jq -rs '.[-1].data.run.unitName' "$TMPDIR/result")
jq -cn --arg u "$service_unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:"<b>plain</b>"}' >"$manager/journal"
call runs logs "$service_run"
jq -es '.[-1].data.output=="<b>plain</b>" and .[-1].data.truncated==false' "$TMPDIR/result" >/dev/null
call runs restart "$service_run" --request-id req-00000000-0000-4000-8000-000000000039
restarted=$(jq -rs '.[-1].data.run.id' "$TMPDIR/result")
[[ $restarted != "$service_run" ]]
call runs stop "$restarted"
call actions remove "$project" "$service"
# Bounded stdin refuses malformed/multiple/large values without payload changes.
cp "$ARANEA_STATE_ROOT/project-actions.json" "$TMPDIR/state-before-invalid"
printf '%s\n' '{} {}' | refuse 1 INVALID_REQUEST actions configure "$project" --json-input
head -c 1048577 /dev/zero | tr '\0' x >"$TMPDIR/too-large"
refuse 1 INPUT_TOO_LARGE actions configure "$project" --json-input <"$TMPDIR/too-large"
cmp "$TMPDIR/state-before-invalid" "$ARANEA_STATE_ROOT/project-actions.json"
# Large state is streamed through capabilities and public envelopes, not argv.
python3 - "$ARANEA_STATE_ROOT/project-actions.json" <<'PY'
import json, sys
p=sys.argv[1]; s=json.load(open(p)); base=s['definitions'][0]
for i in range(1,45):
 d=dict(base,id=f'a-00000000-0000-4000-8000-{i:012d}',name=f'Large {i}',argv=['printf']+['x'*1000]*15)
 s['definitions'].append(d)
json.dump(s,open(p,'w'))
PY
call actions list "$project"
jq -es '.[-1].data.definitions|length==45' "$TMPDIR/result" >/dev/null
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
"$cli" capabilities --json >"$TMPDIR/caps"
jq -es '.[-1].data as $d | any($d.operations[];.name=="projects.actions.run" and .arguments["definition-revision"].minimum==1) and $d.projectActions.bounds.stateBytes==16777216 and $d.availability.projectActions.userManager==true' "$TMPDIR/caps" >/dev/null
[[ $(cat "$ARANEA_TEST_SANDBOX/guard.log") == "omarchy-shell aranea.projects snapshot" ]]

# A public configure stalled on stdin retains its old ingress generation.
mkfifo "$TMPDIR/cli-ingress"
exec {ingress}<>"$TMPDIR/cli-ingress"
(
  exec {ingress}>&-
  exec "$cli" projects actions configure "$project" --json-input --json <"$TMPDIR/cli-ingress" >"$TMPDIR/stale-events" 2>"$TMPDIR/stale-error"
) &
stale_pid=$!
ready=false
for _ in {1..100}; do
  # /proc child PIDs are intentionally split to locate the blocked head reader.
  # shellcheck disable=SC2013
  for child in $(cat "/proc/$stale_pid/task/$stale_pid/children" 2>/dev/null); do
    if [[ $(cat "/proc/$child/comm" 2>/dev/null) == head ]]; then
      ready=true
      break
    fi
  done
  [[ $ready == false ]] || break
  sleep .01
done
[[ $ready == true ]]
"$repo_root/scripts/aranea-project-actions" deactivate </dev/null >"$TMPDIR/deactivate"
"$repo_root/scripts/aranea-project-actions" activate </dev/null >"$TMPDIR/activate"
cat "$TMPDIR/draft" >&"$ingress"
exec {ingress}>&-
if wait "$stale_pid"; then
  echo 'stale public stdin regained authority' >&2
  exit 1
fi
jq -es '.[-1].code=="ACTION_REMOVED"' "$TMPDIR/stale-events" >/dev/null
[[ ! -e "$ARANEA_STATE_ROOT/project-actions.json" ]]
