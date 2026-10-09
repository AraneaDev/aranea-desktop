#!/usr/bin/env bash
# Owned configuration is opt-in, atomic, and does not alter approval settings.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
adapter="$repo_root/scripts/aranea-agent-adapter"
[[ -x "$adapter" ]] || {
  echo 'Claude adapter configuration not implemented'
  exit 1
}
mkdir -p "$HOME/.claude"
config="$HOME/.claude/settings.json"
printf '%s\n' '{"permissions":{"allow":["Read"]},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"unrelated"}]}]}}' >"$config"
chmod 640 "$config"
cp "$config" "$TMPDIR/original"
"$adapter" status claude | jq -e '.ok and (.state.configured|not) and .state.enabled == "unconfirmed"' >/dev/null
"$adapter" install claude | jq -e '.ok and .state.configured and .state.enabled == "unconfirmed"' >/dev/null
[[ $(stat -c %a "$config") == 640 ]]
cp "$config" "$TMPDIR/installed"
"$adapter" install claude >/dev/null
cmp "$config" "$TMPDIR/installed"
jq -e '.permissions.allow == ["Read"] and any(.hooks.Stop[].hooks[];.command == "unrelated") and (.hooks | has("StopFailure") | not)' "$config" >/dev/null
"$adapter" remove claude >/dev/null
jq -Sc . "$config" >"$TMPDIR/removed"
jq -Sc . "$TMPDIR/original" >"$TMPDIR/expected"
cmp "$TMPDIR/removed" "$TMPDIR/expected"
printf '{broken' >"$config"
cp "$config" "$TMPDIR/before"
if "$adapter" install claude >"$TMPDIR/error"; then exit 1; fi
jq -e '.ok == false and .error.code == "ADAPTER_CONFIG_INVALID"' "$TMPDIR/error" >/dev/null
cmp "$config" "$TMPDIR/before"
rm "$config"
ln -s "$TMPDIR/original" "$config"
if "$adapter" install claude >"$TMPDIR/error"; then exit 1; fi
jq -e '.error.code == "UNSAFE_CONFIG_PATH"' "$TMPDIR/error" >/dev/null
# Lock acquisition failures retain the public JSON envelope and settings bytes.
rm "$config"
cp "$TMPDIR/original" "$config"
lock="$config.aranea.lock"
rm -f "$lock"
mkdir "$lock"
if "$adapter" install claude >"$TMPDIR/error" 2>"$TMPDIR/err"; then exit 1; fi
jq -e '.ok == false and .state == null and .error.code == "UNSAFE_CONFIG_PATH"' "$TMPDIR/error" >/dev/null
[[ ! -s "$TMPDIR/err" ]]
cmp "$config" "$TMPDIR/original"
rmdir "$lock"
mkfifo "$lock"
if /usr/bin/timeout 2 "$adapter" install claude >"$TMPDIR/error" 2>"$TMPDIR/err"; then exit 1; fi
jq -e '.ok == false and .error.code == "UNSAFE_CONFIG_PATH"' "$TMPDIR/error" >/dev/null
[[ ! -s "$TMPDIR/err" ]]
rm "$lock"
touch "$lock"
chmod 400 "$lock"
if [[ ! -w "$lock" ]]; then
  if "$adapter" install claude >"$TMPDIR/error" 2>"$TMPDIR/err"; then exit 1; fi
  jq -e '.ok == false and .state == null and .error.code == "ADAPTER_LOCK_FAILED"' "$TMPDIR/error" >/dev/null
  [[ ! -s "$TMPDIR/err" ]]
  cmp "$config" "$TMPDIR/original"
