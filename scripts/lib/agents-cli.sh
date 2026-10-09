#!/usr/bin/env bash
# Public activity syntax and JSONL observation; store/owner retain all authority.
# Public envelope variables are consumed by projects-cli.sh.
# shellcheck disable=SC2154,SC2034

# Loss of an accepted owner is uncertainty about running work, never launch failure.
agents_cli_fail() {
  if [[ "$1" == OPERATION_LOST && -n "${cli_operation_id:-}" ]]; then
    local data
    data=$(jq -cn --arg recovery "$3" '{recovery:$recovery}')
    projects_cli_event recovery action_required '' "$3" "$1" "$data"
    projects_cli_finish partial "$1" "$2" "$data" 1
  fi
  projects_cli_fail "$@"
}

# Bounded printable non-option IDs cannot become executable flags.
agents_cli_id() {
  [[ -n "$1" && ${#1} -le 256 && "$1" != -* && "$1" != [[:space:]]* && ! "$1" =~ [[:cntrl:]] ]]
}

# Read headless activity without requiring a desktop owner.
agents_cli_store() {
  local response
  if response=$("$script_dir/aranea-agent-store" "$@"); then
    cli_state=$(jq -c .state <<<"$response")
  else projects_cli_internal_error "$response"; fi
}

# Accepted observer exits never cancel or resubmit work.
agents_cli_cancel() {
  trap '' INT TERM
  agents_cli_fail OBSERVER_CANCELLED 'Stopped observing; accepted activity work continues.' "Reconnect with aranea agents operation $cli_operation_id --json."
}

# Poll the exact accepted operation ID with a bounded transport and stable owner lifetime.
agents_cli_observe() {
  local cli_deadline=$((SECONDS + 30)) response owner=${cli_owner_id:-} outcome code
  trap agents_cli_cancel INT TERM
  while ((SECONDS < cli_deadline)); do
    if ! response=$(projects_cli_ipc aranea.activity operation "$cli_operation_id"); then
      agents_cli_fail OWNER_UNAVAILABLE 'Activity owner observation disconnected; accepted work is unconfirmed.' "Reconnect with aranea agents operation $cli_operation_id --json."
    fi
    if ! jq -e --arg id "$cli_operation_id" 'type=="object" and .id==$id and (.ownerId|type=="string" and length>0) and (.steps|type=="array")' <<<"$response" >/dev/null 2>&1; then
      agents_cli_fail OPERATION_LOST 'The accepted activity operation is no longer retained.' 'Inspect current activity; never automatically resubmit accepted work.'
    fi
    if [[ -n "$owner" && $(jq -r .ownerId <<<"$response") != "$owner" ]]; then agents_cli_fail OPERATION_LOST 'Activity owner lifetime changed.' 'Inspect current activity before a new explicit action.'; fi
    owner=$(jq -r .ownerId <<<"$response")
    if [[ $(jq -r .state <<<"$response") == completed ]]; then
      outcome=$(jq -r .outcome <<<"$response")
      [[ "$outcome" == observed || "$outcome" == partial || "$outcome" == failed ]] || agents_cli_fail OPERATION_LOST 'Invalid owner outcome.' 'Inspect current activity.'
      code=$(jq -r '.error.code // ""' <<<"$response")
      local exit_code=1
      [[ "$outcome" != observed ]] || exit_code=0
      [[ "$code" != TOOL_CHOICE_REQUIRED ]] || exit_code=3
      [[ "$code" != DEPENDENCY_MISSING ]] || exit_code=4
      projects_cli_finish "$outcome" "$code" 'Activity operation completed.' "$(jq -c '{operation:.}' <<<"$response")" "$exit_code"
    fi
    sleep .25
  done
  agents_cli_fail OBSERVATION_TIMEOUT 'Activity observation timed out; accepted work continues.' "Reconnect with aranea agents operation $cli_operation_id --json."
}

# Submit once except explicit rejected readiness; reobserve never submits an action.
agents_cli_submit() {
  local method=$1 payload=$2 response cli_deadline=$((SECONDS + 5))
  while :; do
    if ! response=$(projects_cli_ipc aranea.activity "$method" "$payload"); then agents_cli_fail OWNER_UNAVAILABLE 'Activity owner IPC unavailable; acceptance is unknown.' 'Activate Aranea and inspect activity before another explicit action.'; fi
    if jq -e '.ok==true and (.operationId|type=="string" and length>0) and (.ownerId|type=="string" and length>0)' <<<"$response" >/dev/null 2>&1; then
      local accepted
      accepted=$(jq -r .operationId <<<"$response")
      if [[ "$method" == reobserve && "$accepted" != "$cli_operation_id" ]]; then agents_cli_fail OPERATION_LOST 'Reobserve returned a different operation.' 'Inspect current activity.'; fi
      cli_operation_id=$accepted
      cli_owner_id=$(jq -r .ownerId <<<"$response")
      projects_cli_event step accepted "$cli_operation_id" 'Owner accepted activity operation.' '' "$response"
      return
    fi
    if [[ "$method" == request ]] && ((SECONDS < cli_deadline)) && jq -e '.ok==false and .operationId==null and .error.code=="OWNER_NOT_READY"' <<<"$response" >/dev/null 2>&1; then
      sleep .15
      continue
    fi
    projects_cli_internal_error "$response"
  done
}

# Capability fragment extends rather than replaces Phase 1 operation schemas.
agents_cli_capabilities() {
  local adapter=null
  adapter=$("$script_dir/aranea-agent-adapter" status claude 2>/dev/null | jq -c '.state // null') || adapter=null
  jq -cn --argjson adapter "$adapter" '{activity:{schemaVersion:1,providers:["claude"],unsupportedProviders:["codex"],adapter:$adapter,heartbeatSeconds:15,connectionLostSeconds:60,maxLiveTasks:200,maxInactiveTasks:500,inactiveRetentionDays:14,focusScope:"hosting-terminal",resumeIdentity:"native-uuid",actions:["focus","reopen","open-checkout"],reobserve:"same-operation-read-only",desktopDismiss:"owner-serialized-store-mutation"},operations:[
    {name:"agents.status",arguments:{}},{name:"agents.list",arguments:{}},
    {name:"agents.inspect",arguments:{taskId:{type:"string",required:true}}},
    {name:"agents.register",arguments:{"json-input":{type:"boolean",required:true}}},
    {name:"agents.report",arguments:{"json-input":{type:"boolean",required:true}}},
    {name:"agents.focus",arguments:{taskId:{type:"string",required:true}}},
    {name:"agents.reopen",arguments:{taskId:{type:"string",required:true}}},
    {name:"agents.open-checkout",arguments:{taskId:{type:"string",required:true}}},
    {name:"agents.dismiss",arguments:{taskId:{type:"string",required:true}}},
    {name:"agents.operation",arguments:{operationId:{type:"string",required:true},reobserve:{type:"boolean"}}},
    {name:"agents.adapter",arguments:{action:{enum:["status","install","remove"],required:true},provider:{enum:["claude"],required:true}}}]}'
}

# Validate complete syntax before store mutations, IPC or adapter configuration.
agents_cli_main() {
  cli_json=false cli_operation=agents cli_operation_id='' cli_owner_id='' cli_state=''
  local arg command id='' reobserve=false json_input=false response event body
  local -a words=()
  for arg in "$@"; do
    if [[ "$arg" == --json ]]; then cli_json=true; else words+=("$arg"); fi
  done
  if ! command -v jq >/dev/null 2>&1; then
    [[ "$cli_json" != true ]] || echo '{"schema":1,"event":"completed","operation":"agents","status":"failed","code":"DEPENDENCY_MISSING","data":{"outcome":"failed","recovery":"Install jq."}}'
    echo 'Install jq to use activity commands.' >&2
    exit 4
  fi
  ((${#words[@]} >= 1)) || projects_cli_usage
  command=${words[0]}
  cli_operation="agents.$command"
  case "$command" in
    status | list) ((${#words[@]} == 1)) || projects_cli_usage ;;
    inspect | dismiss | focus | reopen | open-checkout)
      ((${#words[@]} == 2)) || projects_cli_usage
      id=${words[1]}
      agents_cli_id "$id" || projects_cli_usage
      ;;
    operation)
      ((${#words[@]} == 2 || ${#words[@]} == 3)) || projects_cli_usage
      cli_operation_id=${words[1]}
      agents_cli_id "$cli_operation_id" || projects_cli_usage
      if ((${#words[@]} == 3)); then
        [[ ${words[2]} == --reobserve ]] || projects_cli_usage
        reobserve=true
      fi
      ;;
    report | register)
      ((${#words[@]} == 2)) && [[ ${words[1]} == --json-input ]] || projects_cli_usage
      json_input=true
      ;;
    adapter) ((${#words[@]} == 3)) && [[ ${words[1]} == status || ${words[1]} == install || ${words[1]} == remove ]] && [[ ${words[2]} == claude ]] || projects_cli_usage ;;
    *) projects_cli_usage ;;
  esac
  case "$command" in
    status | list | inspect)
      agents_cli_store snapshot
      if [[ "$command" == inspect ]]; then
        response=$(jq -c --arg id "$id" '[.tasks[]|select(.taskId==$id)][0] // null' <<<"$cli_state")
        [[ "$response" != null ]] || agents_cli_fail TASK_NOT_FOUND 'Task not found.' 'List current activity and select a retained task.'
        body=$(jq -cn --argjson task "$response" '{task:$task}')
      else body=$(jq -cn --argjson state "$cli_state" '{state:$state,tasks:$state.tasks}'); fi
      projects_cli_finish observed '' 'Activity snapshot.' "$body"
      ;;
    report | register)
      [[ "$json_input" == true ]] || projects_cli_usage
      # Read one bounded raw event directly through jq so NUL and duplicate values fail validation.
      event=$(head -c 1048577 | jq -Rcse 'if utf8bytelength<=1048576 then fromjson | if type=="object" then . else error("one event") end else error("too large") end' 2>/dev/null) || agents_cli_fail INVALID_REQUEST 'Provide one bounded event object on stdin.' 'Use the schema1 activity event contract.'
      ((${#event} <= 1048576)) || agents_cli_fail REQUEST_TOO_LARGE 'Activity event exceeds one MiB.' 'Send a bounded structured report.'
      if [[ "$command" == register ]] && ! jq -e '.provenance==null' <<<"$event" >/dev/null; then
        agents_cli_fail INVALID_REQUEST 'Explicit registration cannot claim native process provenance.' 'Omit provenance or set it to null; native hooks own native evidence.'
      fi
      response=$(jq -cn --arg action "$command" --argjson event "$event" '{action:$action,args:$event}' | "$script_dir/aranea-agent-store" mutate) || {
        if [[ $(jq -r '.error.code // ""' <<<"$response") == SESSION_NOT_FOUND ]]; then
          agents_cli_fail SESSION_NOT_FOUND 'Register this explicit session before reporting.' 'Use aranea agents register --json-input with a complete session snapshot, then report events.'
        fi
        projects_cli_internal_error "$response"
      }
      projects_cli_finish observed '' 'Activity report stored.' "$(jq -c '{state:.state}' <<<"$response")"
      ;;
    dismiss)
      response=$(jq -cn --arg id "$id" '{action:"dismiss",args:{taskId:$id}}' | "$script_dir/aranea-agent-store" mutate) || projects_cli_internal_error "$response"
      projects_cli_finish observed '' 'Inactive task dismissed.' "$(jq -c '{state:.state}' <<<"$response")"
      ;;
    adapter)
      response=$("$script_dir/aranea-agent-adapter" "${words[1]}" "${words[2]}") || projects_cli_internal_error "$response"
      projects_cli_finish observed '' 'Adapter status.' "$(jq -c '{adapter:.state}' <<<"$response")"
      ;;
    focus | reopen | open-checkout)
      projects_cli_require timeout omarchy-shell
      agents_cli_submit request "$(jq -cn --arg action "$command" --arg id "$id" '{action:$action,taskId:$id}')"
      agents_cli_observe
      ;;
    operation)
      projects_cli_require timeout omarchy-shell
      if [[ "$reobserve" == true ]]; then agents_cli_submit reobserve "$cli_operation_id"; fi
      agents_cli_observe
      ;;
  esac
}
