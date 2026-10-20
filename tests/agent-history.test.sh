#!/usr/bin/env bash
# Dense history must validate exactly and persist every native delivery within its deadline.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
registry="$ARANEA_STATE_ROOT/agent-activity.json"
store="$repo_root/scripts/aranea-agent-store"
hook="$repo_root/scripts/aranea-agent-hook"
mkdir -p "$ARANEA_STATE_ROOT" "$TMPDIR/checkout"
jq -n --arg cwd "$TMPDIR/checkout" --argjson now "$(date +%s)" --argjson monotonic "$(cut -d. -f1 /proc/uptime)" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" -f "$repo_root/tests/fixtures/agent-history.jq" >"$registry"
cp "$registry" "$TMPDIR/dense"
"$store" snapshot | jq -e '.ok and (.state.sessions|length == 7) and (.state.tasks|length == 41) and all(.state.sessions[];(.receipts|length == 512) and (.nativeMetadata.callbackOwners|length == 512) and (.nativeMetadata.turns|length|. >= 5 and . <= 6))' >/dev/null
# Both adapters must durably apply every sequential delivery, never silently time out.
for delivery in {1..20}; do
  case $(((delivery - 1) % 4)) in
    0)
      provider=claude
      session=0
      event=PreToolUse
      state=needs-input
      pair=$delivery
      ;;
    1)
      provider=claude
      session=0
      event=PostToolUse
      state=working
      pair=$((delivery - 1))
      ;;
    2)
      provider=codex
      session=1
      event=PreToolUse
      state=working
      pair=$delivery
      ;;
    3)
      provider=codex
      session=1
      event=PostToolUse
      state=working
      pair=$((delivery - 1))
      ;;
  esac
  jq -cn --arg provider "$provider" --arg session "dense:session:$session" --arg event "$event" --arg tool "delivery-tool:$pair" '{session_id:$session,hook_event_name:$event,tool_name:"AskUserQuestion",tool_use_id:$tool,tool_input:{questions:[{question:"Dense question?"}]}} + (if $provider == "codex" then {turn_id:"turn:5"} else {prompt_id:"turn:5"} end)' >"$TMPDIR/payload"
  started=$(date +%s.%N)
  /usr/bin/timeout 2 "$hook" "$provider" <"$TMPDIR/payload" >"$TMPDIR/out" 2>"$TMPDIR/err"
  ended=$(date +%s.%N)
  [[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
  if ! jq -e --arg session "dense:session:$session" --arg state "$state" --arg provider "$provider" --arg event "$event" --argjson revision "$((100 + delivery))" '.revision == $revision and any(.tasks[];.providerSessionId == $session and .description == "Dense task 5" and .reportedState == $state and (if $provider == "codex" then .diagnostics[-1].summary == ($event+": AskUserQuestion") else (if $state == "needs-input" then .question == "Dense question?" and (.blockers|length == 1) else .question == "" and (.blockers|length == 0) end) end))' "$registry" >/dev/null; then
    echo "FAIL dense native delivery $delivery did not persist (elapsed $(awk -v s="$started" -v e="$ended" 'BEGIN {printf "%.3f",e-s}')s)"
    exit 1
  fi
  # Same-directory atomic rename updates the published inode's change time.
  published=$(date -d "$(stat -c %z "$registry")" +%s.%N)
  awk -v s="$started" -v p="$published" -v e="$ended" -v n="$delivery" 'BEGIN {printf "dense native delivery %02d: published %.3fs, returned %.3fs\n",n,p-s,e-s; exit !(p-s >= 0 && p-s < 1.5)}'
done
# A retained tool callback must update its original old task, and replay changes no bytes.
jq -cn '{session_id:"dense:session:0",hook_event_name:"PostToolUseFailure",tool_name:"ExitPlanMode",tool_use_id:"dense-tool:100",error:"Late dense callback"}' >"$TMPDIR/late"
"$hook" claude <"$TMPDIR/late"
jq -e 'any(.tasks[];.providerSessionId == "dense:session:0" and .description == "Dense task 4" and .diagnostics[-1].summary == "Late dense callback") and any(.tasks[];.providerSessionId == "dense:session:0" and .description == "Dense task 5" and .reportedState == "working" and (.diagnostics|length == 0))' "$registry" >/dev/null
cp "$registry" "$TMPDIR/replay"
"$hook" claude <"$TMPDIR/late"
cmp "$TMPDIR/replay" "$registry"
echo 'PASS dense stale callback ownership and exact replay'
# Index construction must never hide malformed shapes, duplicates or foreign references.
for change in '.sessions[0].nativeMetadata.callbackOwners[0].taskId=.tasks[6].taskId' '.sessions[0].nativeMetadata.callbackOwners[0].eventId="missing"' '.sessions[0].nativeMetadata.callbackOwners += [.sessions[0].nativeMetadata.callbackOwners[0]]' '.sessions[0].receipts[1].eventId=.sessions[0].receipts[0].eventId' '.sessions[0].nativeMetadata.turns[0].taskId=.tasks[6].taskId' '.sessions[0].nativeMetadata.inactiveTaskIds[0]=.tasks[6].taskId' '.tasks[0].producerEpoch="foreign"' '.sessions[0].nativeMetadata.callbackOwners={}' '.sessions[0].receipts[0].eventId=12' '.tasks[1].taskId=.tasks[0].taskId' '.sessions[0].nativeMetadata.callbackOwners[0].taskId=("x"*257)' '.sessions[0].nativeMetadata.callbackOwners[0].eventId="\u0001"' '.sessions[0].nativeMetadata.callbackOwners[0].eventId=42' '.sessions[0].nativeMetadata.currentTaskId="\u0001"' '.sessions[0].nativeMetadata.turns[0].taskId=42' '.sessions[0].nativeMetadata.inactiveTaskIds[0]=null' '.sessions[0].receipts[0].extra=true' '.sessions[0].receipts[0].hash=("0"*63) | .sessions[0].receipts[1].hash=("0"*65)' '.sessions[0].receipts[0].hash=("g"*64)' '.sessions[0].receipts[0].hash=42' '.sessions[0].receipts[0].eventId="\u0001"' '.sessions[0].receipts[0].eventId=""' '.sessions[0].nativeMetadata.callbackOwners[0].key=("0"*63) | .sessions[0].nativeMetadata.callbackOwners[1].key=("0"*65)' '.sessions[0].nativeMetadata.callbackOwners[0].key=("G"*64)' '.sessions[0].nativeMetadata.callbackOwners[0].toolUseId="\u0001"' '.sessions[0].nativeMetadata.callbackOwners[0].toolUseId=""' '.sessions[0].nativeMetadata.callbackOwners[0].toolUseId=("t"*181)'; do
  jq "$change" "$TMPDIR/dense" >"$registry"
  cp "$registry" "$TMPDIR/invalid"
  if "$store" snapshot >"$TMPDIR/error"; then
    echo "FAIL invalid dense history accepted: $change"
    exit 1
  fi
  jq -e '.error.code == "ACTIVITY_INVALID"' "$TMPDIR/error" >/dev/null
  cmp "$TMPDIR/invalid" "$registry"
done
echo 'PASS dense malformed references and duplicates preserve exact state bytes'
# Cached validation is valid only for exact unchanged sessions. A changed
# candidate must still satisfy its schema and every same-session reference.
jq -n --argjson now "$(date +%s)" --argjson monotonic "$(cut -d. -f1 /proc/uptime)" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" '{receivedAt:$now,monotonic:$monotonic,bootId:$boot,generatedId:"candidate"}' >"$TMPDIR/context"
printf '{"projects":[]}\n' >"$TMPDIR/projects"
# shellcheck disable=SC2016
for change in '.currentTaskId=$s[0].tasks[6].taskId' '.turns[0].taskId=$s[0].tasks[6].taskId' '.callbackOwners[-1].key=("g"*64)'; do
  jq '. as $s | {action:"native",args:{normalized:{action:"report",args:{schemaVersion:1,eventId:"candidate",provider:"claude",providerSessionId:"dense:session:0",producerEpoch:"dense:epoch",sequence:513,taskId:$s.tasks[5].taskId,kind:"working",payload:{}},nativeMetadata:$s.sessions[0].nativeMetadata}}}' "$TMPDIR/dense" >"$TMPDIR/candidate-base"
  # Keep the fixture's valid values available while altering only candidate metadata.
  jq --slurpfile s "$TMPDIR/dense" ".args.normalized.nativeMetadata |= ($change)" "$TMPDIR/candidate-base" >"$TMPDIR/candidate" 2>"$TMPDIR/error" || exit 1
  if jq -c --arg operation store-transaction --arg hash "$(printf '%064d' 0)" --slurpfile activity_context "$TMPDIR/context" --slurpfile activity_projects "$TMPDIR/projects" --slurpfile activity_request "$TMPDIR/candidate" -f "$repo_root/scripts/lib/agent-activity.jq" "$TMPDIR/dense" >"$TMPDIR/result" 2>"$TMPDIR/error"; then
    echo "FAIL invalid changed transaction candidate accepted: $change"
    exit 1
  fi
  [[ ! -s "$TMPDIR/result" ]]
  rg -q ACTIVITY_INVALID "$TMPDIR/error"
done
echo 'PASS changed transaction candidates retain full schema and session-reference validation'
