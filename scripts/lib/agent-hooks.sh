#!/usr/bin/env bash
# Native mapping runs with the store lock held. Never trust payload/caller PIDs.
script_dir="${script_dir:?caller supplies the fixed scripts directory}"

# Read the kernel identity without assuming the comm field contains no spaces.
agent_hooks_process() {
  local pid="$1" raw tail
  [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/stat" ]] || return 1
  IFS= read -r raw <"/proc/$pid/stat" || return 1
  tail=${raw##*) }
  local -a fields
  read -r -a fields <<<"$tail"
  [[ ${fields[0]} != Z && ${fields[19]:-} =~ ^[0-9]+$ ]] || return 1
  printf '%s %s\n' "${fields[1]}" "${fields[19]}"
}

# Match the actual executable and command line, never a claimed payload name.
agent_hooks_provider_process() {
  local pid="$1" provider="${2:-}" exe cwd entry arg
  local -a argv
  agent_hooks_process "$pid" >/dev/null || return 1
  exe=$(readlink -f -- "/proc/$pid/exe") || return 1
  cwd=$(readlink -f -- "/proc/$pid/cwd") || return 1
  argv=()
  mapfile -d '' -t argv <"/proc/$pid/cmdline" || return 1
  [[ ${#argv[@]} -gt 0 && "$exe" != "$cwd/"* ]] || return 1
  if [[ "$provider" != claude && ${argv[0]##*/} == codex ]]; then
    # The app server multiplexes sessions; its ancestry does not own a CLI turn.
    for arg in "${argv[@]:1}"; do [[ "$arg" != app-server ]] || return 1; done
    if [[ ${exe##*/} == codex ]]; then return 0; fi
    [[ ${argv[0]} == /* ]] || return 1
    entry=$(realpath -e -- "${argv[0]}") || return 1
    [[ "$entry" == "$exe" ]]
  elif [[ "$provider" != codex && ${argv[0]##*/} == claude ]]; then
    if [[ ${exe##*/} == claude ]]; then return 0; fi
    # Native installers may use an absolute claude symlink to a versioned binary.
    [[ ${argv[0]} == /* ]] || return 1
    entry=$(realpath -e -- "${argv[0]}") || return 1
    [[ "$entry" == "$exe" ]]
  elif [[ "$provider" != codex && ${exe##*/} == node && ${argv[1]:-} == /*/node_modules/@anthropic-ai/claude-code/cli.js ]]; then
    entry=$(realpath -e -- "${argv[1]}") || return 1
    [[ -f "$entry" && "$entry" != "$cwd/"* ]]
  else return 1; fi
}

# SHA256(executable UTF-8 + NUL + device:inode UTF-8 + NUL + raw cmdline bytes).
# Raw arguments are streamed into the digest and never written to state or files.
agent_hooks_command_hash() {
  local pid="$1" exe identity hash
  exe=$(readlink -f -- "/proc/$pid/exe") || return 1
  identity=$(stat -L -c '%d:%i' -- "/proc/$pid/exe") || return 1
  hash=$({
    printf '%s\0%s\0' "$exe" "$identity"
    cat "/proc/$pid/cmdline"
  } | sha256sum | cut -d' ' -f1) || return 1
  [[ "$exe" == "$(readlink -f -- "/proc/$pid/exe")" ]] || return 1
  printf '%s\n' "$hash"
}

# Only an actual ancestor with an approved executable/entrypoint is a provider.
agent_hooks_provenance() {
  local provider="${1:-}" pid=$$ parent start count=0 ancestors='[]' boot
  boot=$(cat /proc/sys/kernel/random/boot_id)
  while ((pid > 1 && count < 32)); do
    read -r parent start < <(agent_hooks_process "$pid") || break
    if agent_hooks_provider_process "$pid" "$provider"; then
      # Keep the provider and its bounded host ancestry, never environment data.
      local provider_pid=$pid provider_start=$start executable command_hash
      executable=$(readlink -f -- "/proc/$pid/exe") || return 1
      command_hash=$(agent_hooks_command_hash "$pid") || return 1
      while ((parent > 1 && count < 32)); do
        pid=$parent
        read -r parent start < <(agent_hooks_process "$pid") || break
        ancestors=$(jq -c --argjson pid "$pid" --arg start "$start" '.+[{pid:$pid,startTime:$start}]' <<<"$ancestors")
        count=$((count + 1))
      done
      jq -cn --argjson pid "$provider_pid" --arg start "$provider_start" --arg boot "$boot" --argjson ancestors "$ancestors" --arg executable "$executable" --arg hash "$command_hash" '{executable:$executable,commandHash:$hash,pid:$pid,startTime:$start,bootId:$boot,ancestors:$ancestors,windowAddress:null,observedAt:0}'
      return 0
    fi
    pid=$parent
    count=$((count + 1))
  done
  printf 'null\n'
}

# Public read-only proof for later navigation: current provider and host identities.
# A compositor window must still be independently proved by the desktop owner.
agent_hooks_validate_provenance() {
  local evidence="$1" provider="${2:-}" pid expected parent start item
  [[ "$evidence" != null && $(jq -r .bootId <<<"$evidence") == "$(cat /proc/sys/kernel/random/boot_id)" ]] || return 1
  pid=$(jq -r .pid <<<"$evidence")
  expected=$(jq -r .startTime <<<"$evidence")
  read -r parent start < <(agent_hooks_process "$pid") || return 1
  [[ "$start" == "$expected" ]] && agent_hooks_provider_process "$pid" "$provider" || return 1
  [[ "$(jq -r .executable <<<"$evidence")" == "$(readlink -f -- "/proc/$pid/exe")" && "$(jq -r .commandHash <<<"$evidence")" == "$(agent_hooks_command_hash "$pid")" ]] || return 1
  while IFS= read -r item; do
    [[ "$(jq -r .pid <<<"$item")" == "$parent" ]] || return 1
    read -r parent start < <(agent_hooks_process "$(jq -r .pid <<<"$item")") || return 1
    [[ "$start" == "$(jq -r .startTime <<<"$item")" ]] || return 1
  done < <(jq -c '.ancestors[]' <<<"$evidence")
}

# Helpers must themselves occur in actual ancestry with the exact fixed argv.
agent_hooks_helper_proof() {
  local provider="$1" session="$2" epoch="$3" evidence="$4" pid=$$ parent start provider_start count=0
  local -a argv
  agent_hooks_validate_provenance "$evidence" "$provider" || return 1
  provider_start=$(jq -r .startTime <<<"$evidence")
  local root key identity
  root="$(aranea_state_root)/agent-heartbeats"
  key=$(printf '%s\n' "$provider" "$session" "$epoch" | sha256sum | cut -d' ' -f1)
  identity="$root/$key.json"
  [[ ! -L "$root" && ! -L "$identity" && -f "$identity" ]] || return 1
  while ((pid > 1 && count < 32)); do
    read -r parent start < <(agent_hooks_process "$pid") || return 1
    argv=()
    mapfile -d '' -t argv <"/proc/$pid/cmdline" || return 1
    if [[ ${argv[0]:-} == /bin/bash && ${argv[1]:-} == "$script_dir/aranea-agent-heartbeat" && ${#argv[@]} == 8 &&
      ${argv[2]} == "$provider" && ${argv[3]} == "$session" && ${argv[4]} == "$epoch" &&
      ${argv[5]} == "$(jq -r .pid <<<"$evidence")" && ${argv[6]} == "$provider_start" && ${argv[7]} == "$(jq -r .bootId <<<"$evidence")" ]]; then
      [[ $(readlink -f -- "/proc/$pid/exe") == "$(readlink -f /bin/bash)" ]] || return 1
      # Command substitutions can retain helper argv in an intermediate shell.
      # Only the PID/start-time owner record identifies the actual helper.
      if jq -e --argjson pid "$pid" --arg start "$start" --arg provider "$provider" --arg session "$session" --arg epoch "$epoch" --argjson evidence "$evidence" '.pid == $pid and .startTime == $start and .provider == $provider and .providerSessionId == $session and .producerEpoch == $epoch and .providerProcess.pid == $evidence.pid and .providerProcess.startTime == $evidence.startTime and .bootId == $evidence.bootId' "$identity" >/dev/null; then return 0; fi
    fi
    pid=$parent
    count=$((count + 1))
  done
  return 1
}

# Allocate epoch, turn and sequence from the current locked state, including replay.
agent_hooks_prepare_request() {
  local request="$1" state="$2" context="$3" provider proof session epoch evidence fingerprint normalized candidate hash callback_key event_digest
  provider=$(jq -r .args.provider <<<"$request")
  [[ "$provider" == claude || "$provider" == codex ]] || return 1
  if [[ $(jq -r .args.payload.hook_event_name <<<"$request") == AraneaHeartbeat ]]; then
    session=$(jq -r .args.payload.session_id <<<"$request")
    epoch=$(jq -r .args.payload.producer_epoch <<<"$request")
    evidence=$(jq -c --arg provider "$provider" --arg session "$session" --arg epoch "$epoch" '.sessions[] | select(.provider == $provider and .providerSessionId == $session and .producerEpoch == $epoch and .connection.connected) | .provenance' <<<"$state")
    [[ -n "$evidence" && "$evidence" != null ]] || return 1
    agent_hooks_helper_proof "$provider" "$session" "$epoch" "$evidence" || return 1
    proof=$evidence
  else
    proof=$(agent_hooks_provenance "$provider") || return 1
    if [[ "$proof" != null ]]; then agent_hooks_validate_provenance "$proof" "$provider" || return 1; fi
  fi
  fingerprint=$(jq -Sc .args.payload <<<"$request" | sha256sum | cut -d' ' -f1)
  callback_key=$(jq -Sc --arg fingerprint "$fingerprint" '
    def native_id: type == "string" and length>0 and length<=180 and (test("[\\x00-\\x1f\\x7f]")|not);
    .args.provider as $provider | .args.payload | [.hook_event_name,
      (if .hook_event_name == "PermissionRequest" or .hook_event_name == "Notification" then "fingerprint:"+$fingerprint
       elif (.hook_event_name|IN("PreToolUse","PostToolUse","PostToolUseFailure")) then
         if (.tool_use_id|native_id) then "tool:"+.tool_use_id else "fingerprint:"+$fingerprint end
       elif .hook_event_name == "TaskCompleted" and (.task_id|native_id) then "task:"+.task_id
       elif (.agent_id|native_id) then "agent:"+.agent_id
       elif $provider == "codex" and (.turn_id|native_id) then "turn:"+.turn_id
       elif $provider == "claude" and (.prompt_id|native_id) then "prompt:"+.prompt_id
       else "fingerprint:"+$fingerprint end)]' <<<"$request" | sha256sum | cut -d' ' -f1)
  normalized=$(printf '%s\n%s\n%s\n%s\n' "$request" "$state" "$context" "$proof" | jq -c -s --arg fingerprint "$fingerprint" --arg callbackKey "$callback_key" -f "$script_dir/lib/agent-hooks.jq") || return 1
  if [[ $(jq -r .args.eventId <<<"$normalized") == "pending:$callback_key" ]]; then
    event_digest=$(jq -Sc --arg key "$callback_key" '[$key,.args.taskId]' <<<"$normalized" | sha256sum | cut -d' ' -f1)
    normalized=$(jq -c --arg key "$callback_key" --arg eventId "$(jq -r .args.payload.hook_event_name <<<"$request"):$event_digest" '.args.eventId=$eventId | .nativeMetadata.callbackOwners |= map(if .key == $key then .eventId=$eventId else . end)' <<<"$normalized")
  fi
  # A resolved failure replay has no remaining blocker. Only its exact retained
  # canonical receipt authorizes replay of that resolution; otherwise diagnostic.
  if [[ $(jq -r .args.payload.hook_event_name <<<"$request") == PostToolUseFailure && $(jq -r .args.kind <<<"$normalized") == diagnostic ]] && jq -e '.args.payload | (.tool_name == "AskUserQuestion" or .tool_name == "ExitPlanMode") and (.tool_use_id|type == "string" and length > 0 and length <= 180 and (test("[\\x00-\\x1f\\x7f]")|not))' <<<"$request" >/dev/null; then
    # Keep native input outside jq's argv and use the same receipt hash as store.
    candidate=$(printf '%s\n%s\n' "$normalized" "$request" | jq -cs '.[1].args.payload.tool_use_id as $id | .[0] | .args.kind="blocker-resolved" | .args.payload={blockerId:("tool:"+$id),summary:.args.payload.summary}')
    hash=$(jq -Sc 'del(.nativeMetadata)' <<<"$candidate" | sha256sum | cut -d' ' -f1)
    if agent_activity_is_replay "$candidate" "$state" "$hash"; then normalized=$candidate; fi
  fi
  printf '%s\n' "$normalized"
}
