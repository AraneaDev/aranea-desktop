#!/usr/bin/env bash
# Durable action contracts against the real store and inert, sandboxed Git repos.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
store="$repo_root/scripts/aranea-project-action-store"
mkdir -p "$ARANEA_TEST_SANDBOX/repo"
git init -q "$ARANEA_TEST_SANDBOX/repo"
jq -cn --arg p "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
checkout=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/project")
# Submit JSON from stdin, keeping large states off operating-system argv.
mutate() { "$store" mutate >"$TMPDIR/result"; }
# Assert a structured failure while preserving the prior state bytes.
refuse() {
  local code=$1 before
  before=$(sha256sum "$ARANEA_STATE_ROOT/project-actions.json")
  if mutate; then
    echo "unexpected success: $code" >&2
    exit 1
  fi
  jq -e --arg code "$code" '.ok == false and .error.code == $code' "$TMPDIR/result" >/dev/null
  [[ $(sha256sum "$ARANEA_STATE_ROOT/project-actions.json") == "$before" ]]
}
"$store" snapshot | jq -e '.ok and .state == {schemaVersion:1,revision:0,definitions:[],runs:[],requests:[]}' >/dev/null
jq -cn --arg p "$project" '{action:"configure",args:{projectId:$p,definition:{name:"Run checks",kind:"command",argv:["printf","literal $HOME ; $(touch NEVER)",""],cwdRelative:".",timeoutSeconds:300,previewUrl:null}}}' >"$TMPDIR/configure"
mutate <"$TMPDIR/configure"
jq -e '.ok and (.state.definitions|length==1) and .state.definitions[0].argv[1]=="literal $HOME ; $(touch NEVER)" and .state.definitions[0].argv[2]==""' "$TMPDIR/result" >/dev/null
[[ ! -e NEVER ]]
action=$(jq -r '.state.definitions[0].id' "$TMPDIR/result")
jq '.expectedRevision=0' "$TMPDIR/configure" | refuse ACTION_CONFLICT
for change in '.args.extra=true' '.args.definition.extra=true' '.args.definition.argv=[]' '.args.definition.argv=[""]' '.args.definition.argv=["echo","\n"]' '.args.definition.argv=["foo/bar"]' '.args.definition.cwdRelative="../x"' '.args.definition.cwdRelative="/tmp"' '.args.definition.timeoutSeconds=0' '.args.definition.previewUrl="http://127.0.0.1:8080"' '.args.definition.name=""' '.args.definition.id="a-no"'; do
  jq "$change" "$TMPDIR/configure" | refuse INVALID_REQUEST
