#!/usr/bin/env bash
# Safe owned-handler merge. Configuration is never evidence of runtime trust.
script_dir="${script_dir:?caller supplies the fixed scripts directory}"
adapter_search_path="${adapter_search_path-}"

# Emit a structured failure without changing provider settings.
agent_adapters_error() {
  jq -cn --arg code "$1" --arg message "$2" '{ok:false,state:null,error:{code:$code,message:$message,recovery:"Check adapter configuration and retry the explicit operation."}}'
  return 1
}

# POSIX shell quoting, including apostrophes; paths with controls are rejected.
agent_adapters_command() {
  local provider="${1:-claude}" path="$script_dir/aranea-agent-hook"
  [[ "$path" == /* && ! "$path" =~ [[:cntrl:]] ]] || return 1
  path=${path//\'/\'\\\'\'}
  printf "/usr/bin/env -u BASH_ENV -u ENV -u CDPATH PATH=/usr/bin:/bin /bin/bash '%s' %s" "$path" "$provider"
}

# Search only absolute non-checkout directories, without invoking the provider.
agent_adapters_executable() {
  local provider="${1:-claude}" dir canonical cwd candidate
  cwd=$(pwd -P)
  local -a directories
  IFS=: read -r -a directories <<<"$adapter_search_path"
  for dir in "${directories[@]}"; do
    [[ "$dir" == /* && ! "$dir" =~ [[:cntrl:]] ]] || continue
    canonical=$(realpath -e -- "$dir" 2>/dev/null) || continue
    [[ "$canonical" != "$cwd" && "$canonical" != "$cwd/"* ]] || continue
    candidate="$canonical/$provider"
    if [[ -f "$candidate" && -x "$candidate" ]]; then
      candidate=$(realpath -e -- "$candidate") || continue
      [[ ! "$candidate" =~ [[:cntrl:]] && "$candidate" != "$cwd/"* ]] || continue
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Readiness needs both receipt freshness and current executable/host proof.
agent_adapters_connection_proven() {
  local state="$1" provider="${2:-claude}" evidence
  while IFS= read -r evidence; do
    if agent_hooks_validate_provenance "$evidence" "$provider"; then return 0; fi
  done < <(jq -c --arg provider "$provider" --argjson now "$(date +%s)" --argjson monotonic "$(cut -d. -f1 /proc/uptime)" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" '.state.sessions[]? | select(.provider == $provider and .connection.connected and .connection.bootId == $boot and $now >= .connection.receivedAt and ($now-.connection.receivedAt)<60 and $monotonic >= .connection.monotonic and ($monotonic-.connection.monotonic)<60 and .provenance != null) | .provenance' <<<"$state")
  return 1
}

# Read or explicitly merge/remove only this installation's exact command.
agent_adapters_main() {
  [[ $# == 2 && "$1" =~ ^(status|install|remove)$ && ("$2" == claude || "$2" == codex) ]] || {
    agent_adapters_error ADAPTER_UNSUPPORTED 'Use status, install or remove with claude or codex.'
    return 1
  }
  local action="$1" provider="$2" directory config command content='{}' observed='[]' state='null' executable='' tmp='' mode=600
  if [[ "$provider" == codex ]]; then
    directory="${CODEX_HOME:-$HOME/.codex}"
    config="$directory/hooks.json"
  else
    directory="$HOME/.claude"
    config="$directory/settings.json"
  fi
  [[ "$directory" == /* && ! "$directory" =~ [[:cntrl:]] && ! -L "$directory" && "$HOME" == /* && ! "$HOME" =~ [[:cntrl:]] && ! -L "$config" && ! -L "$config.aranea.lock" && (! -e "$config.aranea.lock" || -f "$config.aranea.lock") ]] || {
    agent_adapters_error UNSAFE_CONFIG_PATH 'Provider settings directory, file and lock must be safe regular paths.'
    return 1
  }
  command=$(agent_adapters_command "$provider") || {
    agent_adapters_error UNSAFE_CONFIG_PATH 'Hook path contains control characters.'
    return 1
  }
  if [[ "$action" != status ]]; then
    umask 077
    mkdir -p -- "$directory" || {
      agent_adapters_error ADAPTER_WRITE_FAILED 'Cannot create provider settings directory.'
      return 1
    }
    [[ ! -L "$config.aranea.lock" && (! -e "$config.aranea.lock" || -f "$config.aranea.lock") ]] || {
      agent_adapters_error UNSAFE_CONFIG_PATH 'Provider settings lock must be a regular file.'
      return 1
    }
    if ! { exec {adapter_lock_fd}>"$config.aranea.lock"; } 2>/dev/null; then
      agent_adapters_error ADAPTER_LOCK_FAILED 'Cannot open Provider settings lock.'
      return 1
    fi
    flock -w 1 -x "$adapter_lock_fd" || {
      agent_adapters_error ADAPTER_LOCK_FAILED 'Provider settings are busy.'
      return 1
    }
  fi
  [[ ! -L "$config" ]] || {
    agent_adapters_error UNSAFE_CONFIG_PATH 'Provider settings became a symlink.'
    return 1
  }
  if [[ -e "$config" ]]; then
    [[ -f "$config" ]] || {
      agent_adapters_error UNSAFE_CONFIG_PATH 'Provider settings must be a regular file.'
      return 1
    }
    content=$(head -c 1048577 -- "$config" | jq -Rces 'if utf8bytelength > 1048576 then error("size") else fromjson end' 2>/dev/null) || {
      agent_adapters_error ADAPTER_CONFIG_INVALID 'Provider settings JSON is malformed or oversized.'
      return 1
    }
    mode=$(stat -c %a -- "$config")
  fi
  jq -e 'type == "object" and ((has("hooks")|not) or (.hooks|type == "object" and all(.[];type == "array" and all(.[];type == "object" and (.hooks|type == "array" and all(.[];type == "object"))))))' <<<"$content" >/dev/null || {
    agent_adapters_error ADAPTER_CONFIG_INVALID 'Provider hook configuration is malformed.'
    return 1
  }
  # Read activity, but a corrupt/unavailable store cannot justify optional hooks.
  if state=$(/bin/bash "$script_dir/aranea-agent-store" snapshot 2>/dev/null); then
    observed=$(jq -c --arg provider "$provider" '[.state.sessions[] | select(.provider == $provider) | .nativeMetadata.observedHooks[]?] | unique' <<<"$state")
  else state=null; fi
  local baseline='["SessionStart","UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","Stop","SessionEnd","Notification"]'
  local optional='["PostToolUseFailure","StopFailure","SubagentStart","SubagentStop","TaskCompleted"]'
  if [[ "$provider" == codex ]]; then
    baseline='["SessionStart","UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","Stop","SessionEnd","SubagentStart","SubagentStop","Interrupt"]'
    optional='[]'
  fi
  local supported
  supported=$(jq -cn --argjson baseline "$baseline" --argjson optional "$optional" --argjson observed "$observed" '$baseline + [$optional[] | select(. as $name | $observed | index($name))]')
  if [[ "$action" == install ]]; then
    content=$(jq -c --arg command "$command" --argjson events "$supported" 'reduce $events[] as $event (. ; if any(.hooks[$event][]?.hooks[]?; .type == "command" and .command == $command) then . else .hooks[$event] = ((.hooks[$event] // []) + [{matcher:"",hooks:[{type:"command",command:$command,timeout:2}]}]) end)' <<<"$content")
  elif [[ "$action" == remove ]]; then
    content=$(jq -c --arg command "$command" 'if has("hooks") then .hooks |= with_entries((.value | any(.[]?.hooks[]?;.type == "command" and .command == $command)) as $hadOwned | .value |= map(. as $group | any(.hooks[]; .type == "command" and .command == $command) as $owned | .hooks |= map(select(.type != "command" or .command != $command)) | select(($owned|not) or (.hooks|length>0))) | select((.value|length>0) or ($hadOwned|not))) else . end' <<<"$content")
  fi
  if [[ "$action" != status ]]; then
    tmp=$(mktemp "$config.aranea.XXXXXX") || {
      agent_adapters_error ADAPTER_WRITE_FAILED 'Cannot create settings replacement.'
      return 1
    }
    # No native text is written here, only the bounded provider settings object.
    if ! printf '%s\n' "$content" >"$tmp" || ! chmod "$mode" "$tmp" || [[ -L "$config" ]] || ! mv -T -- "$tmp" "$config"; then
      rm -f -- "$tmp"
      agent_adapters_error ADAPTER_WRITE_FAILED 'Cannot atomically replace provider settings.'
      return 1
    fi
  fi
  local connection_proven=false
  if agent_adapters_connection_proven "$state" "$provider"; then connection_proven=true; fi
  executable=$(agent_adapters_executable "$provider") || executable=''
  printf '%s\n%s\n' "$content" "$state" | jq -c -s --arg provider "$provider" --arg configPath "$config" --arg command "$command" --arg executable "$executable" --argjson observed "$observed" --argjson baseline "$baseline" --argjson optional "$optional" --argjson connectionProven "$connection_proven" '
    .[0] as $config | .[1] as $runtime |
    [($config.hooks//{}) | to_entries[]? | select(any(.value[]?.hooks[]?;.type == "command" and .command == $command)) | .key] as $installed |
    {ok:true,error:null,state:{provider:$provider,configPath:$configPath,commandAvailable:($executable!=""),executable:(if $executable=="" then null else $executable end),configured:all($baseline[];. as $event|$installed|index($event)!=null),enabled:"unconfirmed",trusted:"unconfirmed",runtimeObserved:($observed|length>0),connectionProven:$connectionProven,installedHooks:$installed,capabilities:{callbackOwnership:{legacySessions:([$runtime.state.sessions[]?|select(.provider==$provider and (.nativeMetadata|has("callbackOwners")|not))]|length),restartRequired:($runtime.state as $live | any($live.sessions[]?;. as $session | .provider==$provider and (.nativeMetadata|has("callbackOwners")|not) and any($live.tasks[]?;.provider==$provider and .providerSessionId==$session.providerSessionId and .producerEpoch==$session.producerEpoch and .freshness!="connection-lost"))),recovery:"Start a new native provider/session epoch to establish private callback ownership; legacy uncorrelated callbacks are refused."},baselineHooks:$baseline,optionalHooks:[$optional[]|. as $event|{event:$event,mapperSupported:true,runtimeObserved:($observed|index($event)!=null),installed:($installed|index($event)!=null),available:($observed|index($event)!=null)}],permissionResolution:"unconfirmed-without-native-tool-id",duplicateDelivery:(if $provider=="codex" then "exact-replay-within-512-receipts; native turn_id required" else "exact-replay-within-512-receipts; native-turn-identity-unavailable-without-prompt_id" end),userInput:(if $provider=="codex" then "unconfirmed-use-explicit-reports" else "AskUserQuestion-and-ExitPlanMode" end),setup:(if $provider=="codex" then "Review and trust the current hooks.json definition in Codex; disabled or managed-only policies may prevent execution. Inline config.toml hooks coexist unchanged. Installation does not prove trust, enabled hooks or CLI session ownership." else "Review provider hook configuration and runtime observations." end),resume:(if $provider=="codex" then "CLI-native-UUID-only; app/server identities unavailable without CLI process proof" else "native-UUID-only" end),fallback:"Use explicit structured reports for unavailable API-error, subagent, completion or tool-failure coverage."}}}'
}