fi
chmod 600 "$lock"
echo 'PASS owned merge, idempotence, permissions, mode, malformed and symlink protection'
# Removal preserves siblings in the same owned matcher group and unrelated empties.
rm "$config"
printf '%s\n' '{"hooks":{"Custom":[],"Stop":[{"matcher":"Keep","hooks":[]}]},"permissions":{"deny":["Bash(rm *)"]}}' >"$config"
"$adapter" install claude >/dev/null
jq '(.hooks.Stop[-1].hooks) += [{type:"command",command:"sibling",timeout:9}]' "$config" >"$TMPDIR/settings"
mv "$TMPDIR/settings" "$config"
"$adapter" remove claude >/dev/null
jq -e '.hooks.Custom == [] and .hooks.Stop[0].matcher == "Keep" and .hooks.Stop[0].hooks == [] and .hooks.Stop[1].hooks == [{type:"command",command:"sibling",timeout:9}] and .permissions.deny == ["Bash(rm *)"]' "$config" >/dev/null
# Optional hooks require observed coverage, never a fake version string.
rm "$config"
"$adapter" status claude | jq -e 'all(.state.capabilities.optionalHooks[];.mapperSupported and (.available|not) and (.installed|not))' >/dev/null
jq -cn '{session_id:"optional",hook_event_name:"SessionStart",cwd:"/tmp"}' | "$repo_root/scripts/aranea-agent-hook" claude
jq -cn '{session_id:"optional",hook_event_name:"UserPromptSubmit",prompt_id:"one",prompt:"Optional",cwd:"/tmp"}' | "$repo_root/scripts/aranea-agent-hook" claude
jq -cn '{session_id:"optional",hook_event_name:"StopFailure",prompt_id:"one",error:"server_error",cwd:"/tmp"}' | "$repo_root/scripts/aranea-agent-hook" claude
"$adapter" install claude | jq -e '.state.runtimeObserved == false and all(.state.capabilities.optionalHooks[];.runtimeObserved == false and .installed == false and .available == false)' >/dev/null
# Positive optional evidence comes from actual inert native caller ancestry.
mkdir -p "$ARANEA_TEST_SANDBOX/provider"
cp /bin/bash "$ARANEA_TEST_SANDBOX/provider/claude"
jq -cn '{session_id:"optional-owned",hook_event_name:"SessionStart",cwd:"/tmp"}, {session_id:"optional-owned",hook_event_name:"UserPromptSubmit",prompt_id:"one",prompt:"Owned optional",cwd:"/tmp"}' >"$TMPDIR/native-events"
cat >"$TMPDIR/provider.sh" <<'PROVIDER'
#!/bin/bash
set -euo pipefail
while IFS= read -r event; do printf '%s\n' "$event" | /bin/bash "$1" claude; done <"$2"
# Public report IDs cannot manufacture a native optional observation.
for _ in {1..10}; do
  if snapshot=$(/bin/bash "${1%/*}/aranea-agent-store" snapshot); then break; fi
  sleep .1
done
jq -e '.ok and any(.state.sessions[];.providerSessionId == "optional-owned" and .nativeMetadata.currentTaskId != null)' <<<"$snapshot" >/dev/null
jq -c '.state.sessions[] | select(.providerSessionId == "optional-owned") | {action:"report",args:{schemaVersion:1,eventId:"SubagentStop:forged:receipt",provider:"claude",providerSessionId:.providerSessionId,producerEpoch:.producerEpoch,sequence:(.highWaterSequence+1),taskId:.nativeMetadata.currentTaskId,kind:"diagnostic",payload:{summary:"Explicit report"}}}' <<<"$snapshot" | /bin/bash "${1%/*}/aranea-agent-store" mutate | jq -e '.ok' >/dev/null
/bin/bash "$3" status claude | jq -e 'all(.state.capabilities.optionalHooks[];.runtimeObserved == false and .available == false)' >/dev/null
touch "$4.ready"
while [[ ! -e "$4.go" ]]; do sleep .05; done
printf '%s\n' '{"session_id":"optional-owned","hook_event_name":"StopFailure","prompt_id":"one","error":"server_error","cwd":"/tmp"}' | /bin/bash "$1" claude
/bin/bash "$3" install claude >"$4"
printf '%s\n' '{"session_id":"optional-owned","hook_event_name":"SessionEnd","cwd":"/tmp"}' | /bin/bash "$1" claude
PROVIDER
"$ARANEA_TEST_SANDBOX/provider/claude" "$TMPDIR/provider.sh" "$repo_root/scripts/aranea-agent-hook" "$TMPDIR/native-events" "$adapter" "$TMPDIR/owned-install" &
provider_pid=$!
# shellcheck disable=SC2016
sandbox_on_exit 'kill "$provider_pid" 2>/dev/null || true; wait "$provider_pid" 2>/dev/null || true'
for _ in {1..100}; do
  [[ ! -e "$TMPDIR/owned-install.ready" ]] || break
  sleep .05