done
jq '.args.projectId="p-00000000-0000-0000-0000-000000000000"' "$TMPDIR/configure" | refuse PROJECT_NOT_FOUND
jq --arg id "$action" '.args.definition.id=$id | .args.definition.name="Updated"' "$TMPDIR/configure" | mutate
jq -e '.state.definitions[0].revision==2 and (.state.definitions|length)==1' "$TMPDIR/result" >/dev/null
hash=$(jq -Sc '.state.definitions[0] | del(.createdAt,.updatedAt)' "$TMPDIR/result" | sha256sum | cut -d' ' -f1)
jq -cn --arg p "$project" --arg c "$checkout" --arg a "$action" --arg h "$hash" --arg cwd "$ARANEA_TEST_SANDBOX/repo" '{action:"reserve",args:{projectId:$p,checkoutId:$c,actionId:$a,requestId:"req-00000000-0000-0000-0000-000000000001",cwd:$cwd,definitionRevision:2,definitionHash:$h,bootId:"00000000-0000-0000-0000-000000000000"}}' >"$TMPDIR/reserve"
mutate <"$TMPDIR/reserve"
run=$(jq -r .run.id "$TMPDIR/result")
jq -e '.ok and .reused==false and .run.processState=="pending" and .run.submissionUnconfirmed and .run.definitionSnapshot.name=="Updated"' "$TMPDIR/result" >/dev/null
cp "$TMPDIR/result" "$TMPDIR/accepted"
mutate <"$TMPDIR/reserve"
jq -e --arg run "$run" '.reused and .run.id==$run and (.state.runs|length)==1' "$TMPDIR/result" >/dev/null
jq '.args.checkoutId="c-00000000-0000-0000-0000-000000000000"' "$TMPDIR/reserve" | refuse REQUEST_CONFLICT
jq '.args.requestId="req-00000000-0000-0000-0000-000000000002"' "$TMPDIR/reserve" | mutate
jq -e --arg run "$run" '.reused and .run.id==$run and (.state.requests|length)==2' "$TMPDIR/result" >/dev/null
jq -cn --arg p "$project" --arg a "$action" '{action:"remove",args:{projectId:$p,actionId:$a}}' | refuse RUN_PROTECTED
if "$store" deactivate >"$TMPDIR/result"; then exit 1; fi
jq -e '.error.code=="RUN_PROTECTED"' "$TMPDIR/result" >/dev/null
jq --arg id "$action" '.args.definition.id=$id | .args.definition.name="After acceptance"' "$TMPDIR/configure" | mutate
jq -e '.state.runs[0].definitionSnapshot.name=="Updated" and .state.definitions[0].revision==3' "$TMPDIR/result" >/dev/null
# Replay survives an edited definition and unavailable checkout.
mv "$ARANEA_TEST_SANDBOX/repo" "$ARANEA_TEST_SANDBOX/away"
mutate <"$TMPDIR/reserve"
jq -e '.reused' "$TMPDIR/result" >/dev/null
mv "$ARANEA_TEST_SANDBOX/away" "$ARANEA_TEST_SANDBOX/repo"
revision=$(jq .state.revision "$TMPDIR/result")
jq -cn --arg run "$run" --argjson rev "$revision" '{action:"observe",expectedRevision:$rev,args:{runId:$run,expectedInvocationId:null,patch:{invocationId:"11111111111111111111111111111111",state:"observing",outcome:"observed",processState:"running",submissionUnconfirmed:false}}}' >"$TMPDIR/observe"
mutate <"$TMPDIR/observe"
refuse ACTION_CONFLICT <"$TMPDIR/observe"
revision=$(jq .state.revision "$TMPDIR/result")
jq --argjson rev "$revision" '.expectedRevision=$rev' "$TMPDIR/observe" | refuse RUN_IDENTITY_LOST
jq --argjson rev "$revision" '.expectedRevision=$rev | .args.patch.cwd="/tmp"' "$TMPDIR/observe" | refuse INVALID_REQUEST
jq -cn --arg run "$run" '{action:"request-stop",args:{runId:$run}}' | mutate
jq -e '.run.stopRequested and .run.processState=="running"' "$TMPDIR/result" >/dev/null
revision=$(jq .state.revision "$TMPDIR/result")
jq --argjson rev "$revision" '.expectedRevision=$rev | .args.expectedInvocationId="11111111111111111111111111111111" | .args.patch={state:"completed",outcome:"observed",processState:"stopped",submissionUnconfirmed:false,exitCode:0}' "$TMPDIR/observe" | mutate
jq -e '.run.processState=="stopped"' "$TMPDIR/result" >/dev/null
# Terminal observations cannot be resurrected by a later callback.
revision=$(jq .state.revision "$TMPDIR/result")
jq --argjson rev "$revision" '.expectedRevision=$rev | .args.expectedInvocationId="11111111111111111111111111111111"' "$TMPDIR/observe" | refuse RUN_TERMINAL
# Parallel edits serialize; no write gets lost.
for n in {1..6}; do jq --arg n "$n" '.args.definition.name=$n' "$TMPDIR/configure" | "$store" mutate >"$TMPDIR/parallel-$n" & done
wait
for n in {1..6}; do jq -e '.ok' "$TMPDIR/parallel-$n" >/dev/null; done
"$store" snapshot | jq -e '(.state.definitions|length)==7' >/dev/null
# Strict state validation preserves corrupt bytes, and unsafe paths are refused.
cp "$ARANEA_STATE_ROOT/project-actions.json" "$TMPDIR/good"
printf 'broken' >"$ARANEA_STATE_ROOT/project-actions.json"
if "$store" snapshot >"$TMPDIR/result"; then exit 1; fi
jq -e '.error.code=="ACTION_STATE_INVALID"' "$TMPDIR/result" >/dev/null
[[ $(cat "$ARANEA_STATE_ROOT/project-actions.json") == broken ]]
cp "$TMPDIR/good" "$ARANEA_STATE_ROOT/project-actions.json"
mv "$ARANEA_STATE_ROOT/project-actions.json" "$TMPDIR/payload"
ln -s "$TMPDIR/payload" "$ARANEA_STATE_ROOT/project-actions.json"
if "$store" snapshot >"$TMPDIR/result"; then exit 1; fi
jq -e '.error.code=="UNSAFE_STATE_PATH"' "$TMPDIR/result" >/dev/null
rm "$ARANEA_STATE_ROOT/project-actions.json"
mv "$TMPDIR/payload" "$ARANEA_STATE_ROOT/project-actions.json"
# Input above exec's argv limit stays on stdin; state remains readable above it.
jq '.args.definition.argv=(["printf"] + [range(15)|"x"*1024])' "$TMPDIR/configure" | mutate
jq '.args.definition.argv=(["printf"] + [range(17)|"x"*1024])' "$TMPDIR/configure" | refuse INVALID_REQUEST
jq -cn '{action:"prune",args:{},padding:("x"*1048576)}' | refuse INPUT_TOO_LARGE
# Service URL and executable/cwd lexical constraints are strict at Save.
for url in 'http://localhost:8080' 'http://127.0.0.1' 'http://127.0.0.1:0' 'http://127.0.0.1:65536' 'http://user@127.0.0.1:80' 'http://127.0.0.1:80/#fragment'; do
  jq --arg url "$url" '.args.definition.kind="service" | .args.definition.timeoutSeconds=null | .args.definition.previewUrl=$url' "$TMPDIR/configure" | refuse INVALID_REQUEST
