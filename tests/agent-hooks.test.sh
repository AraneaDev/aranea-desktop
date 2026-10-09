#!/usr/bin/env bash
# Native fixtures exercise actual silent ingress and durable reducer, no provider launch.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
hook="$repo_root/scripts/aranea-agent-hook"
store="$repo_root/scripts/aranea-agent-store"
checkout="$ARANEA_TEST_SANDBOX/checkout"
mkdir -p "$checkout"
# Deliver native display data through the installed boundary and require silence.
deliver() {
  jq -cn --arg cwd "$checkout" --argjson p "$1" '$p+{session_id:"fixture",cwd:$cwd}' | "$hook" claude >"$TMPDIR/out" 2>"$TMPDIR/err"
  [[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
}
# Read the actual store projection without changing durable bytes.
snap() { "$store" snapshot; }
[[ -x "$hook" ]] || {
  echo 'Claude hook boundary not implemented'
  exit 1
}
deliver '{"hook_event_name":"SessionStart","source":"startup"}'
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"p-one","prompt":"  Fix parser\nPRIVATE SECOND LINE"}'
snap | jq -e '.state.tasks[0] | .reportedState == "working" and .description == "Fix parser" and .freshness == "unconfirmed"' >/dev/null
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"SessionStart","source":"startup"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"p-one","prompt":"  Fix parser\nPRIVATE SECOND LINE"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_use_id":"question-a","tool_input":{"questions":[{"question":"Which parser?"}],"secret":"PRIVATE TOOL"}}'
deliver '{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","tool_use_id":"question-b","tool_input":{}}'
deliver '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"unrelated"}'
snap | jq -e '.state.tasks[0] | .reportedState == "needs-input" and (.blockers|length == 2)' >/dev/null
deliver '{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","tool_use_id":"question-a"}'
snap | jq -e '.state.tasks[0].blockers|length == 1' >/dev/null
deliver '{"hook_event_name":"PostToolUseFailure","tool_name":"ExitPlanMode","tool_use_id":"question-b","error":"Tool cancelled"}'
snap | jq -e '.state.tasks[0] | .reportedState == "working" and (.blockers|length == 0) and .diagnostics[-1].summary == "Tool cancelled"' >/dev/null
# Exact replay after resolution is accepted by the native store, not merely suppressed.
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
jq -cn --arg cwd "$checkout" '{action:"native",args:{provider:"claude",caller:null,payload:{session_id:"fixture",cwd:$cwd,hook_event_name:"PostToolUseFailure",tool_name:"ExitPlanMode",tool_use_id:"question-b",error:"Tool cancelled"}}}' | "$store" mutate | jq -e '.ok' >/dev/null
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"PRIVATE COMMAND"}}'
deliver '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"unknown"}'
snap | jq -e '.state.tasks[0] | .reportedState == "needs-input" and (.question|contains("unconfirmed"))' >/dev/null
deliver '{"hook_event_name":"PostToolUseFailure","tool_name":"AskUserQuestion","tool_use_id":"not-pending","error":"Unmatched question failed"}'
snap | jq -e '.state.tasks[0] | .reportedState == "needs-input" and (.question|contains("unconfirmed")) and .diagnostics[-1].summary == "Unmatched question failed"' >/dev/null
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"p-two","prompt":"Fix parser"}'
snap | jq -e '.state.tasks|length == 2 and any(.[];.reportedState == "needs-input" and .freshness == "connection-lost") and any(.[];.description == "Fix parser" and .reportedState == "working")' >/dev/null
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"p-one","prompt":"  Fix parser\nPRIVATE SECOND LINE"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
# A retained old native turn must not reset history after its replay receipt expires.
jq '.sessions[0].receipts=[] | .sessions[0].nativeMetadata.callbackOwners=[]' "$ARANEA_STATE_ROOT/agent-activity.json" >"$TMPDIR/no-receipts"
mv "$TMPDIR/no-receipts" "$ARANEA_STATE_ROOT/agent-activity.json"
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"p-one","prompt":"  Fix parser\nPRIVATE SECOND LINE"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"SubagentStart","agent_id":"child","agent_type":"Explore"}'
deliver '{"hook_event_name":"PreToolUse","agent_id":"child","prompt_id":"p-two","tool_name":"AskUserQuestion","tool_use_id":"child-question","tool_input":{"questions":[{"question":"Child question"}]}}'
snap | jq -e '.state.tasks | any(.[];.reportedState == "working" and .description == "Fix parser") and any(.[];.reportedState == "needs-input" and .description == "Subagent Explore")' >/dev/null
deliver '{"hook_event_name":"PostToolUse","agent_id":"child","prompt_id":"p-two","tool_name":"AskUserQuestion","tool_use_id":"child-question"}'
deliver '{"hook_event_name":"SubagentStop","agent_id":"child","last_assistant_message":"Child result"}'
snap | jq -e '.state.tasks | length == 3 and any(.[];.reportedState == "working" and .description == "Fix parser") and any(.[];.reportedState == "ready-for-review" and .description == "Subagent Explore")' >/dev/null
deliver '{"hook_event_name":"TaskCompleted","task_id":"native-task","task_subject":"Native task"}'
snap | jq -e '.state.tasks | length == 4 and any(.[];.reportedState == "working" and .description == "Fix parser") and any(.[];.reportedState == "finished" and .description == "Native task")' >/dev/null
deliver '{"hook_event_name":"Stop","prompt_id":"p-two","last_assistant_message":"Review changes"}'
snap | jq -e '.state.tasks | any(.[];.reportedState == "ready-for-review" and .result == "Review changes" and .verification.status == "unknown")' >/dev/null
deliver '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Idle"}'
snap | jq -e '.state.tasks | any(.[];.reportedState == "ready-for-review" and .result == "Review changes")' >/dev/null
deliver '{"hook_event_name":"StopFailure","prompt_id":"p-two","error":"API failed"}'
snap | jq -e '.state.tasks | any(.[];.reportedState == "failed" and .result == "API failed")' >/dev/null
deliver '{"hook_event_name":"SessionEnd","reason":"exit"}'
snap | jq -e '.state.sessions[0].connection.connected == false and any(.state.tasks[];.reportedState == "failed" and .result == "API failed")' >/dev/null
if rg -q 'PRIVATE' "$ARANEA_STATE_ROOT/agent-activity.json"; then exit 1; fi
echo 'PASS lifecycle, exact blockers, duplicates, child separation, privacy and unconfirmed provenance'
# Fail-open preserves malformed bytes, refuses missing session and unsupported provider/events.
printf '{broken' >"$ARANEA_STATE_ROOT/agent-activity.json"
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"SessionStart"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
printf '{}' | "$hook" unsupported >"$TMPDIR/out" 2>"$TMPDIR/err"
[[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
echo 'PASS fail-open invalid store and unsupported provider'
# Genuine owned ancestry uses a disposable bash executable named claude, never live Claude.
rm -rf "$ARANEA_STATE_ROOT"
mkdir -p "$ARANEA_TEST_SANDBOX/provider"
cp /bin/bash "$ARANEA_TEST_SANDBOX/provider/claude"
cat >"$TMPDIR/provider.sh" <<'PROVIDER'
#!/bin/bash
while IFS= read -r event; do
  [[ "$event" != quit ]] || exit 0
  if [[ "$event" == exec-sleep ]]; then printf 'done\n' >>"$2"; exec /bin/sleep 30; fi
  printf '%s\n' "$event" | /bin/bash "$1" claude
  printf 'done\n' >>"$2"
done
PROVIDER
mkfifo "$TMPDIR/events"
exec {event_fd}<>"$TMPDIR/events"
"$ARANEA_TEST_SANDBOX/provider/claude" "$TMPDIR/provider.sh" "$hook" "$TMPDIR/done" -p "PRIVATE PROVIDER ARGV" <"$TMPDIR/events" &
provider_pid=$!
# shellcheck disable=SC2016
sandbox_on_exit 'kill "$provider_pid" 2>/dev/null || true; wait "$provider_pid" 2>/dev/null || true'
# Await bounded externally observable results rather than assuming fork scheduling.
await_lines() {
  for _ in {1..100}; do
    if [[ -f "$TMPDIR/done" ]] && (($(wc -l <"$TMPDIR/done") >= $1)); then return 0; fi
    sleep .05
  done
  return 1
}
jq -cn --arg cwd "$checkout" '{session_id:"owned",cwd:$cwd,hook_event_name:"SessionStart",source:"startup"}' >&"$event_fd"
await_lines 1
jq -cn --arg cwd "$checkout" '{session_id:"owned",cwd:$cwd,hook_event_name:"UserPromptSubmit",prompt_id:"owned-one",prompt:"Owned task",pid:1}' >&"$event_fd"
await_lines 2
snap | jq -e --argjson pid "$provider_pid" '.state.sessions[0].provenance.pid == $pid and ((.state.sessions[0].provenance.commandHash//"")|test("^[a-f0-9]{64}$")) and ((.state.sessions[0].provenance.executable//"")|endswith("/provider/claude")) and .state.tasks[0].freshness == "connected"' >/dev/null
[[ -x "$repo_root/scripts/aranea-agent-heartbeat" ]] || {
  echo 'Owned heartbeat helper not implemented'
  exit 1
}
for _ in {1..100}; do
  if compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .05
done
identity=$(cat "$ARANEA_STATE_ROOT"/agent-heartbeats/*.json)
helper_pid=$(jq -r .pid <<<"$identity")
[[ $(jq -r .startTime <<<"$identity") =~ ^[0-9]+$ ]]
[[ "$helper_pid" != "$provider_pid" && -r /proc/$helper_pid/stat ]]
# Record creation alone is not a proven live heartbeat.
for _ in {1..100}; do
  if snap | jq -e 'any(.state.sessions[0].receipts[];.eventId|startswith("AraneaHeartbeat:"))' >/dev/null; then break; fi
  sleep .05
done
snap | jq -e 'any(.state.sessions[0].receipts[];.eventId|startswith("AraneaHeartbeat:"))' >/dev/null
if rg -q 'PRIVATE PROVIDER ARGV' "$ARANEA_STATE_ROOT/agent-activity.json" "$ARANEA_STATE_ROOT/agent-heartbeats"; then exit 1; fi
"$repo_root/scripts/aranea-agent-adapter" status claude | jq -e '.state.connectionProven and .state.enabled == "unconfirmed"' >/dev/null
epoch=$(snap | jq -r .state.sessions[0].producerEpoch)
# A single missed tick due to contention must keep ownership and recover receipts.
heartbeat_before=$(snap | jq '[.state.sessions[0].receipts[]|select(.eventId|startswith("AraneaHeartbeat:"))]|length')
flock "$ARANEA_STATE_ROOT/agent-activity.json.lock" -c 'sleep 18'
kill -0 "$provider_pid"
[[ $(jq -r .pid "$ARANEA_STATE_ROOT"/agent-heartbeats/*.json) == "$helper_pid" ]]
for _ in {1..170}; do
  if snap | jq -e --argjson before "$heartbeat_before" '[.state.sessions[0].receipts[]|select(.eventId|startswith("AraneaHeartbeat:"))]|length > $before' >/dev/null; then break; fi
  sleep .1
done
snap | jq -e --argjson before "$heartbeat_before" '[.state.sessions[0].receipts[]|select(.eventId|startswith("AraneaHeartbeat:"))]|length > $before' >/dev/null
[[ $(jq -r .pid "$ARANEA_STATE_ROOT"/agent-heartbeats/*.json) == "$helper_pid" ]]
echo 'PASS transient lock contention retains singleton and accepted heartbeat recovers'
# A direct fabricated native heartbeat cannot borrow the real provider's proof.
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
if jq -cn --arg epoch "$epoch" '{action:"native",args:{provider:"claude",caller:null,payload:{hook_event_name:"AraneaHeartbeat",session_id:"owned",producer_epoch:$epoch}}}' | "$store" mutate >"$TMPDIR/error"; then exit 1; fi
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
# A claimed PID cannot replace an established proven session through SessionStart.
jq -cn --argjson pid "$provider_pid" '{session_id:"owned",hook_event_name:"SessionStart",source:"spoof",cwd:"/tmp",pid:$pid}' | "$hook" claude
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
# Kernel start-time proof rejects a reused PID even when executable/argv still match.
script_dir="$repo_root/scripts"
# shellcheck source=scripts/lib/agent-hooks.sh
source "$script_dir/lib/agent-hooks.sh"
proof=$(snap | jq -c '.state.sessions[0].provenance')
agent_hooks_validate_provenance "$proof"
if agent_hooks_validate_provenance "$(jq '.startTime="0"' <<<"$proof")"; then exit 1; fi
# A second helper for the same epoch exits, leaving the winning owner intact.
/bin/bash "$repo_root/scripts/aranea-agent-heartbeat" claude owned "$epoch" "$provider_pid" "$(snap | jq -r .state.sessions[0].provenance.startTime)" "$(cat /proc/sys/kernel/random/boot_id)"
[[ $(jq -r .pid "$ARANEA_STATE_ROOT"/agent-heartbeats/*.json) == "$helper_pid" ]]
# Explicit end only stops this helper; lifecycle remains a working historical report.
jq -cn --arg cwd "$checkout" '{session_id:"owned",cwd:$cwd,hook_event_name:"SessionEnd",reason:"exit"}' >&"$event_fd"
await_lines 3
for _ in {1..170}; do
  if ! compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .1
done
if compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then exit 1; fi
kill -0 "$provider_pid"
snap | jq -e '.state.sessions[0].connection.connected == false and .state.tasks[0].reportedState == "working"' >/dev/null
if rg -q 'PRIVATE PROVIDER ARGV' "$ARANEA_STATE_ROOT/agent-activity.json" "$ARANEA_STATE_ROOT/agent-heartbeats"; then exit 1; fi
echo 'PASS owned ancestry, payload PID rejection, singleton heartbeat and exact session stop'

# A lost epoch stops only its helper; a provider exec with reused PID/start cannot refresh.
jq -cn --arg cwd "$checkout" '{session_id:"epoch-loss",cwd:$cwd,hook_event_name:"SessionStart",source:"startup"}' >&"$event_fd"
await_lines 4
for _ in {1..100}; do
  if compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .05
done
jq -cn '{action:"register",args:{provider:"claude",providerSessionId:"epoch-loss",producerEpoch:"replacement",tasks:[]}}' | "$store" mutate >/dev/null
for _ in {1..170}; do
  if ! compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .1
done
if compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then exit 1; fi
kill -0 "$provider_pid"
jq -cn --arg cwd "$checkout" '{session_id:"exec-loss",cwd:$cwd,hook_event_name:"SessionStart",source:"startup"}' >&"$event_fd"
await_lines 5
for _ in {1..100}; do
  if compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .05
done
printf 'exec-sleep\n' >&"$event_fd"
await_lines 6
for _ in {1..170}; do
  if ! compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .1
done
if compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then
  echo 'Provider exec wrongly remains connected'
  exit 1
fi
kill -0 "$provider_pid"
kill "$provider_pid"
wait "$provider_pid" || true
if agent_hooks_validate_provenance "$proof"; then exit 1; fi
# Missing provider PID cannot create durable helper state or alter lifecycle.
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
/bin/bash "$repo_root/scripts/aranea-agent-heartbeat" claude owned "$epoch" "$provider_pid" "$(jq -r .startTime <<<"$proof")" "$(cat /proc/sys/kernel/random/boot_id)"
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
if compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then exit 1; fi
echo 'PASS epoch and provider executable identity loss stop only helper'
# The reporter ignores checkout-local bootstrap names and fails open on a missing worker.
rm -rf "$ARANEA_STATE_ROOT"
mkdir -p "$checkout/bin" "$TMPDIR/missing"
for executable in bash jq timeout; do
  printf '#!/bin/bash\nprintf hostile >> %q\nexit 99\n' "$TMPDIR/hostile" >"$checkout/bin/$executable"
  chmod +x "$checkout/bin/$executable"
done
PATH="$checkout/bin:.:/usr/bin:/bin" "$hook" claude <<'NATIVE'
{"session_id":"safe-path","hook_event_name":"SessionStart","cwd":"/tmp"}
NATIVE
[[ ! -e "$TMPDIR/hostile" ]]
snap | jq -e 'any(.state.sessions[];.providerSessionId == "safe-path" and .provenance == null)' >/dev/null
cp "$hook" "$TMPDIR/missing/aranea-agent-hook"
printf '{}' | "$TMPDIR/missing/aranea-agent-hook" claude >"$TMPDIR/out" 2>"$TMPDIR/err"
[[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
# Contended hook cannot delay or change approval flow; exact bytes survive.
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
flock "$ARANEA_STATE_ROOT/agent-activity.json.lock" -c 'sleep 3' &
locker=$!
sleep .1
started=$(date +%s.%N)
"$hook" claude <<'NATIVE'
{"session_id":"safe-path","hook_event_name":"UserPromptSubmit","prompt_id":"locked","prompt":"Locked","cwd":"/tmp"}
NATIVE
ended=$(date +%s.%N)
awk -v started="$started" -v ended="$ended" 'BEGIN {exit !(ended-started < 2.5)}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
wait "$locker"
echo 'PASS safe executable bootstrap, missing dependency and bounded lock contention'

# Real native ingress streams both large retained state and a large prompt, without argv limits.
rm -rf "$ARANEA_STATE_ROOT"
deliver '{"hook_event_name":"SessionStart","source":"startup"}'
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"large-seed","prompt":"Seed"}'
jq '.tasks[0] as $task | .tasks += [range(100) as $i | $task + {taskId:("fixture-"+($i|tostring)),description:("d"*4000)}]' "$ARANEA_STATE_ROOT/agent-activity.json" >"$TMPDIR/large-state"
mv "$TMPDIR/large-state" "$ARANEA_STATE_ROOT/agent-activity.json"
[[ $(stat -c %s "$ARANEA_STATE_ROOT/agent-activity.json") -gt 131072 ]]
jq -cn --arg cwd "$checkout" '{session_id:"fixture",hook_event_name:"UserPromptSubmit",prompt_id:"large-next",prompt:("Large first line\nPRIVATE LARGE PROMPT"+("x"*300000)),cwd:$cwd}' | "$hook" claude >"$TMPDIR/out" 2>"$TMPDIR/err"
[[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
snap | jq -e 'any(.state.tasks[];.description == "Large first line" and .reportedState == "working") and (.state.tasks|length == 102)' >/dev/null
if rg -q 'PRIVATE LARGE PROMPT' "$ARANEA_STATE_ROOT"; then exit 1; fi
echo 'PASS large retained state and raw prompt stream through real native ingress'

# Providers without native prompt IDs provide exact replay, but not delivery certainty.
deliver '{"hook_event_name":"UserPromptSubmit","prompt":"No native turn ID"}'
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"prompt":"No native turn ID","hook_event_name":"UserPromptSubmit"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
"$repo_root/scripts/aranea-agent-adapter" status claude | jq -e '.state.capabilities.duplicateDelivery|contains("unavailable-without-prompt_id")' >/dev/null
echo 'PASS canonical no-ID replay and explicit duplicate-certainty limitation'

# Retained callbacks keep their original native turn even after currentTaskId changes.
rm -rf "$ARANEA_STATE_ROOT"
deliver '{"hook_event_name":"SessionStart"}'
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"first","prompt":"First turn"}'
# Valid retained task IDs may contain separators; correlation must preserve them.
jq '.tasks[0].taskId="fixture:main:with:colons" | .sessions[0].nativeMetadata.currentTaskId="fixture:main:with:colons" | .sessions[0].nativeMetadata.turns[0].taskId="fixture:main:with:colons" | if (.sessions[0].nativeMetadata|has("callbackOwners")) then .sessions[0].nativeMetadata.callbackOwners |= map(.taskId="fixture:main:with:colons") else . end' "$ARANEA_STATE_ROOT/agent-activity.json" >"$TMPDIR/colon-task"
mv "$TMPDIR/colon-task" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_use_id":"unique-old-tool","tool_input":{"questions":[{"question":"Old question?"}]}}'
deliver '{"hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","tool_use_id":"old-plan","tool_input":{}}'
deliver '{"hook_event_name":"Stop","last_assistant_message":"First turn result"}'
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"second","prompt":"Second turn"}'
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/turn-before"
deliver '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_use_id":"unique-old-tool","tool_input":{"questions":[{"question":"Old question?"}]}}'
cmp "$TMPDIR/turn-before" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"Stop","last_assistant_message":"First turn result"}'
cmp "$TMPDIR/turn-before" "$ARANEA_STATE_ROOT/agent-activity.json"
# Exact retained replay succeeds at the store transport, not only silent wrapper.
jq -cn --arg cwd "$checkout" '{action:"native",args:{provider:"claude",caller:null,payload:{session_id:"fixture",cwd:$cwd,hook_event_name:"Stop",last_assistant_message:"First turn result"}}}' | "$store" mutate | jq -e '.ok' >/dev/null
cmp "$TMPDIR/turn-before" "$ARANEA_STATE_ROOT/agent-activity.json"
# Changed reuse and a contradictory explicit turn cannot rewrite either task.
for payload in '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_use_id":"unique-old-tool","tool_input":{"questions":[{"question":"Changed question"}]}}' '{"hook_event_name":"PostToolUse","prompt_id":"second","tool_name":"AskUserQuestion","tool_use_id":"unique-old-tool"}'; do
  jq -cn --arg cwd "$checkout" --argjson p "$payload" '{action:"native",args:{provider:"claude",caller:null,payload:($p+{session_id:"fixture",cwd:$cwd})}}' | "$store" mutate >"$TMPDIR/error" 2>"$TMPDIR/err" && exit 1
  jq -e '.ok == false and (.error.code == "ADAPTER_UNSUPPORTED" or .error.code == "EVENT_ID_CONFLICT")' "$TMPDIR/error" >/dev/null
  cmp "$TMPDIR/turn-before" "$ARANEA_STATE_ROOT/agent-activity.json"
done
# First late results use the tool identity established by earlier PreToolUse.
deliver '{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","tool_use_id":"unique-old-tool"}'
deliver '{"hook_event_name":"PostToolUseFailure","tool_name":"ExitPlanMode","tool_use_id":"old-plan","error":"Old tool cancelled"}'
snap | jq -e '.state.tasks | any(.[];.description == "Second turn" and .reportedState == "working" and .result == "" and .question == "" and (.diagnostics|length == 0)) and any(.[];.description == "First turn" and .freshness == "connection-lost" and (.blockers|length == 0) and .diagnostics[-1].summary == "Old tool cancelled")' >/dev/null
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/turn-before"
deliver '{"hook_event_name":"PostToolUseFailure","tool_name":"ExitPlanMode","tool_use_id":"old-plan","error":"Old tool cancelled"}'
cmp "$TMPDIR/turn-before" "$ARANEA_STATE_ROOT/agent-activity.json"
snap | jq -e '[.state.sessions[0].receipts[]|select(.eventId|startswith("PreToolUse:"))]|length == 2' >/dev/null
echo 'PASS retained native tool/lifecycle replay and first late results preserve original turn'

# Private ownership cannot confuse delimiter IDs or borrow explicit event labels.
rm -rf "$ARANEA_STATE_ROOT"
deliver '{"hook_event_name":"SessionStart"}'
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"one","prompt":"First"}'
jq '.tasks[0].taskId="A" | .sessions[0].nativeMetadata.currentTaskId="A" | .sessions[0].nativeMetadata.turns[0].taskId="A" | if (.sessions[0].nativeMetadata|has("callbackOwners")) then .sessions[0].nativeMetadata.callbackOwners |= map(.taskId="A") else . end' "$ARANEA_STATE_ROOT/agent-activity.json" >"$TMPDIR/rename"
mv "$TMPDIR/rename" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_use_id":"B:C","tool_input":{"questions":[{"question":"First tool"}]}}'
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"two","prompt":"Second"}'
jq '(.sessions[0].nativeMetadata.currentTaskId) as $id | .tasks |= map(if .taskId == $id then .taskId="A:B" else . end) | .sessions[0].nativeMetadata.currentTaskId="A:B" | .sessions[0].nativeMetadata.turns |= map(if .taskId == $id then .taskId="A:B" else . end) | if (.sessions[0].nativeMetadata|has("callbackOwners")) then .sessions[0].nativeMetadata.callbackOwners |= map(if .taskId == $id then .taskId="A:B" else . end) else . end' "$ARANEA_STATE_ROOT/agent-activity.json" >"$TMPDIR/rename"
mv "$TMPDIR/rename" "$ARANEA_STATE_ROOT/agent-activity.json"
# Public report can choose any label, but cannot establish native tool ownership.
snapshot=$(snap)
jq -c '.state.sessions[0] | {action:"report",args:{schemaVersion:1,eventId:"PreToolUse:A:B:forged-tool",provider:"claude",providerSessionId:.providerSessionId,producerEpoch:.producerEpoch,sequence:(.highWaterSequence+1),taskId:"A:B",kind:"needs-input",payload:{blockerId:"tool:forged-tool",question:"Explicit report question"}}}' <<<"$snapshot" | "$store" mutate >/dev/null
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"three","prompt":"Third"}'
deliver '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_use_id":"C","tool_input":{"questions":[{"question":"Third tool"}]}}'
snap | jq -e 'any(.state.tasks[];.description == "Third" and .question == "Third tool" and .reportedState == "needs-input")' >/dev/null
deliver '{"hook_event_name":"PostToolUseFailure","tool_name":"AskUserQuestion","tool_use_id":"C","error":"Third tool failed"}'
deliver '{"hook_event_name":"PostToolUseFailure","tool_name":"AskUserQuestion","tool_use_id":"forged-tool","error":"Uncorrelated failure"}'
snap | jq -e 'any(.state.tasks[];.taskId == "A:B" and .reportedState == "needs-input" and .question == "Explicit report question" and (.diagnostics|length == 0)) and any(.state.tasks[];.description == "Third" and .reportedState == "working" and (.diagnostics|map(.summary)) == ["Third tool failed","Uncorrelated failure"])' >/dev/null
# Shared parent context is not child identity or a permission-decision identity.
deliver '{"hook_event_name":"SubagentStart","agent_id":"child-one","prompt_id":"three","agent_type":"Explore"}'
deliver '{"hook_event_name":"SubagentStart","agent_id":"child-two","prompt_id":"three","agent_type":"Explore"}'
deliver '{"hook_event_name":"SubagentStop","agent_id":"child-one","prompt_id":"three","last_assistant_message":"One result"}'
deliver '{"hook_event_name":"SubagentStop","agent_id":"child-two","prompt_id":"three","last_assistant_message":"Two result"}'
deliver '{"hook_event_name":"TaskCompleted","task_id":"task-one","agent_id":"child-one","prompt_id":"three","task_subject":"One task"}'
deliver '{"hook_event_name":"TaskCompleted","task_id":"task-two","agent_id":"child-one","prompt_id":"three","task_subject":"Two task"}'
deliver '{"hook_event_name":"PermissionRequest","prompt_id":"three","tool_name":"Read","tool_input":{"file_path":"one"}}'
deliver '{"hook_event_name":"PermissionRequest","prompt_id":"three","tool_name":"Read","tool_input":{"file_path":"two"}}'
snap | jq -e 'any(.state.tasks[];.result == "One result" and .reportedState == "ready-for-review") and any(.state.tasks[];.result == "Two result" and .reportedState == "ready-for-review") and ([.state.tasks[]|select(.reportedState == "finished")]|length == 2) and any(.state.tasks[];.description == "Third" and (.blockers|length == 2))' >/dev/null
# Legacy epochs remain readable, but no uncorrelated callback gains new ownership.
jq 'del(.sessions[0].nativeMetadata.callbackOwners)' "$ARANEA_STATE_ROOT/agent-activity.json" >"$TMPDIR/legacy"
mv "$TMPDIR/legacy" "$ARANEA_STATE_ROOT/agent-activity.json"
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"SessionStart"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
"$repo_root/scripts/aranea-agent-adapter" status claude | jq -e '.state.capabilities.callbackOwnership.restartRequired and .state.capabilities.callbackOwnership.legacySessions == 1' >/dev/null
deliver '{"hook_event_name":"Stop","last_assistant_message":"Uncorrelated legacy result"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"Stop","prompt_id":"three","last_assistant_message":"Explicit legacy turn result"}'
snap | jq -e 'any(.state.tasks[];.description == "Third" and .result == "Explicit legacy turn result") and (.state.sessions[0].nativeMetadata|has("callbackOwners")|not)' >/dev/null
deliver '{"hook_event_name":"SessionStart","source":"new-epoch"}'
snap | jq -e '.state.sessions[0].nativeMetadata.callbackOwners == []' >/dev/null
"$repo_root/scripts/aranea-agent-adapter" status claude | jq -e '(.state.capabilities.callbackOwnership.restartRequired|not) and .state.capabilities.callbackOwnership.legacySessions == 0' >/dev/null
echo 'PASS delimiter-safe private ownership, forged labels and conservative legacy recovery'