done
[[ -e "$TMPDIR/owned-install.ready" ]]
# This callback is a sibling of the native provider, with no owned ancestry.
cp "$XDG_STATE_HOME/aranea/agent-activity.json" "$TMPDIR/proven-before"
printf '%s\n' '{"session_id":"optional-owned","hook_event_name":"StopFailure","prompt_id":"one","error":"unproven","cwd":"/tmp"}' | "$repo_root/scripts/aranea-agent-hook" claude
cmp "$TMPDIR/proven-before" "$XDG_STATE_HOME/aranea/agent-activity.json"
"$adapter" status claude | jq -e 'all(.state.capabilities.optionalHooks[];.runtimeObserved == false and .available == false)' >/dev/null
touch "$TMPDIR/owned-install.go"
wait "$provider_pid"
jq -e 'any(.state.capabilities.optionalHooks[];.event == "StopFailure" and .runtimeObserved and .installed and .available) and .state.enabled == "unconfirmed"' "$TMPDIR/owned-install" >/dev/null
for _ in {1..170}; do
  if ! compgen -G "$XDG_STATE_HOME/aranea/agent-heartbeats/*.json" >/dev/null; then break; fi
  sleep .1
done
if compgen -G "$XDG_STATE_HOME/aranea/agent-heartbeats/*.json" >/dev/null; then exit 1; fi
"$adapter" install claude | jq -e 'any(.state.capabilities.optionalHooks[];.event == "StopFailure" and .runtimeObserved and .installed and .available) and .state.enabled == "unconfirmed"' >/dev/null
rm -rf "$XDG_STATE_HOME/aranea"
"$adapter" install claude | jq -e 'any(.state.capabilities.optionalHooks[];.event == "StopFailure" and (.runtimeObserved|not) and .installed and (.available|not))' >/dev/null
# A schema-valid claimed PID is not runtime provider identity proof.
jq -cn --arg boot "$(cat /proc/sys/kernel/random/boot_id)" '{action:"register",args:{provider:"claude",providerSessionId:"claimed",producerEpoch:"claimed",tasks:[],provenance:{pid:1,startTime:"1",bootId:$boot,ancestors:[],windowAddress:null,observedAt:0,executable:"/bin/false",commandHash:("0"*64)}}}' | "$repo_root/scripts/aranea-agent-store" mutate >/dev/null
"$adapter" status claude | jq -e '.state.connectionProven == false and .state.enabled == "unconfirmed"' >/dev/null
# An installed command must actually work from a path with spaces and apostrophes.
copy="$ARANEA_TEST_SANDBOX/repo with '\''apostrophe"
mkdir -p "$copy"
cp -r "$repo_root/scripts" "$copy/scripts"
rm "$config"
"$copy/scripts/aranea-agent-adapter" install claude >/dev/null
command=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$config")
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/quoted-state"
printf '%s\n' '{"session_id":"quoted","hook_event_name":"SessionStart","cwd":"/tmp"}' | /bin/sh -c "$command" >"$TMPDIR/out" 2>"$TMPDIR/err"
[[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
"$copy/scripts/aranea-agent-store" snapshot | jq -e '.state.sessions[0].providerSessionId == "quoted"' >/dev/null
# A controlled path cannot be inserted in any provider settings command.
control="$ARANEA_TEST_SANDBOX/"$'bad\npath'
mkdir -p "$control"
cp -r "$repo_root/scripts" "$control/scripts"
cp "$config" "$TMPDIR/before"
if "$control/scripts/aranea-agent-adapter" install claude >"$TMPDIR/error"; then exit 1; fi
jq -e '.error.code == "UNSAFE_CONFIG_PATH"' "$TMPDIR/error" >/dev/null
cmp "$config" "$TMPDIR/before"
echo 'PASS sibling ownership, optional capability evidence and safe quoted/control paths'