done
jq '.args.definition.kind="service" | .args.definition.timeoutSeconds=null | .args.definition.previewUrl="http://[::1]:8080/path?q=x"' "$TMPDIR/configure" | mutate
jq '.args.definition | del(.timeoutSeconds) | {action:"configure",args:{projectId:$p,definition:.}}' --arg p "$project" "$TMPDIR/configure" | mutate
jq -e '.state.definitions[-1].timeoutSeconds==300' "$TMPDIR/result" >/dev/null
# New acceptance checks the current definition, exact Git group and canonical cwd.
hash=$(jq -Sc --arg a "$action" '.state.definitions[]|select(.id==$a)|del(.createdAt,.updatedAt)' "$TMPDIR/result" | sha256sum | cut -d' ' -f1)
jq --arg h "$hash" '.args.definitionHash=$h | .args.definitionRevision=3 | .args.requestId="req-00000000-0000-0000-0000-000000000003"' "$TMPDIR/reserve" >"$TMPDIR/fresh"
jq '.args.definitionHash=("0"*64)' "$TMPDIR/fresh" | refuse ACTION_CONFLICT
jq '.args.cwd="/tmp"' "$TMPDIR/fresh" | refuse CHECKOUT_INVALID
jq '.args.checkoutId="c-00000000-0000-0000-0000-000000000000"' "$TMPDIR/fresh" | refuse CHECKOUT_INVALID
mv "$ARANEA_TEST_SANDBOX/repo/.git" "$ARANEA_TEST_SANDBOX/git-away"
git init -q "$ARANEA_TEST_SANDBOX/replacement"
cp -a "$ARANEA_TEST_SANDBOX/replacement/.git" "$ARANEA_TEST_SANDBOX/repo/.git"
# A replacement with the same canonical commonDir is intentionally indistinguishable
# under the registry contract; a symlink to a different commonDir is not.
rm -rf "$ARANEA_TEST_SANDBOX/repo/.git"
ln -s "$ARANEA_TEST_SANDBOX/replacement/.git" "$ARANEA_TEST_SANDBOX/repo/.git"
refuse CHECKOUT_INVALID <"$TMPDIR/fresh"
rm "$ARANEA_TEST_SANDBOX/repo/.git"
mv "$ARANEA_TEST_SANDBOX/git-away" "$ARANEA_TEST_SANDBOX/repo/.git"
# Seed valid large histories to exercise bounds without hundreds of child stores.
cp "$ARANEA_STATE_ROOT/project-actions.json" "$TMPDIR/before-bounds"
jq --arg p "$project" '
  def uid($n): "00000000-0000-0000-0000-"+(("000000000000"+($n|tostring))[-12:]);
  .definitions[0] as $d | .definitions=[range(200) as $n | $d+{id:("a-"+uid($n)),projectId:(if $n<50 then $p else "p-"+uid(($n/50|floor)) end),argv:(["printf"]+[range(15)|"x"*1024])}]
