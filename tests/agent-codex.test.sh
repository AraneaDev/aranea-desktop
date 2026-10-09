#!/usr/bin/env bash
# Codex native fixtures use the real silent ingress/store, never a live provider.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
unset CODEX_HOME
hook="$repo_root/scripts/aranea-agent-hook"
store="$repo_root/scripts/aranea-agent-store"
adapter="$repo_root/scripts/aranea-agent-adapter"
mkdir -p "$ARANEA_TEST_SANDBOX/checkout"
# Send real native envelopes and require nonsteering success/silence.
deliver() {
  jq -cn --arg cwd "$ARANEA_TEST_SANDBOX/checkout" --argjson p "$1" '$p+{session_id:"thr_fixture",cwd:$cwd}' | "$hook" codex >"$TMPDIR/out" 2>"$TMPDIR/err"
  [[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
}
# Read durable state without changing it.
snap() { "$store" snapshot; }
deliver '{"hook_event_name":"SessionStart","source":"startup"}'
deliver '{"hook_event_name":"UserPromptSubmit","turn_id":"one","prompt":"Fix parser\nPRIVATE"}'
snap | jq -e '.state.tasks|length==1 and .[0].provider=="codex" and .[0].description=="Fix parser" and .[0].reportedState=="working" and .[0].freshness=="unconfirmed"' >/dev/null || {
  echo 'FAIL Codex native turn was not ingested'
  exit 1
}
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"UserPromptSubmit","turn_id":"one","prompt":"Fix parser\nPRIVATE"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
# Claude-only names and missing turn identity cannot create an invented task.
for event in StopFailure TaskCompleted Notification PostToolUseFailure; do
  deliver "{\"hook_event_name\":\"$event\",\"turn_id\":\"one\",\"task_id\":\"fake\"}"
done
deliver '{"hook_event_name":"UserPromptSubmit","prompt_id":"fake","prompt":"Unknown turn"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"PreToolUse","turn_id":"one","tool_name":"request_user_input","tool_use_id":"q","tool_input":{}}'
snap | jq -e '.state.tasks[0].reportedState=="working"' >/dev/null
deliver '{"hook_event_name":"PermissionRequest","turn_id":"one","tool_name":"Bash","tool_input":{"command":"PRIVATE"}}'
for fields in '"tool_use_id":"different"' '"tool_response":{"exit_code":1}'; do
  deliver "{\"hook_event_name\":\"PostToolUse\",\"turn_id\":\"one\",\"tool_name\":\"Bash\",$fields}"
done
deliver '{"hook_event_name":"Interrupt","turn_id":"one"}'
snap | jq -e '.state.tasks[0] | .reportedState=="needs-input" and (.blockers|length)==1 and (.diagnostics[-1].summary|contains("interrupted")) and .verification.status=="unknown"' >/dev/null
# Child identity takes precedence over its parent turn. Stop cannot finish parent.
deliver '{"hook_event_name":"SubagentStart","turn_id":"one","agent_id":"child","agent_type":"explorer"}'
deliver '{"hook_event_name":"SubagentStop","turn_id":"one","agent_id":"child","last_assistant_message":"Child done"}'
snap | jq -e '.state.tasks|length==2 and any(.[];.reportedState=="needs-input") and any(.[];.reportedState=="ready-for-review" and .result=="Child done")' >/dev/null
deliver '{"hook_event_name":"Stop","turn_id":"one","last_assistant_message":"Review","extra":"ignored"}'
snap | jq -e '.state.tasks[0]|.reportedState=="ready-for-review" and .verification.status=="unknown"' >/dev/null
deliver '{"hook_event_name":"UserPromptSubmit","turn_id":"two","prompt":"Next"}'
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"Stop","turn_id":"one","last_assistant_message":"Review","extra":"ignored"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
# A tool's retained owner cannot be reassigned by a contradictory current turn.
deliver '{"hook_event_name":"PostToolUse","turn_id":"two","tool_name":"request_user_input","tool_use_id":"q"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
deliver '{"hook_event_name":"SessionEnd","reason":"other"}'
snap | jq -e '.state.sessions[0].connection.connected==false and .state.tasks[-1].reportedState=="working"' >/dev/null
# Retained old turn identities cannot allocate a fresh task when receipts expire.
jq '.sessions[0].receipts=[] | .sessions[0].nativeMetadata.callbackOwners=[]' "$ARANEA_STATE_ROOT/agent-activity.json" >"$TMPDIR/expired"
mv "$TMPDIR/expired" "$ARANEA_STATE_ROOT/agent-activity.json"
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"UserPromptSubmit","turn_id":"one","prompt":"Fix parser\nPRIVATE"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
# Legacy metadata stays legacy; missing correlation never chooses its current turn.
jq 'del(.sessions[0].nativeMetadata.callbackOwners)' "$ARANEA_STATE_ROOT/agent-activity.json" >"$TMPDIR/legacy"
mv "$TMPDIR/legacy" "$ARANEA_STATE_ROOT/agent-activity.json"
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
deliver '{"hook_event_name":"Stop","last_assistant_message":"Uncorrelated legacy"}'
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
echo 'PASS Codex turns, child isolation, replay ownership, permission uncertainty, interruption and silent output'
# hooks.json is independent of inline configuration, trust and permission policy.
export CODEX_HOME="$HOME/custom codex"
mkdir -p "$CODEX_HOME"
printf '%s\n' 'allow_only_managed_hooks = true' '[[hooks.Stop]]' 'matcher = ""' >"$CODEX_HOME/config.toml"
cp "$CODEX_HOME/config.toml" "$TMPDIR/toml"
config="$CODEX_HOME/hooks.json"
printf '%s\n' '{"description":"Keep","hooks":{"Stop":[{"matcher":"keep","custom":true,"hooks":[{"type":"command","command":"unrelated","timeout":7}]}],"Custom":[]}}' >"$config"
cp "$config" "$TMPDIR/original"
"$adapter" install codex | jq -e '.ok and .state.provider=="codex" and .state.configured and .state.trusted=="unconfirmed" and .state.enabled=="unconfirmed" and (.state.runtimeObserved|not) and (.state.connectionProven|not) and .state.capabilities.userInput=="unconfirmed-use-explicit-reports" and (.state.capabilities.baselineHooks|index("Interrupt")!=null and index("StopFailure")==null)' >/dev/null
cp "$config" "$TMPDIR/installed"
"$adapter" install codex >/dev/null
cmp "$config" "$TMPDIR/installed"
"$adapter" remove codex >/dev/null
cmp <(jq -Sc . "$config") <(jq -Sc . "$TMPDIR/original")
cmp "$CODEX_HOME/config.toml" "$TMPDIR/toml"
printf '{broken' >"$config"
if "$adapter" install codex >"$TMPDIR/error"; then exit 1; fi
jq -e '.error.code=="ADAPTER_CONFIG_INVALID"' "$TMPDIR/error" >/dev/null
[[ $(cat "$config") == '{broken' ]]
rm "$config"
ln -s "$TMPDIR/original" "$config"
if "$adapter" install codex >"$TMPDIR/error"; then exit 1; fi
jq -e '.error.code=="UNSAFE_CONFIG_PATH"' "$TMPDIR/error" >/dev/null
unset CODEX_HOME
"$adapter" install codex >/dev/null
[[ -f "$HOME/.codex/hooks.json" ]]
echo 'PASS Codex owned hooks.json merge/removal, configured vs trusted, untouched TOML and safe paths'
# Native ownership requires an actual Codex CLI ancestor and owns one heartbeat.
mkdir -p "$ARANEA_TEST_SANDBOX/provider"
cp /bin/bash "$ARANEA_TEST_SANDBOX/provider/codex"
cp /bin/bash "$ARANEA_TEST_SANDBOX/provider/claude"
cat >"$TMPDIR/provider.sh" <<'PROVIDER'
#!/bin/bash
set -euo pipefail
printf '%s\n' '{"session_id":"owned-codex","hook_event_name":"SessionStart","cwd":"/tmp","source":"startup"}' | /bin/bash "$1" codex
printf '%s\n' '{"session_id":"owned-codex","hook_event_name":"UserPromptSubmit","turn_id":"owned-turn","cwd":"/tmp","prompt":"Owned Codex"}' | /bin/bash "$1" codex
touch "$2.ready"
while [[ ! -e "$2.stop" ]]; do sleep .05; done
printf '%s\n' '{"session_id":"owned-codex","hook_event_name":"SessionEnd","cwd":"/tmp","reason":"other"}' | /bin/bash "$1" codex
PROVIDER
"$ARANEA_TEST_SANDBOX/provider/codex" "$TMPDIR/provider.sh" "$hook" "$TMPDIR/native" &
provider_pid=$!
sandbox_on_exit "kill $provider_pid 2>/dev/null || true"
for _ in {1..100}; do
  [[ ! -e "$TMPDIR/native.ready" ]] || break
  sleep .05
done
[[ -e "$TMPDIR/native.ready" ]]
snap | jq -e --argjson pid "$provider_pid" 'any(.state.sessions[];.provider=="codex" and .providerSessionId=="owned-codex" and .provenance.pid==$pid and (.nativeMetadata.observedHooks|index("UserPromptSubmit")!=null)) and any(.state.tasks[];.description=="Owned Codex" and .freshness=="connected")' >/dev/null
for _ in {1..100}; do
  if snap | jq -e 'any(.state.sessions[]; .providerSessionId=="owned-codex" and any(.receipts[];.eventId|startswith("AraneaHeartbeat:")))' >/dev/null; then break; fi
  sleep .05
done
snap | jq -e 'any(.state.sessions[]; .providerSessionId=="owned-codex" and any(.receipts[];.eventId|startswith("AraneaHeartbeat:")))' >/dev/null
"$adapter" status codex | jq -e '.state.connectionProven and .state.runtimeObserved and .state.trusted=="unconfirmed"' >/dev/null
identity=$(cat "$ARANEA_STATE_ROOT"/agent-heartbeats/*.json)
helper_pid=$(jq -r .pid <<<"$identity")
[[ "$helper_pid" != "$provider_pid" ]]
epoch=$(snap | jq -r '.state.sessions[]|select(.providerSessionId=="owned-codex")|.producerEpoch')
# A sibling cannot borrow the owned epoch, including for fabricated heartbeat.
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
printf '%s\n' '{"session_id":"owned-codex","hook_event_name":"Stop","turn_id":"owned-turn","last_assistant_message":"Forged","cwd":"/tmp"}' | "$hook" codex
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
if jq -cn --arg epoch "$epoch" '{action:"native",args:{provider:"codex",caller:null,payload:{hook_event_name:"AraneaHeartbeat",session_id:"owned-codex",producer_epoch:$epoch}}}' | "$store" mutate >"$TMPDIR/error"; then exit 1; fi
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
touch "$TMPDIR/native.stop"
wait "$provider_pid"
for _ in {1..170}; do
  if ! compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .1
done
if compgen -G "$ARANEA_STATE_ROOT/agent-heartbeats/*.json" >/dev/null; then exit 1; fi
# Unconfirmed app-server ancestry and a Claude parent cannot own Codex sessions.
cat >"$TMPDIR/unproven.sh" <<'PROVIDER'
#!/bin/bash
/bin/bash "$1" codex <"$2"
PROVIDER
for mode in app-server claude; do
  path="$ARANEA_TEST_SANDBOX/provider/codex"
  [[ "$mode" != claude ]] || path="$ARANEA_TEST_SANDBOX/provider/claude"
  printf '%s\n' '{"session_id":"unproven-'"$mode"'","hook_event_name":"SessionStart","cwd":"/tmp"}' >"$TMPDIR/event"
  "$path" "$TMPDIR/unproven.sh" "$hook" "$TMPDIR/event" "$mode"
  snap | jq -e --arg id "unproven-$mode" 'any(.state.sessions[];.providerSessionId==$id and .provenance==null and .nativeMetadata.observedHooks==[])' >/dev/null
done
"$adapter" status codex | jq -e '.state.connectionProven==false' >/dev/null
echo 'PASS Codex native ownership, heartbeat receipts/cleanup, forged callback and app/Claude proof refusal'
