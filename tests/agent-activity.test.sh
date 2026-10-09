#!/usr/bin/env bash
# Exercise the real locked store; lifecycle, ordering and invalid bytes must survive.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
store="$repo_root/scripts/aranea-agent-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
registry="$ARANEA_STATE_ROOT/agent-activity.json"
checkout="$ARANEA_TEST_SANDBOX/checkout"
mkdir -p "$checkout/nested"
git init -q "$checkout"
# Submit one mutation to the actual store.
mutate() { jq -cn --arg action "$1" --argjson args "$2" '{action:$action,args:$args}' | "$store" mutate; }
# Create an explicitly registered empty producer epoch.
register() { mutate register '{"provider":"claude","providerSessionId":"session","producerEpoch":"epoch","tasks":[]}'; }
# Construct a contract event with a stable session and task identity.
event() {
  local payload="{}"
  if (($# > 3)); then payload=$4; fi
  jq -cn --arg id "$1" --argjson sequence "$2" --arg kind "$3" --argjson payload "$payload" '{schemaVersion:1,eventId:$id,provider:"claude",providerSessionId:"session",producerEpoch:"epoch",sequence:$sequence,taskId:"turn",kind:$kind,payload:$payload}'
}
# Submit one event through the public mutation boundary.
report() { mutate report "$(event "$@")"; }
# Supply a complete initial task snapshot.
begin() { report begin 1 snapshot "$(jq -cn --arg cwd "$checkout" '{cwd:$cwd,reportedState:"working",description:"First turn"}')"; }
# Register the disposable checkout through the real project registry.
seed_projects() { jq -cn --arg p "$checkout" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"; }
# Require both a structured error and unchanged prior bytes.
reject() {
  local action="$1" args="$2" code="$3"
  if [[ -e "$registry" ]]; then cp "$registry" "$TMPDIR/before"; else rm -f "$TMPDIR/before"; fi
  if mutate "$action" "$args" >"$TMPDIR/error"; then
    echo "unexpected accepted $action"
    return 1
  fi
  jq -e --arg code "$code" '.ok == false and .error.code == $code' "$TMPDIR/error" >/dev/null
  if [[ -e "$TMPDIR/before" ]]; then cmp "$registry" "$TMPDIR/before"; else [[ ! -e "$registry" ]]; fi
}
failures=0
# Reset disposable state and run each case with effective errexit isolation.
run_case() {
  rm -rf "$ARANEA_STATE_ROOT"
  set +e
  (
    set -e
    "$@"
  )
  local status=$?
  set -e
  if ((status == 0)); then printf 'PASS %s\n' "$1"; else
    printf 'FAIL %s\n' "$1"
    failures=$((failures + 1))
  fi
}
# Catch a missing executable or incompatible initial snapshot.
snapshot_contract() {
  [[ -x "$store" ]] || {
    echo 'Activity store is not implemented'
    return 1
  }
  "$store" snapshot | jq -e '.ok and .state.schemaVersion == 1 and .state.revision == 0' >/dev/null
}
# Catch duplicate revision changes, reused IDs and stale producer updates.
ordered_reports() {
  [[ -x "$store" ]] || {
    echo 'Ordered reports are not implemented'
    return 1
  }
  seed_projects
  register >/dev/null
  begin >"$TMPDIR/begin"
  jq -e '.state.revision == 2 and .state.tasks[0].reportedState == "working" and .state.tasks[0].association.status == "registered"' "$TMPDIR/begin" >/dev/null
  begin | jq -e '.state.revision == 2' >/dev/null
  reject report "$(event begin 1 failed '{"result":"different"}')" EVENT_ID_CONFLICT
  report third 3 ready-for-review '{"result":"Review changes"}' >/dev/null
  reject report "$(event second 2 working)" STALE_SEQUENCE
  reject report "$(event old 4 working | jq '.producerEpoch="old"')" EPOCH_MISMATCH
  reject register '{"provider":"claude","providerSessionId":"session","producerEpoch":"new"}' INVALID_REQUEST
  mutate register '{"provider":"claude","providerSessionId":"session","producerEpoch":"new","tasks":[]}' >/dev/null
  reject report "$(event late 5 finished)" EPOCH_MISMATCH
}
# Catch unrelated events clearing blockers or inventing successful verification.
blockers_diagnostics_and_verification() {
  register >/dev/null
  begin >/dev/null
  report a 2 needs-input '{"blockerId":"a","question":"Allow A?"}' >/dev/null
  report b 3 needs-input '{"blockerId":"b","question":"Allow B?"}' >/dev/null
  report diagnostic 4 diagnostic '{"summary":"tool failed"}' | jq -e '.state.tasks[0] | .reportedState == "needs-input" and (.blockers|length == 2)' >/dev/null
  report heartbeat 5 heartbeat | jq -e '.state.tasks[0].reportedState == "needs-input"' >/dev/null
  report resolve 6 blocker-resolved '{"blockerId":"a"}' | jq -e '.state.tasks[0] | .reportedState == "needs-input" and .blockers[0].blockerId == "b"' >/dev/null
  report unrelated 7 blocker-resolved '{"blockerId":"other"}' | jq -e '.state.tasks[0].reportedState == "needs-input"' >/dev/null
  report resolveb 8 blocker-resolved '{"blockerId":"b"}' | jq -e '.state.tasks[0].reportedState == "working"' >/dev/null
  report finish 9 finished '{"result":"Done"}' | jq -e '.state.tasks[0] | .reportedState == "finished" and .verification.status == "unknown"' >/dev/null
  report verify 10 verification '{"status":"reported-fail","summary":"Check failed","commands":["tests/run"]}' >/dev/null
  report end 11 disconnected | jq -e '.state.tasks[0] | .reportedState == "finished" and .verification.status == "reported-fail"' >/dev/null
  report pending 12 snapshot "$(jq -cn --arg cwd "$checkout" '{cwd:$cwd,reportedState:"needs-input",question:"A direct question"}')" >/dev/null
  report unmatched 13 blocker-resolved '{"blockerId":"not-present"}' | jq -e '.state.tasks[0].reportedState == "needs-input" and .state.tasks[0].question == "A direct question"' >/dev/null
}
# Catch invalid, unknown, oversize or controlled text reaching durable state.
invalid_inputs_preserve_bytes() {
  register >/dev/null
  begin >/dev/null
  for input in '{}' '[]' '{"action":"unknown","args":{}}' '{"action":"prune","args":{},"extra":true}'; do
    cp "$registry" "$TMPDIR/before"
    if printf '%s' "$input" | "$store" mutate >"$TMPDIR/error"; then return 1; fi
    jq -e '.ok == false' "$TMPDIR/error" >/dev/null
    cmp "$registry" "$TMPDIR/before"
  done
  reject report "$(event bad 2 working '{"command":"sh"}')" INVALID_REQUEST
  reject report "$(event $'bad\n' 2 working)" INVALID_REQUEST
  reject report "$(event bad 2 failed "$(jq -cn '{result:("a"*4097)}')")" INVALID_REQUEST
  cp "$registry" "$TMPDIR/before"
  if jq -cn '{action:"prune",args:{},padding:("a"*1048577)}' | "$store" mutate >"$TMPDIR/error"; then return 1; fi
  jq -e '.error.code == "INPUT_TOO_LARGE"' "$TMPDIR/error" >/dev/null
  cmp "$registry" "$TMPDIR/before"
}
# Catch automatic reset of malformed or unsupported state.
corrupt_state_is_preserved() {
  mkdir -p "$ARANEA_STATE_ROOT"
  for raw in '{broken' '{"schemaVersion":2,"revision":0,"sessions":[],"tasks":[]}' '{"schemaVersion":1,"revision":0,"sessions":[{}],"tasks":[]}'; do
    printf '%s' "$raw" >"$registry"
    cp "$registry" "$TMPDIR/before"
    if "$store" snapshot >"$TMPDIR/error"; then return 1; fi
    jq -e '.error.code == "ACTIVITY_INVALID" and .state == null' "$TMPDIR/error" >/dev/null
    cmp "$registry" "$TMPDIR/before"
  done
}
# Catch containing-directory association and hidden registry errors.
association_and_registry_errors() {
  seed_projects
  register >/dev/null
  begin >/dev/null
  report nested 2 snapshot "$(jq -cn --arg cwd "$checkout/nested" '{cwd:$cwd,reportedState:"working"}')" | jq -e '.state.tasks[0].association.status == "unassigned"' >/dev/null
  local p c
  p=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
  c=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/project")
  reject report "$(event mismatch 3 snapshot "$(jq -cn --arg cwd "$checkout/nested" --arg p "$p" --arg c "$c" '{cwd:$cwd,projectId:$p,checkoutId:$c,reportedState:"working"}')")" ASSOCIATION_MISMATCH
  report root 3 snapshot "$(jq -cn --arg cwd "$checkout" '{cwd:$cwd,reportedState:"working"}')" >/dev/null
  jq -cn --arg p "$p" '{action:"remove",args:{projectId:$p}}' | "$repo_root/scripts/aranea-project-store" mutate >/dev/null
  "$store" snapshot | jq -e '.state.tasks[0].association.status == "unavailable"' >/dev/null
  printf '{broken' >"$ARANEA_STATE_ROOT/projects.json"
  if "$store" snapshot >"$TMPDIR/error"; then return 1; fi
  jq -e '.error.code == "REGISTRY_INVALID"' "$TMPDIR/error" >/dev/null
}
# Catch lost updates, ignored revisions and implicit producer registration.
concurrency_conflict_and_no_implicit_session() {
  "$store" snapshot >/dev/null
  reject report "$(event missing 1 working)" SESSION_NOT_FOUND
  register >"$TMPDIR/register"
  if printf '{"action":"prune","args":{},"expectedRevision":0}' | "$store" mutate >"$TMPDIR/error"; then return 1; fi
  jq -e '.error.code == "ACTIVITY_CONFLICT"' "$TMPDIR/error" >/dev/null
  mutate register '{"provider":"codex","providerSessionId":"other","producerEpoch":"other","tasks":[]}' >"$TMPDIR/one" &
  local one=$!
  begin >"$TMPDIR/two" &
  local two=$!
  wait "$one"
  wait "$two"
  "$store" snapshot | jq -e '.state.revision == 3 and (.state.sessions|length == 2) and (.state.tasks|length == 1)' >/dev/null
}
# Catch read-time rewrites, live dismissal and symlink target writes.
freshness_dismissal_and_symlinks() {
  register >/dev/null
  begin >/dev/null
  reject dismiss '{"taskId":"turn"}' TASK_LIVE
  jq '.sessions[0].connection.monotonic = 0 | .sessions[0].connection.receivedAt = 0' "$registry" >"$TMPDIR/stale"
  mv "$TMPDIR/stale" "$registry"
  cp "$registry" "$TMPDIR/before"
  "$store" snapshot | jq -e '.state.tasks[0] | .freshness == "connection-lost" and .reportedState == "working"' >/dev/null
  cmp "$registry" "$TMPDIR/before"
  mutate dismiss '{"taskId":"turn"}' | jq -e '.state.tasks|length == 0' >/dev/null
  mv "$registry" "$TMPDIR/target"
  ln -s "$TMPDIR/target" "$registry"
  cp "$TMPDIR/target" "$TMPDIR/before"
  if mutate prune '{}' >"$TMPDIR/error"; then return 1; fi
  jq -e '.error.code == "UNSAFE_STATE_PATH"' "$TMPDIR/error" >/dev/null
  cmp "$TMPDIR/target" "$TMPDIR/before"
}
# Catch unbounded task retention, silent live eviction, and loss of ordering after
# the honest duplicate replay window has expired. Fixtures start from real state.
capacity_retention_and_receipt_bounds() {
  register >/dev/null
  begin >/dev/null
  jq '.tasks[0] as $task | .tasks = [range(200) as $i | $task + {taskId:("live-"+($i|tostring))}]' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  reject report "$(event overflow 2 snapshot "$(jq -cn --arg cwd "$checkout" '{cwd:$cwd,reportedState:"working"}')")" CAPACITY_EXCEEDED
  jq '.tasks[0] as $task | .tasks = [range(501) as $i | $task + {taskId:("done-"+($i|tostring)),reportedState:"finished",lastReceivedAt:($task.lastReceivedAt - 501 + $i)}]' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  mutate prune '{}' | jq -e '(.state.tasks|length == 500) and all(.state.tasks[];.taskId != "done-0")' >/dev/null
  jq '.tasks |= map(.lastReceivedAt=0) | .sessions[0].connection.monotonic=0 | .sessions[0].connection.receivedAt=0' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  mutate prune '{}' | jq -e '.state.tasks == [] and .state.sessions == []' >/dev/null
  register >/dev/null
  begin >/dev/null
  jq '.sessions[0].receipts = [range(1;513) as $i | {eventId:("receipt-"+($i|tostring)),sequence:$i,hash:("a"*64)}] | .sessions[0].highWaterSequence=512' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  report latest 513 heartbeat | jq -e '(.state.sessions[0].receipts|length == 512) and .state.sessions[0].receipts[0].eventId == "receipt-2" and .state.sessions[0].highWaterSequence == 513' >/dev/null
  reject report "$(event receipt-1 1 working)" STALE_SEQUENCE
}
# Catch a diagnostic/history cap or nested validator that accepts injected fields.
nested_records_and_history_bounds() {
  register >/dev/null
  begin >/dev/null
  for update in '.sessions[0].provenance={pid:1}' '.sessions[0].provenance={pid:1,startTime:"1",bootId:"boot",ancestors:[],windowAddress:null,observedAt:0,executable:"/bin/false"}' '.sessions[0].provenance={pid:1,startTime:"1",bootId:"boot",ancestors:[],windowAddress:null,observedAt:0,executable:"/bin/false",commandHash:"invalid"}' '.tasks[0].verification.commands=[42]' '.tasks[0].blockers=[{blockerId:"a",question:"a"},{blockerId:"a",question:"b"}]' '.tasks[0].providerSessionId="missing"' '.sessions[0].nativeMetadata={currentTaskId:"missing",turns:[]}' '.tasks[0].association.cwd="/tmp/\u0000"'; do
    cp "$registry" "$TMPDIR/valid"
    jq "$update" "$registry" >"$TMPDIR/fixture"
    mv "$TMPDIR/fixture" "$registry"
    cp "$registry" "$TMPDIR/before"
    if "$store" snapshot >"$TMPDIR/error"; then
      echo "accepted corrupt nested record: $update"
      return 1
    fi
    jq -e '.error.code == "ACTIVITY_INVALID"' "$TMPDIR/error" >/dev/null
    cmp "$registry" "$TMPDIR/before"
    mv "$TMPDIR/valid" "$registry"
  done
  jq '.tasks[0].diagnostics=[range(20)|{summary:tostring,receivedAt:0}]' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  report diagnostic 2 diagnostic '{"summary":"new"}' | jq -e '.state.tasks[0].diagnostics | length == 20 and .[0].summary == "1" and .[-1].summary == "new"' >/dev/null
  jq '.tasks[0].blockers=[range(32)|{blockerId:tostring,question:"Question"}] | .tasks[0].reportedState="needs-input"' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  reject report "$(event extra 3 needs-input '{"blockerId":"extra","question":"Question"}')" CAPACITY_EXCEEDED
}
# Catch accepting native mappings when no provider adapter exists.
missing_native_adapter_is_structured() {
  copy_store_without_mapper
  register >/dev/null
  reject native '{"provider":"claude","payload":{},"caller":null}' ADAPTER_UNSUPPORTED
}
# Catch prompt/transcript retention and loss of duplicate receipts when checkout
# paths disappear after receipt; both are observable store boundary guarantees.
prompt_minimization_and_duplicate_replay() {
  source "$repo_root/scripts/lib/agent-activity.sh"
  local description
  description=$(printf '\n   \n First useful line\nPRIVATE TRANSCRIPT' | agent_activity_prompt_description)
  [[ "$description" == 'First useful line' ]]
  description=$(printf '%0200d\nPRIVATE' 0 | agent_activity_prompt_description)
  [[ ${#description} == 160 ]]
  register >/dev/null
  begin >/dev/null
  mv "$checkout" "$checkout-moved"
  begin >"$TMPDIR/duplicate"
  mv "$checkout-moved" "$checkout"
  jq -e '.ok and .state.revision == 2' "$TMPDIR/duplicate" >/dev/null
}
# Fresh attention may never be evicted; stale work must release live capacity.
attention_retention_respects_connection() {
  register >/dev/null
  begin >/dev/null
  report review 2 ready-for-review >/dev/null
  reject dismiss '{"taskId":"turn"}' TASK_LIVE
  report failed 3 failed >/dev/null
  reject dismiss '{"taskId":"turn"}' TASK_LIVE
  jq '.tasks[0] as $task | .tasks=[range(200) as $i|$task+{taskId:("attention-"+($i|tostring))}]' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  reject report "$(event extra 4 snapshot "$(jq -cn --arg cwd "$checkout" '{cwd:$cwd,reportedState:"ready-for-review"}')")" CAPACITY_EXCEEDED
  jq '.sessions[0].connection.monotonic=0 | .sessions[0].connection.receivedAt=0' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  mutate dismiss '{"taskId":"attention-0"}' | jq -e '(.state.tasks|length == 199) and all(.state.tasks[];.reportedState == "failed")' >/dev/null
  jq '.tasks |= map(.lastReceivedAt=0)' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  mutate prune '{}' | jq -e '.state.tasks == [] and .state.sessions == []' >/dev/null
}
# A sandbox provider mapper exercises the production serialization boundary.
copy_store_without_mapper() {
  local fixture="$TMPDIR/store-copy"
  mkdir -p "$fixture/lib"
  cp "$repo_root/scripts/aranea-agent-store" "$fixture/"
  cp "$repo_root/scripts/lib/"{paths.sh,agent-activity.sh,agent-activity.jq,projects-registry.jq} "$fixture/lib/"
  store="$fixture/aranea-agent-store"
}
# Catch split native allocation and duplicate metadata changes.
native_mapping_is_one_atomic_transaction() {
  copy_store_without_mapper
  cat >"$TMPDIR/store-copy/lib/agent-hooks.sh" <<'MAPPER'
agent_hooks_prepare_request() {
  jq -cn --argjson r "$1" --argjson s "$2" --argjson c "$3" '
    $r.args.payload as $p |
    if $p.kind == "start" then {action:"register",args:{provider:"claude",providerSessionId:"native",producerEpoch:"native-epoch",tasks:[]},nativeMetadata:{currentTaskId:null,turns:[]}}
    else $s.sessions[0] as $session |
      ([$session.nativeMetadata.turns[]|select(.nativeId == $p.id)][0].taskId // $c.generatedId) as $task |
      ([$session.receipts[]|select(.eventId == $p.id)][0].sequence // ($session.highWaterSequence+1)) as $seq |
      {action:"report",args:{schemaVersion:1,eventId:$p.id,provider:"claude",providerSessionId:"native",producerEpoch:"native-epoch",sequence:$seq,taskId:$task,kind:"snapshot",payload:{cwd:$p.cwd,reportedState:"working"}},
       nativeMetadata:{currentTaskId:$task,turns:([$session.nativeMetadata.turns[]|select(.nativeId != $p.id)]+[{nativeId:$p.id,taskId:$task}])}}
    end'
}
MAPPER
  mutate native '{"provider":"claude","payload":{"kind":"start"},"caller":null}' >/dev/null
  mutate native "$(jq -cn --arg cwd "$checkout" '{provider:"claude",payload:{id:"one",cwd:$cwd},caller:null}')" >"$TMPDIR/native-one" &
  local first=$!
  mutate native "$(jq -cn --arg cwd "$checkout" '{provider:"claude",payload:{id:"two",cwd:$cwd},caller:null}')" >"$TMPDIR/native-two" &
  local second=$!
  wait "$first"
  wait "$second"
  "$store" snapshot | jq -e '.state.revision == 3 and (.state.tasks|length == 2) and .state.sessions[0].highWaterSequence == 2 and (.state.sessions[0].nativeMetadata.turns|length == 2) and all(.state.tasks[];.source == "native")' >/dev/null
  cp "$registry" "$TMPDIR/before"
  local older
  older=$(jq -r '.sessions[0].receipts[0].eventId' "$registry")
  mutate native "$(jq -cn --arg id "$older" --arg cwd "$checkout" '{provider:"claude",payload:{id:$id,cwd:$cwd},caller:null}')" | jq -e '.state.revision == 3' >/dev/null
  cmp "$registry" "$TMPDIR/before"
}
# Catch failed atomic replacement corrupting bytes or an unbounded lock wait.
write_failure_lock_timeout_and_clock_regression() {
  register >/dev/null
  begin >/dev/null
  mkdir -p "$TMPDIR/failing-bin"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$TMPDIR/failing-bin/mv"
  chmod +x "$TMPDIR/failing-bin/mv"
  cp "$registry" "$TMPDIR/before"
  if PATH="$TMPDIR/failing-bin:$PATH" report finish 2 finished >"$TMPDIR/error"; then return 1; fi
  jq -e '.error.code == "ACTIVITY_WRITE_FAILED"' "$TMPDIR/error" >/dev/null
  cmp "$registry" "$TMPDIR/before"
  [[ $(find "$ARANEA_STATE_ROOT" -name 'agent-activity.json.*' ! -name '*.lock' | wc -l) == 0 ]]
  exec {test_lock_fd}>"$registry.lock"
  flock -x "$test_lock_fd"
  if "$store" snapshot >"$TMPDIR/error"; then return 1; fi
  jq -e '.error.code == "ACTIVITY_LOCK_FAILED"' "$TMPDIR/error" >/dev/null
  flock -u "$test_lock_fd"
  exec {test_lock_fd}>&-
  jq '.sessions[0].connection.receivedAt += 1000' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  "$store" snapshot | jq -e '.state.tasks[0].freshness == "connection-lost" and .state.tasks[0].reportedState == "working"' >/dev/null
  report heartbeat 2 heartbeat | jq -e '.state.tasks[0].reportedState == "working" and .state.tasks[0].freshness == "unconfirmed"' >/dev/null
  cp "$registry" "$TMPDIR/before"
  if printf '{"action":"prune","args":{}}\0' | "$store" mutate >"$TMPDIR/error"; then return 1; fi
  jq -e '.error.code == "INVALID_REQUEST"' "$TMPDIR/error" >/dev/null
  cmp "$registry" "$TMPDIR/before"
}
# Catch forgetting revoked epoch IDs and accepting a delayed old registration.
epoch_history_never_revives_a_retained_producer() {
  register >/dev/null
  jq '.sessions[0].retiredEpochs=[range(512)|"retired-"+tostring]' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  reject register '{"provider":"claude","providerSessionId":"session","producerEpoch":"next","tasks":[]}' CAPACITY_EXCEEDED
  reject register '{"provider":"claude","providerSessionId":"session","producerEpoch":"retired-0","tasks":[]}' EPOCH_MISMATCH
  "$store" snapshot | jq -e '.state.capabilities.maxRetiredEpochs == 512 and .state.capabilities.epochHistoryLifetime == "retained-session"' >/dev/null
  jq '.sessions[0].connection.monotonic=0 | .sessions[0].connection.receivedAt=0' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  mutate prune '{}' | jq -e '.state.sessions == []' >/dev/null
  register | jq -e '.state.sessions[0].retiredEpochs == []' >/dev/null
}
# Catch unbounded resolution diagnostics, invalid inactive references and heartbeat revival.
native_inactivity_and_resolution_summary() {
  register >/dev/null
  begin >/dev/null
  report input 2 needs-input '{"blockerId":"question","question":"Keep question"}' >/dev/null
  reject report "$(event bad-summary 3 blocker-resolved "$(jq -cn '{blockerId:"question",summary:("x"*4097)}')")" INVALID_REQUEST
  reject report "$(event bad-summary 3 blocker-resolved '{"blockerId":"question","summary":42}')" INVALID_REQUEST
  report unmatched 3 blocker-resolved '{"blockerId":"other","summary":"Unrelated failure"}' | jq -e '.state.tasks[0] | .reportedState == "needs-input" and .diagnostics == []' >/dev/null
  local args
  args=$(event current 4 snapshot "$(jq -cn --arg cwd "$checkout" '{cwd:$cwd,reportedState:"working"}')" | jq '.taskId="current"')
  mutate report "$args" >/dev/null
  jq '.sessions[0].nativeMetadata={currentTaskId:"current",turns:[{nativeId:"old",taskId:"turn"},{nativeId:"new",taskId:"current"}],inactiveTaskIds:["turn"]}' "$registry" >"$TMPDIR/fixture"
  mv "$TMPDIR/fixture" "$registry"
  report heartbeat 5 heartbeat | jq -e 'any(.state.tasks[];.taskId == "turn" and .freshness == "connection-lost" and .reportedState == "needs-input" and .question == "Keep question") and any(.state.tasks[];.taskId == "current" and .freshness == "unconfirmed")' >/dev/null
  for update in '.sessions[0].nativeMetadata.observedHooks=null' '.sessions[0].nativeMetadata.observedHooks=false' '.sessions[0].nativeMetadata.observedHooks=["StopFailure","StopFailure"]' '.sessions[0].nativeMetadata.observedHooks=["bad-name"]' '.sessions[0].nativeMetadata.observedHooks=[("x"*65)]' '.sessions[0].nativeMetadata.observedHooks=[range(33)|tostring|"Hook"+.]' '.sessions[0].nativeMetadata.inactiveTaskIds=null' '.sessions[0].nativeMetadata.inactiveTaskIds=false' '.sessions[0].nativeMetadata.inactiveTaskIds=["current"]' '.sessions[0].nativeMetadata.inactiveTaskIds=["missing"]' '.sessions[0].nativeMetadata.inactiveTaskIds=["turn","turn"]'; do
    cp "$registry" "$TMPDIR/valid"
    jq "$update" "$registry" >"$TMPDIR/fixture"
    mv "$TMPDIR/fixture" "$registry"
    cp "$registry" "$TMPDIR/before"
    if "$store" snapshot >"$TMPDIR/error"; then return 1; fi
    jq -e '.error.code == "ACTIVITY_INVALID"' "$TMPDIR/error" >/dev/null
    cmp "$registry" "$TMPDIR/before"
    mv "$TMPDIR/valid" "$registry"
  done
  mutate dismiss '{"taskId":"turn"}' | jq -e '.state.sessions[0].nativeMetadata.inactiveTaskIds == [] and (.state.tasks|length == 1)' >/dev/null
}
for name in snapshot_contract ordered_reports blockers_diagnostics_and_verification invalid_inputs_preserve_bytes corrupt_state_is_preserved association_and_registry_errors concurrency_conflict_and_no_implicit_session freshness_dismissal_and_symlinks capacity_retention_and_receipt_bounds nested_records_and_history_bounds missing_native_adapter_is_structured prompt_minimization_and_duplicate_replay attention_retention_respects_connection native_mapping_is_one_atomic_transaction write_failure_lock_timeout_and_clock_regression epoch_history_never_revives_a_retained_producer native_inactivity_and_resolution_summary; do run_case "$name"; done
((failures == 0))