' "$TMPDIR/before-bounds" >"$ARANEA_STATE_ROOT/project-actions.json"
[[ $(stat -c %s "$ARANEA_STATE_ROOT/project-actions.json") -gt 131072 ]]
"$store" snapshot | jq -e '.ok and (.state.definitions|length)==200' >/dev/null
refuse CAPACITY_EXCEEDED <"$TMPDIR/configure"
jq '.definitions=.definitions[:50]' "$ARANEA_STATE_ROOT/project-actions.json" >"$TMPDIR/bounded"
cp "$TMPDIR/bounded" "$ARANEA_STATE_ROOT/project-actions.json"
refuse CAPACITY_EXCEEDED <"$TMPDIR/configure"
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# Fifty pending intents protect their slots even with completed operation state.
jq --slurpfile accepted "$TMPDIR/accepted" '
  def uid($n): "00000000-0000-0000-0000-"+(("000000000000"+($n|tostring))[-12:]);
  $accepted[0].run as $run | .runs=[range(50) as $n|$run+{id:("r-"+uid($n)),requestId:("req-"+uid($n)),checkoutId:("c-"+uid($n)),unitName:("aranea-project-"+uid($n)+".service"),state:"completed",outcome:"partial",processState:"unconfirmed"}]
  | .requests=[.runs[]|{requestId,runId:.id,hash:("0"*64),createdAt}]
' "$TMPDIR/before-bounds" >"$ARANEA_STATE_ROOT/project-actions.json"
jq '.args.requestId="req-11111111-1111-1111-1111-111111111111"' "$TMPDIR/fresh" | refuse CAPACITY_EXCEEDED
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# All receipt aliases of protected runs are pinned; a full table refuses safely.
jq --slurpfile accepted "$TMPDIR/accepted" '
  def uid($n): "00000000-0000-0000-0000-"+(("000000000000"+($n|tostring))[-12:]);
  .runs=[$accepted[0].run] | .runs[0] as $run | .requests=[$accepted[0].state.requests[0]]+[range(2;513) as $n|{requestId:("req-"+uid($n)),runId:$run.id,hash:("0"*64),createdAt:$run.createdAt}]
' "$TMPDIR/before-bounds" >"$ARANEA_STATE_ROOT/project-actions.json"
jq '.args.requestId="req-11111111-1111-1111-1111-111111111111"' "$TMPDIR/fresh" | refuse CAPACITY_EXCEEDED
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# Evict a terminal alias when exactly 512 primary/protected receipts need slots.
jq --slurpfile accepted "$TMPDIR/accepted" '
  def uid($n): "00000000-0000-0000-0000-"+(("000000000000"+($n|tostring))[-12:]);
  .runs[0] as $done | $accepted[0].run as $live
  | .runs=[$live,($done+{id:"r-ffffffff-ffff-ffff-ffff-ffffffffffff",requestId:"req-ffffffff-ffff-ffff-ffff-ffffffffffff",unitName:"aranea-project-ffffffff-ffff-ffff-ffff-ffffffffffff.service"})]
  | .requests=[$accepted[0].state.requests[0]]+[range(2;511) as $n|{requestId:("req-"+uid($n)),runId:$live.id,hash:("0"*64),createdAt:$live.createdAt}]
    +[{requestId:"req-ffffffff-ffff-ffff-ffff-ffffffffffff",runId:.runs[1].id,hash:("0"*64),createdAt:$done.createdAt},{requestId:"req-eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",runId:.runs[1].id,hash:("0"*64),createdAt:$done.createdAt}]
' "$TMPDIR/before-bounds" >"$ARANEA_STATE_ROOT/project-actions.json"
if ! jq '.args.requestId="req-11111111-1111-1111-1111-111111111111"' "$TMPDIR/fresh" | mutate; then
  jq .error "$TMPDIR/result" >&2
  exit 1
