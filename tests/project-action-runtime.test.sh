#!/usr/bin/env bash
# Real runtime/store/Git contracts with stateful, strictly sandboxed effects.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
backend="$repo_root/scripts/aranea-project-actions"
[[ -x $backend ]] || {
  echo 'Missing executable shared action runtime' >&2
  exit 1
}
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo" "$ARANEA_TEST_SANDBOX/manager"
for tool in systemd-run systemctl journalctl curl xdg-open; do ln -s "$repo_root/tests/fixtures/project-actions-manager.sh" "$ARANEA_TEST_SANDBOX/bin/$tool"; done
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
manager="$ARANEA_TEST_SANDBOX/manager"
git init -q "$ARANEA_TEST_SANDBOX/repo"
jq -cn --arg p "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
checkout=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/project")
# Run one real boundary call, retaining its envelope for assertions.
call() {
  local status=0
  "$backend" "$1" >"$TMPDIR/result" || status=$?
  if ((status != 0)); then jq -c '{ok,error,runId:.run.id,processState:.run.processState}' "$TMPDIR/result" >&2; fi
  return "$status"
}
# Failure must always retain an actionable structured envelope.
refuse() {
  local op=$1 code=$2
  if call "$op"; then
    echo "unexpected success $op $code" >&2
    exit 1
  fi
  jq -e --arg c "$code" '.ok==false and .error.code==$c' "$TMPDIR/result" >/dev/null
}
jq -cn --arg p "$project" '{projectId:$p,definition:{name:"Run",kind:"command",argv:["printf","literal $HOME %i ; $(touch NEVER)",""],cwdRelative:".",timeoutSeconds:33,previewUrl:null}}' >"$TMPDIR/configure"
call configure <"$TMPDIR/configure"
action=$(jq -r '.state.definitions[0].id' "$TMPDIR/result")
jq -cn --arg p "$project" --arg c "$checkout" --arg a "$action" '{projectId:$p,checkoutId:$c,actionId:$a,requestId:"req-00000000-0000-4000-8000-000000000001"}' >"$TMPDIR/start"
call start <"$TMPDIR/start"
jq -e '.ok and .run.processState=="running" and .run.readiness=="unknown" and (.run.submissionUnconfirmed|not)' "$TMPDIR/result" >/dev/null
run=$(jq -r .run.id "$TMPDIR/result")
unit=$(jq -r .run.unitName "$TMPDIR/result")
jq -cn --arg r "$run" '{runId:$r}' >"$TMPDIR/run"
call start <"$TMPDIR/start"
jq -e '.reused' "$TMPDIR/result" >/dev/null
[[ $(wc -l <"$manager/launches") == 1 ]]
# A displayed definition revision fences fresh UI submissions, but not receipt replay.
jq --arg a "$action" '.definition.id=$a | .definition.name="Edited"' "$TMPDIR/configure" | call configure
jq '.expectedDefinitionRevision=1 | .requestId="req-00000000-0000-4000-8000-000000000025"' "$TMPDIR/start" | refuse start ACTION_CONFLICT
jq '.expectedDefinitionRevision=1' "$TMPDIR/start" | call start
jq -e '.reused and .run.definitionRevision==1' "$TMPDIR/result" >/dev/null
jq '.expectedDefinitionRevision=2 | .requestId="req-00000000-0000-4000-8000-000000000026"' "$TMPDIR/start" | call start
jq -e '.reused and .run.definitionRevision==1' "$TMPDIR/result" >/dev/null

