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
  local path="$script_dir/aranea-agent-hook"
  [[ "$path" == /* && ! "$path" =~ [[:cntrl:]] ]] || return 1
  path=${path//\'/\'\\\'\'}
  printf "/usr/bin/env -u BASH_ENV -u ENV -u CDPATH PATH=/usr/bin:/bin /bin/bash '%s' claude" "$path"
}

# Search only absolute non-checkout directories, without invoking the provider.
agent_adapters_executable() {
  local dir canonical cwd candidate
  cwd=$(pwd -P)
  local -a directories
  IFS=: read -r -a directories <<<"$adapter_search_path"
  for dir in "${directories[@]}"; do
    [[ "$dir" == /* && ! "$dir" =~ [[:cntrl:]] ]] || continue
    canonical=$(realpath -e -- "$dir" 2>/dev/null) || continue
    [[ "$canonical" != "$cwd" && "$canonical" != "$cwd/"* ]] || continue
    candidate="$canonical/claude"
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
  local state="$1" evidence
  while IFS= read -r evidence; do
    if agent_hooks_validate_provenance "$evidence"; then return 0; fi
  done < <(jq -c --argjson now "$(date +%s)" --argjson monotonic "$(cut -d. -f1 /proc/uptime)" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" '.state.sessions[]? | select(.provider == "claude" and .connection.connected and .connection.bootId == $boot and $now >= .connection.receivedAt and ($now-.connection.receivedAt)<60 and $monotonic >= .connection.monotonic and ($monotonic-.connection.monotonic)<60 and .provenance != null) | .provenance' <<<"$state")
  return 1
}

# Read or explicitly merge/remove only this installation's exact command.
agent_adapters_main() {
  [[ $# == 2 && "$1" =~ ^(status|install|remove)$ && "$2" == claude ]] || {
    agent_adapters_error ADAPTER_UNSUPPORTED 'Use status, install or remove with claude.'
    return 1
  }
  local action="$1" config="$HOME/.claude/settings.json" command content='{}' observed='[]' state='null' executable='' tmp='' mode=600
  [[ "$HOME" == /* && ! "$HOME" =~ [[:cntrl:]] && ! -L "$HOME/.claude" && ! -L "$config" && ! -L "$config.aranea.lock" ]] || {
    agent_adapters_error UNSAFE_CONFIG_PATH 'Claude settings directory, file and lock must be safe regular paths.'
    return 1
  }
  command=$(agent_adapters_command) || {
    agent_adapters_error UNSAFE_CONFIG_PATH 'Hook path contains control characters.'
    return 1
  }
  if [[ "$action" != status ]]; then
    umask 077
    mkdir -p -- "$HOME/.claude" || {
      agent_adapters_error ADAPTER_WRITE_FAILED 'Cannot create Claude settings directory.'
      return 1
    }
    exec {adapter_lock_fd}>"$config.aranea.lock"
    flock -w 1 -x "$adapter_lock_fd" || {
      agent_adapters_error ADAPTER_LOCK_FAILED 'Claude settings are busy.'
      return 1
    }
  fi
  [[ ! -L "$config" ]] || {
    agent_adapters_error UNSAFE_CONFIG_PATH 'Claude settings became a symlink.'
    return 1
  }
  if [[ -e "$config" ]]; then
    [[ -f "$config" ]] || {
      agent_adapters_error UNSAFE_CONFIG_PATH 'Claude settings must be a regular file.'
      return 1
    }
    content=$(head -c 1048577 -- "$config" | jq -Rces 'if utf8bytelength > 1048576 then error("size") else fromjson end' 2>/dev/null) || {
      agent_adapters_error ADAPTER_CONFIG_INVALID 'Claude settings JSON is malformed or oversized.'
      return 1
    }
    mode=$(stat -c %a -- "$config")
  fi
  jq -e 'type == "object" and ((has("hooks")|not) or (.hooks|type == "object" and all(.[];type == "array" and all(.[];type == "object" and (.hooks|type == "array" and all(.[];type == "object"))))))' <<<"$content" >/dev/null || {
    agent_adapters_error ADAPTER_CONFIG_INVALID 'Claude hook configuration is malformed.'
    return 1
  }
  # Read activity, but a corrupt/unavailable store cannot justify optional hooks.
  if state=$(/bin/bash "$script_dir/aranea-agent-store" snapshot 2>/dev/null); then
    observed=$(jq -c '[.state.sessions[] | select(.provider == "claude") | .nativeMetadata.observedHooks[]?] | unique' <<<"$state")
  else state=null; fi
  local baseline='["SessionStart","UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","Stop","SessionEnd","Notification"]'
  local optional='["PostToolUseFailure","StopFailure","SubagentStart","SubagentStop","TaskCompleted"]'
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
      agent_adapters_error ADAPTER_WRITE_FAILED 'Cannot atomically replace Claude settings.'
      return 1
    fi
  fi
  local connection_proven=false
  if agent_adapters_connection_proven "$state"; then connection_proven=true; fi
  executable=$(agent_adapters_executable) || executable=''
  printf '%s\n%s\n' "$content" "$state" | jq -c -s --arg command "$command" --arg executable "$executable" --argjson observed "$observed" --argjson baseline "$baseline" --argjson optional "$optional" --argjson connectionProven "$connection_proven" '
    .[0] as $config | .[1] as $runtime |
    [($config.hooks//{}) | to_entries[]? | select(any(.value[]?.hooks[]?;.type == "command" and .command == $command)) | .key] as $installed |
    {ok:true,error:null,state:{provider:"claude",commandAvailable:($executable!=""),executable:(if $executable=="" then null else $executable end),configured:all($baseline[];. as $event|$installed|index($event)!=null),enabled:"unconfirmed",trusted:"unconfirmed",runtimeObserved:($observed|length>0),connectionProven:$connectionProven,installedHooks:$installed,capabilities:{baselineHooks:$baseline,optionalHooks:[$optional[]|. as $event|{event:$event,mapperSupported:true,runtimeObserved:($observed|index($event)!=null),installed:($installed|index($event)!=null),available:($observed|index($event)!=null)}],permissionResolution:"unconfirmed-without-native-tool-id",duplicateDelivery:"exact-replay-within-512-receipts; native-turn-identity-unavailable-without-prompt_id",fallback:"Use explicit structured reports for unavailable API-error, subagent, completion or tool-failure coverage."}}}'
}