fi
jq -e '(.state.requests|length)==512 and all(.state.requests[];.requestId!="req-eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")' "$TMPDIR/result" >/dev/null
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# Pruning removes expired terminal history and its receipts, preserving intents.
jq --slurpfile accepted "$TMPDIR/accepted" '
  .runs[0].createdAt=1 | .runs[0].updatedAt=1 | .runs+=[$accepted[0].run|.id="r-11111111-1111-1111-1111-111111111111"|.requestId="req-11111111-1111-1111-1111-111111111111"|.unitName="aranea-project-11111111-1111-1111-1111-111111111111.service"]
  | .requests += [{requestId:.runs[1].requestId,runId:.runs[1].id,hash:("0"*64),createdAt:1}]
' "$TMPDIR/before-bounds" >"$ARANEA_STATE_ROOT/project-actions.json"
printf '%s\n' '{"action":"prune","args":{}}' | mutate
jq -e '(.state.runs|length)==1 and .state.runs[0].processState=="pending" and (.state.requests|length)==1' "$TMPDIR/result" >/dev/null
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# Keep the just-observed result even when prior timestamps are ahead of the clock.
jq --argjson horizon "$(($(date +%s) + 60))" --slurpfile accepted "$TMPDIR/accepted" '
  def uid($n): "00000000-0000-0000-0000-"+(("000000000000"+($n|tostring))[-12:]);
  .runs[0] as $done | .runs=[range(100) as $n|$done+{id:("r-"+uid($n)),requestId:("req-"+uid($n)),unitName:("aranea-project-"+uid($n)+".service"),updatedAt:$horizon }]
  | .runs += [$accepted[0].run|.id="r-ffffffff-ffff-ffff-ffff-ffffffffffff"|.requestId="req-ffffffff-ffff-ffff-ffff-ffffffffffff"|.unitName="aranea-project-ffffffff-ffff-ffff-ffff-ffffffffffff.service"]
  | .requests=[.runs[]|{requestId,runId:.id,hash:("0"*64),createdAt}]
' "$TMPDIR/before-bounds" >"$ARANEA_STATE_ROOT/project-actions.json"
revision=$(jq .revision "$ARANEA_STATE_ROOT/project-actions.json")
jq -cn --argjson rev "$revision" '{action:"observe",expectedRevision:$rev,args:{runId:"r-ffffffff-ffff-ffff-ffff-ffffffffffff",expectedInvocationId:null,patch:{state:"completed",outcome:"failed",processState:"failed",submissionUnconfirmed:false}}}' | mutate
jq -e '(.state.runs|length)==100 and (.state.requests|length)==100 and .run.processState=="failed"' "$TMPDIR/result" >/dev/null
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# Concurrent reservations all receive the same accepted run.
for n in {1..4}; do
  jq --arg req "req-22222222-2222-2222-2222-22222222222$n" '.args.requestId=$req' "$TMPDIR/fresh" | "$store" mutate >"$TMPDIR/start-$n" &