# Real parser must refuse a replaced invocation before stop, journal or HTTP.
sed -i 's/InvocationID=.*/InvocationID=22222222222222222222222222222222/' "$manager/$unit"
refuse stop RUN_IDENTITY_LOST <"$TMPDIR/run"
[[ ! -e "$manager/stops" ]]
refuse logs RUN_IDENTITY_LOST <"$TMPDIR/run"
[[ ! -e "$manager/journalctl.argv" ]]
sed -i 's/InvocationID=.*/InvocationID=11111111111111111111111111111111/' "$manager/$unit"
call stop <"$TMPDIR/run"
jq -e '.run.processState=="stopped" and .run.stopRequested' "$TMPDIR/result" >/dev/null
# Fast commands retain the real exit result before releasing the unit.
echo fast >"$manager/mode"
touch "$manager/check-release"
jq '.requestId="req-00000000-0000-4000-8000-000000000002"' "$TMPDIR/start" | call start
jq -e '.run.processState=="succeeded" and .run.exitCode==0' "$TMPDIR/result" >/dev/null
rm "$manager/check-release"
echo failed >"$manager/mode"
jq '.requestId="req-00000000-0000-4000-8000-000000000003"' "$TMPDIR/start" | call start
jq -e '.run.processState=="failed" and .run.exitCode==7' "$TMPDIR/result" >/dev/null
# No live manager makes launch unavailable before reserving an intent.
touch "$manager/unavailable"
jq '.requestId="req-00000000-0000-4000-8000-000000000004"' "$TMPDIR/start" | refuse start EXECUTION_UNAVAILABLE
[[ $(wc -l <"$manager/launches") == 3 ]]
rm "$manager/unavailable"
# Exact launch argv are data, with fixed unit semantics and bounded commands.
python3 - "$manager/systemd-run.argv" <<'PY'
import sys
args = open(sys.argv[1], 'rb').read().split(b'\0')[:-1]
assert b'--expand-environment=no' in args
assert b'--property=KillMode=control-group' in args
assert b'--property=RuntimeMaxSec=33s' in args
assert b'--collect' not in args
assert args[-2:] == [b'literal $HOME %i ; $(touch NEVER)', b'']
PY
# A running service and loopback reachability have independent states.
echo running >"$manager/mode"
jq '.definition.kind="service" | .definition.timeoutSeconds=null | .definition.previewUrl="http://127.0.0.1:8181/?q=x"' "$TMPDIR/configure" | call configure
service=$(jq -r '.state.definitions[-1].id' "$TMPDIR/result")
jq --arg a "$service" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000005"' "$TMPDIR/start" >"$TMPDIR/service-start"
touch "$manager/unreachable"
call start <"$TMPDIR/service-start"
jq -e '.run.processState=="running" and .run.readiness=="unreachable"' "$TMPDIR/result" >/dev/null
service_run=$(jq -r .run.id "$TMPDIR/result")
service_unit=$(jq -r .run.unitName "$TMPDIR/result")
jq -cn --arg r "$service_run" '{runId:$r}' >"$TMPDIR/service-run"
rm "$manager/unreachable"
call refresh <"$TMPDIR/service-run"
jq -e '.run.processState=="running" and .run.readiness=="reachable"' "$TMPDIR/result" >/dev/null
call open-preview <"$TMPDIR/service-run"
[[ $(wc -l <"$manager/opened") == 1 ]]
python3 - "$manager/curl.argv" "$manager/systemd-run.argv" <<'PY'
import sys
args = open(sys.argv[1], 'rb').read().split(b'\0')[:-1]
assert args[0] == b'-q'
assert b'--noproxy' in args and b'*' in args
assert b'--max-time' in args and b'1' in args
assert b'-L' not in args and b'--location' not in args
assert not any(a.startswith(b'--property=RuntimeMaxSec') for a in open(sys.argv[2], 'rb').read().split(b'\0'))
PY
# Journal content is exact-invocation plaintext with hard output bounds.
jq -cn --arg u "$service_unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"22222222222222222222222222222222",MESSAGE:"UNRELATED"},{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:"\u001b[31m<literal>\u001b[0m\u0007"}' >"$manager/journal"
call logs <"$TMPDIR/service-run"
jq -e '.output=="<literal>" and .truncated==false' "$TMPDIR/result" >/dev/null
jq -cn --arg u "$service_unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:("x"*300000)}' >"$manager/journal"
call logs <"$TMPDIR/service-run"
jq -e '.truncated and (.output|utf8bytelength)<=262144' "$TMPDIR/result" >/dev/null
# Proof mismatch must refuse every effect, even with matching name and invocation.
for field in Transient Description Id; do
  cp "$manager/$service_unit" "$TMPDIR/proof"
  sed -i "s/^$field=.*/$field=spoof/" "$manager/$service_unit"
  refuse open-preview RUN_IDENTITY_LOST <"$TMPDIR/service-run"
  refuse logs RUN_IDENTITY_LOST <"$TMPDIR/service-run"
  cp "$TMPDIR/proof" "$manager/$service_unit"
done
# Stop uncertainty refuses restart and preserves the original protected identity.
touch "$manager/stop-fails"
launches=$(wc -l <"$manager/launches")
jq '.requestId="req-00000000-0000-4000-8000-000000000006"' "$TMPDIR/service-run" | refuse restart STOP_UNCONFIRMED
[[ $(wc -l <"$manager/launches") == "$launches" ]]
rm "$manager/stop-fails"
call stop <"$TMPDIR/service-run"
# Late manager acceptance remains protected through drain failure and reconnect.
echo late >"$manager/mode"
jq '.requestId="req-00000000-0000-4000-8000-000000000007"' "$TMPDIR/start" >"$TMPDIR/late-start"
call start <"$TMPDIR/late-start"
jq -e '.run.processState=="unconfirmed" and .run.submissionUnconfirmed' "$TMPDIR/result" >/dev/null
late_run=$(jq -r .run.id "$TMPDIR/result")
jq -cn --arg r "$late_run" '{runId:$r}' >"$TMPDIR/late-run"
# Hide a possible arrival to force incomplete teardown without forgetting intent.
touch "$manager/unavailable"
refuse deactivate OBSERVATION_UNAVAILABLE </dev/null
[[ -f "$ARANEA_STATE_ROOT/project-actions.json" ]]
[[ $(cat "$ARANEA_STATE_ROOT/project-actions.json.lock") == draining:* ]]
refuse activate RUN_PROTECTED </dev/null
refuse start ACTION_REMOVED <"$TMPDIR/late-start"
rm "$manager/unavailable"
sleep 1.2
call refresh <"$TMPDIR/late-run"
jq -e '.run.processState=="running" and (.run.submissionUnconfirmed|not)' "$TMPDIR/result" >/dev/null
call deactivate </dev/null
[[ ! -e "$ARANEA_STATE_ROOT/project-actions.json" ]]
[[ $(cat "$ARANEA_STATE_ROOT/project-actions.json.lock") == removed:* ]]
call activate </dev/null
# Recreate definitions after removal, then race two distinct request IDs.
call configure <"$TMPDIR/configure"
action=$(jq -r '.state.definitions[0].id' "$TMPDIR/result")
jq --arg a "$action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000011"' "$TMPDIR/start" >"$TMPDIR/fresh-start"
echo running >"$manager/mode"
launches=$(wc -l <"$manager/launches")
"$backend" start <"$TMPDIR/fresh-start" >"$TMPDIR/concurrent-a" &
pid_a=$!
jq '.requestId="req-00000000-0000-4000-8000-000000000012"' "$TMPDIR/fresh-start" | "$backend" start >"$TMPDIR/concurrent-b" &
pid_b=$!
wait "$pid_a" "$pid_b" || {
  jq -s 'map({ok,reused,runId:.run.id,error})' "$TMPDIR/concurrent-a" "$TMPDIR/concurrent-b" >&2
  exit 1
}
jq -se 'all(.[];.ok) and (.[0].run.id==.[1].run.id) and ([.[]|select(.reused==false)]|length)==1' "$TMPDIR/concurrent-a" "$TMPDIR/concurrent-b" >/dev/null || {
  jq -s 'map({ok,reused,runId:.run.id,error})' "$TMPDIR/concurrent-a" "$TMPDIR/concurrent-b" >&2
  exit 1
}
[[ $(wc -l <"$manager/launches") == $((launches + 1)) ]]
new_run=$(jq -r .run.id "$TMPDIR/concurrent-a")
jq -cn --arg r "$new_run" '{runId:$r}' >"$TMPDIR/new-run"
# Fresh requests coalesce protected runs even while their manager is unavailable.
touch "$manager/unavailable"
jq '.requestId="req-00000000-0000-4000-8000-000000000013"' "$TMPDIR/fresh-start" | call start
jq -e '.reused and .run.processState=="running"' "$TMPDIR/result" >/dev/null
rm "$manager/unavailable"
# Different exact worktrees never coalesce, and a changed default cannot alter replay.
git -C "$ARANEA_TEST_SANDBOX/repo" -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm initial
git -C "$ARANEA_TEST_SANDBOX/repo" worktree add -q -b second "$ARANEA_TEST_SANDBOX/worktree"
jq -cn --arg p "$ARANEA_TEST_SANDBOX/worktree" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project-2"
checkout2=$(jq -r --arg p "$ARANEA_TEST_SANDBOX/worktree" '.state.projects[].checkouts[]|select(.path==$p)|.id' "$TMPDIR/project-2")
jq --arg c "$checkout2" '.checkoutId=$c | .requestId="req-00000000-0000-4000-8000-000000000014"' "$TMPDIR/fresh-start" | call start
jq -e --arg c "$checkout2" --arg r "$new_run" '.run.checkoutId==$c and .run.id!=$r and .reused==false' "$TMPDIR/result" >/dev/null
jq 'del(.checkoutId)' "$TMPDIR/fresh-start" | call start
jq -e --arg c "$checkout" --arg r "$new_run" '.reused and .run.checkoutId==$c and .run.id==$r' "$TMPDIR/result" >/dev/null
# Canonical cwd escapes and explicit executable escapes are refused before dispatch.
ln -s "$TMPDIR" "$ARANEA_TEST_SANDBOX/repo/outside"
jq '.definition.cwdRelative="outside"' "$TMPDIR/configure" | call configure
outside_action=$(jq -r '.state.definitions[-1].id' "$TMPDIR/result")
jq --arg a "$outside_action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000015"' "$TMPDIR/fresh-start" | refuse start CHECKOUT_INVALID
# Missing binaries are valid definitions but cannot dispatch a new intent.
jq '.definition.argv=["aranea-nonexistent-fixture-binary"]' "$TMPDIR/configure" | call configure
missing_action=$(jq -r '.state.definitions[-1].id' "$TMPDIR/result")
jq --arg a "$missing_action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000016"' "$TMPDIR/fresh-start" | refuse start EXECUTABLE_MISSING
# Safe PATH excludes checkout descendants and bootstrap never runs their helpers.
mkdir "$ARANEA_TEST_SANDBOX/repo/bin"
for tool in bash printf jq systemctl systemd-run; do
  # shellcheck disable=SC2016
  printf '#!/usr/bin/bash\necho SHADOW >>"$ARANEA_TEST_SANDBOX/shadow"\nexit 89\n' >"$ARANEA_TEST_SANDBOX/repo/bin/$tool"
  chmod +x "$ARANEA_TEST_SANDBOX/repo/bin/$tool"
done
jq '.definition.argv=["printf","safe"]' "$TMPDIR/configure" | call configure
safe_action=$(jq -r '.state.definitions[-1].id' "$TMPDIR/result")
jq --arg a "$safe_action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000017"' "$TMPDIR/fresh-start" >"$TMPDIR/safe-start"
PATH="$ARANEA_TEST_SANDBOX/repo/bin:.:$PATH" "$backend" start <"$TMPDIR/safe-start" >"$TMPDIR/result"
[[ ! -e "$ARANEA_TEST_SANDBOX/shadow" ]]
python3 - "$manager/systemd-run.argv" "$ARANEA_TEST_SANDBOX/repo" <<'PY'
import sys
args = open(sys.argv[1], 'rb').read().split(b'\0')[:-1]
p = next(a for a in args if a.startswith(b'--setenv=PATH='))
assert sys.argv[2].encode() not in p
assert args[-2] == b'/usr/bin/printf'
PY
# Observation resolves helpers outside the whole checkout, including sibling bins.
mkdir "$ARANEA_TEST_SANDBOX/repo/nested"
jq '.definition.cwdRelative="nested"' "$TMPDIR/configure" | call configure
nested_action=$(jq -r '.state.definitions[-1].id' "$TMPDIR/result")
jq --arg a "$nested_action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000027"' "$TMPDIR/fresh-start" | call start
jq '{runId:.run.id}' "$TMPDIR/result" >"$TMPDIR/nested-run"
PATH="$ARANEA_TEST_SANDBOX/repo/bin:$PATH" "$backend" stop <"$TMPDIR/nested-run" >"$TMPDIR/result"
jq -e '.run.processState=="stopped"' "$TMPDIR/result" >/dev/null
[[ ! -e "$ARANEA_TEST_SANDBOX/shadow" ]]
# Saved ./ scripts are resolved explicitly and may remain inside the exact checkout.
printf '#!/usr/bin/env bash\nexit 0\n' >"$ARANEA_TEST_SANDBOX/repo/approved"
chmod +x "$ARANEA_TEST_SANDBOX/repo/approved"
jq '.definition.argv=["./approved"]' "$TMPDIR/configure" | call configure
relative_action=$(jq -r '.state.definitions[-1].id' "$TMPDIR/result")
jq --arg a "$relative_action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000018"' "$TMPDIR/fresh-start" | call start
jq -e '.run.processState=="running"' "$TMPDIR/result" >/dev/null
# Current boot is part of proof, even if all manager fields match.
cp "$ARANEA_STATE_ROOT/project-actions.json" "$TMPDIR/boot-state"
jq --arg r "$new_run" '(.runs[]|select(.id==$r)|.bootId)="00000000-0000-0000-0000-000000000000"' "$TMPDIR/boot-state" >"$ARANEA_STATE_ROOT/project-actions.json"
refuse stop RUN_IDENTITY_LOST <"$TMPDIR/new-run"
cp "$TMPDIR/boot-state" "$ARANEA_STATE_ROOT/project-actions.json"
# Historical runs remain inspectable and stoppable after registry removal.
cp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/projects-kept"
jq '.projects=[]' "$TMPDIR/projects-kept" >"$ARANEA_STATE_ROOT/projects.json"
call inspect <"$TMPDIR/new-run"
call stop <"$TMPDIR/new-run"
call start <"$TMPDIR/fresh-start"
jq -e '.reused' "$TMPDIR/result" >/dev/null
cp "$TMPDIR/projects-kept" "$ARANEA_STATE_ROOT/projects.json"
# Pending stdin captures its old generation before teardown and reinstall.
mkfifo "$TMPDIR/ingress"
exec {ingress}<>"$TMPDIR/ingress"
(
  exec {ingress}>&-
  exec "$backend" start <"$TMPDIR/ingress" >"$TMPDIR/stale-ingress"
) &
stale_pid=$!
ready=false
for _ in {1..100}; do
  # /proc lists space-separated numeric child PIDs, intentionally split here.
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
lock_inode=$(stat -c %i "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock")
call deactivate </dev/null
call activate </dev/null
cat "$TMPDIR/fresh-start" >&"$ingress"
exec {ingress}>&-
wait "$stale_pid" && {
  echo 'stale stdin unexpectedly accepted' >&2
  exit 1
}
jq -e '.error.code=="ACTION_REMOVED"' "$TMPDIR/stale-ingress" >/dev/null
[[ $(stat -c %i "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock") == "$lock_inode" ]]
# Dispatch lock leaf/ancestor symlinks refuse without touching their targets.
mv "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock" "$TMPDIR/dispatch-kept"
ln -s "$TMPDIR/dispatch-kept" "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock"
refuse snapshot UNSAFE_STATE_PATH </dev/null
rm "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock"
mv "$TMPDIR/dispatch-kept" "$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock"

# An accepted unit discovered after transport failure must be pinned before log reads.
call configure <"$TMPDIR/configure"
action=$(jq -r '.state.definitions[0].id' "$TMPDIR/result")
echo accepted-error >"$manager/mode"
jq --arg a "$action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000021"' "$TMPDIR/start" | call start
jq -e '.run.submissionUnconfirmed and .run.invocationId==null' "$TMPDIR/result" >/dev/null
adopt_run=$(jq -r .run.id "$TMPDIR/result")
adopt_unit=$(jq -r .run.unitName "$TMPDIR/result")
jq -cn --arg r "$adopt_run" '{runId:$r}' >"$TMPDIR/adopt-run"
jq -cn --arg u "$adopt_unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:"retained"}' >"$manager/journal"
call logs <"$TMPDIR/adopt-run"
jq -e '.run.invocationId=="11111111111111111111111111111111" and .output=="retained"' "$TMPDIR/result" >/dev/null
call stop <"$TMPDIR/adopt-run"
# Command runtime expiration carries manager evidence rather than a success claim.
echo timeout >"$manager/mode"
jq --arg a "$action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000022"' "$TMPDIR/start" | call start
jq -e '.run.processState=="failed" and .run.error.code=="TIMEOUT" and .run.exitSignal==15' "$TMPDIR/result" >/dev/null

# Low-level lifecycle calls must obey dispatch ordering as well as state protection.
exec {held_dispatch}<>"$ARANEA_STATE_ROOT/project-actions.json.dispatch.lock"
flock -x "$held_dispatch"
if "$repo_root/scripts/aranea-project-action-store" activate >"$TMPDIR/direct-lifecycle"; then
  echo 'low-level lifecycle bypassed dispatch authority' >&2
  exit 1
fi
jq -e '.error.code=="ACTION_LOCK_FAILED"' "$TMPDIR/direct-lifecycle" >/dev/null
exec {held_dispatch}>&-
# Project-scoped snapshots retain receipts for their retained runs.
jq -cn --arg p "$project" '{projectId:$p}' | call snapshot
failures=0
jq -e '.state as $s | all($s.runs[];.id as $r | any($s.requests[];.runId==$r))' "$TMPDIR/result" >/dev/null || {
  echo 'scoped snapshot lost retained receipts' >&2
  failures=$((failures + 1))
}
# The byte limit must also hold when truncation splits a multibyte codepoint.
jq -cn --arg u "$adopt_unit" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",MESSAGE:("界"*100000)}' >"$manager/journal"
call logs <"$TMPDIR/adopt-run"
jq -e '.truncated and (.output|utf8bytelength)<=262144' "$TMPDIR/result" >/dev/null || {
  echo 'journal exceeded UTF-8 byte bound' >&2
  failures=$((failures + 1))
}
((failures == 0))

# An observation held at the manager boundary cannot overwrite a newer store revision.
echo running >"$manager/mode"
jq --arg a "$action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000023"' "$TMPDIR/start" | call start
stale_run=$(jq -r .run.id "$TMPDIR/result")
jq -cn --arg r "$stale_run" '{runId:$r}' >"$TMPDIR/stale-run"
touch "$manager/show-hold"
"$backend" refresh <"$TMPDIR/stale-run" >"$TMPDIR/stale-observation" &
observer=$!
for _ in {1..100}; do
  [[ ! -e $manager/show-entered ]] || break
  sleep .01
done
[[ -e $manager/show-entered ]]
jq '{action:"configure",args:.}' "$TMPDIR/configure" | "$repo_root/scripts/aranea-project-action-store" mutate >"$TMPDIR/new-revision"
rm "$manager/show-hold"
if wait "$observer"; then
  echo 'stale observation overwrote newer state' >&2
  exit 1
fi
jq -e '.error.code=="ACTION_CONFLICT"' "$TMPDIR/stale-observation" >/dev/null
call inspect <"$TMPDIR/stale-run"
jq -e '.run.processState=="running"' "$TMPDIR/result" >/dev/null
call stop <"$TMPDIR/stale-run"
# A stop held on stdin cannot acquire fresh drain authority after retirement.
jq --arg a "$action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000024"' "$TMPDIR/start" | call start
retired_run=$(jq -r .run.id "$TMPDIR/result")
jq -cn --arg r "$retired_run" '{runId:$r}' >"$TMPDIR/retired-run"
mkfifo "$TMPDIR/stop-ingress"
exec {ingress}<>"$TMPDIR/stop-ingress"
(
  exec {ingress}>&-
  exec "$backend" stop <"$TMPDIR/stop-ingress" >"$TMPDIR/stale-stop"
) &
stale_pid=$!
ready=false
for _ in {1..100}; do
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
touch "$manager/unavailable"
refuse deactivate OBSERVATION_UNAVAILABLE </dev/null
cat "$TMPDIR/retired-run" >&"$ingress"
exec {ingress}>&-
if wait "$stale_pid"; then
  echo 'retired stop acquired drain authority' >&2
  exit 1
fi
jq -e '.error.code=="ACTION_REMOVED"' "$TMPDIR/stale-stop" >/dev/null
rm "$manager/unavailable"
call stop <"$TMPDIR/retired-run"
call deactivate </dev/null
call activate </dev/null

# Persisted terminal proof authorizes exact historical logs after unit release/GC.
call configure <"$TMPDIR/configure"
action=$(jq -r '.state.definitions[0].id' "$TMPDIR/result")
echo fast >"$manager/mode"
touch "$manager/gc-on-release" "$manager/check-release"
jq --arg a "$action" '.actionId=$a | .requestId="req-00000000-0000-4000-8000-000000000028"' "$TMPDIR/start" | call start
jq -e '.run.processState=="succeeded"' "$TMPDIR/result" >/dev/null
history_run=$(jq -r .run.id "$TMPDIR/result")
history_unit=$(jq -r .run.unitName "$TMPDIR/result")
history_boot=$(jq -r '.run.bootId|gsub("-";"")' "$TMPDIR/result")
[[ ! -e $manager/$history_unit ]]
rm "$manager/gc-on-release" "$manager/check-release"
jq -cn --arg r "$history_run" '{runId:$r}' >"$TMPDIR/history-run"
jq -cn --arg u "$history_unit" --arg b "$history_boot" '{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",_BOOT_ID:$b,MESSAGE:"historical"},{_SYSTEMD_USER_UNIT:$u,_SYSTEMD_INVOCATION_ID:"11111111111111111111111111111111",_BOOT_ID:"00000000000000000000000000000000",MESSAGE:"OTHER BOOT"}' >"$manager/journal"
call logs <"$TMPDIR/history-run"
jq -e '.output=="historical"' "$TMPDIR/result" >/dev/null
# If the unit name was reused, mismatching current evidence still forbids reads.
cp "$manager/pending" "$manager/$history_unit"
sed -i 's/InvocationID=.*/InvocationID=22222222222222222222222222222222/' "$manager/$history_unit"
refuse logs RUN_IDENTITY_LOST <"$TMPDIR/history-run"