done
wait
jq -s -e 'all(.[];.ok) and ([.[].run.id]|unique|length)==1 and ([.[]|select(.reused==false)]|length)==1' "$TMPDIR"/start-* >/dev/null
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# Saving a shell command does not execute it, and absent executables are valid.
jq --arg marker "$TMPDIR/executed" '.args.definition.argv=["/usr/bin/sh","-c",("touch "+$marker)]' "$TMPDIR/configure" | mutate
[[ ! -e "$TMPDIR/executed" ]]
jq '.args.definition.argv=["aranea-missing-executable-for-test"]' "$TMPDIR/configure" | mutate
# A cwd symlink outside the registered checkout refuses at reserve.
ln -s "$TMPDIR" "$ARANEA_TEST_SANDBOX/repo/outside"
jq '.args.definition.cwdRelative="outside"' "$TMPDIR/configure" | mutate
new_action=$(jq -r '.state.definitions[-1].id' "$TMPDIR/result")
new_hash=$(jq -Sc '.state.definitions[-1]|del(.createdAt,.updatedAt)' "$TMPDIR/result" | sha256sum | cut -d' ' -f1)
jq --arg a "$new_action" --arg h "$new_hash" --arg cwd "$TMPDIR" '.args.actionId=$a | .args.definitionHash=$h | .args.definitionRevision=1 | .args.cwd=$cwd' "$TMPDIR/fresh" | refuse CHECKOUT_INVALID
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# Registry removal does not erase historical authority; only fresh starts fail.
cp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/registered"
jq -cn --arg p "$project" '{action:"remove",args:{projectId:$p}}' | "$repo_root/scripts/aranea-project-store" mutate >/dev/null
mutate <"$TMPDIR/reserve"
jq -e '.reused' "$TMPDIR/result" >/dev/null
refuse PROJECT_NOT_FOUND <"$TMPDIR/fresh"
cp "$TMPDIR/registered" "$ARANEA_STATE_ROOT/projects.json"
jq -cn --arg p "$project" --arg a "$action" '{action:"remove",args:{projectId:$p,actionId:$a}}' | mutate
jq -e --arg a "$action" 'all(.state.definitions[];.id!=$a) and .state.runs[0].actionId==$a' "$TMPDIR/result" >/dev/null
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
# A busy lock fails within its bounded wait instead of hanging a client.
exec {held_lock}<>"$ARANEA_STATE_ROOT/project-actions.json.lock"
flock -x "$held_lock"
if "$store" snapshot >"$TMPDIR/result"; then exit 1; fi
jq -e '.error.code=="ACTION_LOCK_FAILED"' "$TMPDIR/result" >/dev/null
flock -u "$held_lock"
exec {held_lock}>&-
# Corrupt schema and symlinked ancestors/locks cannot be normalized away.
jq '.runs[0].definitionSnapshot.extra=true' "$TMPDIR/before-bounds" >"$ARANEA_STATE_ROOT/project-actions.json"
if "$store" snapshot >"$TMPDIR/result"; then exit 1; fi
jq -e '.error.code=="ACTION_STATE_INVALID"' "$TMPDIR/result" >/dev/null
cp "$TMPDIR/before-bounds" "$ARANEA_STATE_ROOT/project-actions.json"
ln -s "$ARANEA_STATE_ROOT" "$ARANEA_TEST_SANDBOX/state-link"
if ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state-link" "$store" snapshot >"$TMPDIR/result"; then exit 1; fi
jq -e '.error.code=="UNSAFE_STATE_PATH"' "$TMPDIR/result" >/dev/null
mv "$ARANEA_STATE_ROOT/project-actions.json.lock" "$TMPDIR/lock"
ln -s "$TMPDIR/lock" "$ARANEA_STATE_ROOT/project-actions.json.lock"
if "$store" snapshot >"$TMPDIR/result"; then exit 1; fi
jq -e '.error.code=="UNSAFE_STATE_PATH"' "$TMPDIR/result" >/dev/null
rm "$ARANEA_STATE_ROOT/project-actions.json.lock"
mv "$TMPDIR/lock" "$ARANEA_STATE_ROOT/project-actions.json.lock"
[[ $(stat -c %a "$ARANEA_STATE_ROOT/project-actions.json") == 600 ]]
[[ $(stat -c %a "$ARANEA_STATE_ROOT/project-actions.json.lock") == 600 ]]
inode=$(stat -c %i "$ARANEA_STATE_ROOT/project-actions.json.lock")
source "$repo_root/scripts/lib/paths.sh"
source "$repo_root/scripts/lib/project-actions.sh"
old_generation=$(project_actions_generation)
"$store" deactivate | jq -e '.ok' >/dev/null
[[ $(stat -c %i "$ARANEA_STATE_ROOT/project-actions.json.lock") == "$inode" ]]
"$store" activate | jq -e '.ok' >/dev/null
if ARANEA_ACTION_GENERATION="$old_generation" "$store" snapshot >"$TMPDIR/result"; then exit 1; fi
jq -e '.error.code=="ACTION_REMOVED"' "$TMPDIR/result" >/dev/null
"$store" snapshot | jq -e '.ok and (.state.runs|length)==0' >/dev/null
printf 'project-action-store: real registry, definitions, immutable intents, replay, guards, safety and lifecycle passed\n'
