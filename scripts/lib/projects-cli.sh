#!/usr/bin/env bash
# Public protocol adapter. Registry and persistent owner retain all authority.
# Entry point supplies the absolute helper directory.
# shellcheck disable=SC2154

# Emit public JSONL or readable human progress; diagnostics never enter stdout.
projects_cli_event() {
  local event=$1 status=$2 id=$3 message=$4 code=$5 data=${6:-\{\}}
  if [[ "$cli_json" == true ]]; then
    json_event "$event" "$cli_operation" "$status" "$id" "$message" "$code" "$data" "$cli_operation_id"
  else
    printf '%s: %s%s\n' "$event" "${message:-$status}" "${code:+ ($code)}"
    if [[ "$event" == completed && "$status" == observed ]]; then jq . <<<"$data"; fi
  fi
}

# Finish with an authoritative outcome/exit code.
projects_cli_finish() {
  local outcome=$1 code=${2:-} message=${3:-} data=${4:-\{\}} exit_code=${5:-0}
  data=$(jq -c --arg outcome "$outcome" '. + {outcome:$outcome}' <<<"$data")
  projects_cli_event completed "$outcome" '' "$message" "$code" "$data"
  exit "$exit_code"
}

# Fail with stable code and explicit recovery, preserving operation reconnection.
projects_cli_fail() {
  local code=$1 message=$2 recovery=$3 exit_code=${4:-1} outcome=failed data
  [[ "$code" != OBSERVATION_TIMEOUT && "$code" != OBSERVER_CANCELLED && "$code" != OWNER_UNAVAILABLE ]] || outcome=partial
  data=$(jq -cn --arg recovery "$recovery" '{recovery:$recovery}')
  printf '%s: %s\n' "$code" "$message" >&2
  projects_cli_event recovery action_required '' "$recovery" "$code" "$data"
  projects_cli_finish "$outcome" "$code" "$message" "$data" "$exit_code"
}

# Reject usage before IPC/mutation; missing fields and repeated options are errors.
projects_cli_usage() {
  projects_cli_fail INVALID_USAGE 'Invalid command arguments.' 'Run aranea capabilities --json for command argument schemas.' 2
}

# Require only the dependencies used by this command.
projects_cli_require() {
  local dependency
  for dependency in "$@"; do
    command -v "$dependency" >/dev/null 2>&1 || projects_cli_fail DEPENDENCY_MISSING "Install $dependency to use this command." "Install $dependency and retry." 4
  done
}

# Read an internal store response and translate its structured failure.
projects_cli_store() {
  local response
  if response=$("$script_dir/aranea-project-store" "$@") && jq -e '.ok == true' <<<"$response" >/dev/null; then
    cli_state=$(jq -c .state <<<"$response")
  else
    projects_cli_internal_error "$response"
  fi
}

# Convert a helper or owner refusal without replacing stable domain errors.
projects_cli_internal_error() {
  local response=$1 code message recovery exit_code=1
  if ! jq -e -s 'length==1 and (.[0]|type=="object")' <<<"$response" >/dev/null 2>&1; then response='{}'; fi
  code=$(jq -r '(.error.code | select(type=="string" and length>0)) // "OWNER_UNAVAILABLE"' <<<"$response" 2>/dev/null) || code=OWNER_UNAVAILABLE
  message=$(jq -r '(.error.message | select(type=="string" and length>0)) // "The response was unavailable."' <<<"$response" 2>/dev/null) || message='The response was unavailable.'
  recovery=$(jq -r '(.error.recovery | select(type=="string" and length>0)) // "Inspect current state before retrying."' <<<"$response" 2>/dev/null) || recovery='Inspect current state before retrying.'
  case "$code" in
    DEPENDENCY_MISSING) exit_code=4 ;;
    TOOL_CHOICE_REQUIRED) exit_code=3 ;;
  esac
  projects_cli_fail "$code" "$message" "$recovery" "$exit_code"
}

# Fixed IPC argv, bounded even if the shell stops answering during observation.
projects_cli_ipc() {
  local response bound=2
  if [[ -n "${cli_deadline:-}" ]]; then
    local remaining=$((cli_deadline - SECONDS))
    ((remaining > 0)) || return 1
    ((remaining >= bound)) || bound=$remaining
  fi
  if response=$(timeout "${bound}s" omarchy-shell "$@"); then
    printf '%s\n' "$response"
  else
    return 1
  fi
}

# Read a fresh owner snapshot; unavailable compositor does not block registry reads.
projects_cli_snapshot() {
  if ! cli_snapshot=$(projects_cli_ipc aranea.projects snapshot) || ! jq -e 'type=="object" and (.sessionId|type=="string") and (.availability|type=="object")' <<<"$cli_snapshot" >/dev/null 2>&1; then
    if [[ -n "${cli_deadline:-}" ]] && ((SECONDS >= cli_deadline)); then projects_cli_observer_timeout; fi
    projects_cli_fail OWNER_UNAVAILABLE 'Project owner IPC is unavailable.' "Activate Aranea and reconnect with aranea projects operation ${cli_operation_id:-OPERATION_ID} --json."
  fi
}

# Check registered project/checkout IDs before any desktop call.
projects_cli_select() {
  cli_project=$(jq -c --arg id "$cli_project_id" '.projects[] | select(.id==$id)' <<<"$cli_state")
  [[ -n "$cli_project" ]] || projects_cli_usage
  if [[ -n "$cli_checkout_id" ]]; then
    jq -e --arg id "$cli_checkout_id" 'any(.checkouts[];.id==$id)' <<<"$cli_project" >/dev/null || projects_cli_usage
  fi
}

# Validate the exact fresh registered checkout identity; never substitute another.
projects_cli_validate_checkout() {
  local metadata path common
  [[ -n "$cli_checkout_id" ]] || cli_checkout_id=$(jq -r .lastCheckoutId <<<"$cli_project")
  path=$(jq -r --arg id "$cli_checkout_id" '.checkouts[]|select(.id==$id)|.path' <<<"$cli_project")
  [[ -n "$path" && -d "$path" ]] || projects_cli_fail CHECKOUT_MISSING 'The selected checkout folder is missing.' 'Locate the folder, explicitly choose another checkout, or remove the registration.'
  if ! metadata=$("$script_dir/aranea-project-discover" --metadata "$path" --json); then
    projects_cli_fail CHECKOUT_MISSING 'The exact selected checkout cannot be validated.' 'Locate the exact checkout folder and retry.'
  fi
  common=$(jq -r .commonDir <<<"$cli_project")
  jq -e --arg path "$path" --arg common "$common" '.ok==true and .metadata.path==$path and .metadata.commonDir==$common' <<<"$metadata" >/dev/null || projects_cli_fail REGISTRY_CONFLICT 'The checkout identity changed.' 'Refresh or explicitly relocate the registered checkout.'
}

# Observer cancellation is local only: no owner cancellation or resubmission.
projects_cli_cancel_observer() {
  trap '' INT TERM
  projects_cli_fail OBSERVER_CANCELLED 'Stopped observing; accepted owner work continues.' "Reconnect with aranea projects operation $cli_operation_id --json."
}

# Report the observer deadline without affecting the owner.
projects_cli_observer_timeout() {
  projects_cli_fail OBSERVATION_TIMEOUT 'Owner work remains unconfirmed after 30 seconds.' "Reconnect with aranea projects operation $cli_operation_id --json."
}

# Poll one accepted ID at 250ms for at most 30 seconds; changed steps emit once.
projects_cli_observe() {
  local cli_deadline=$((SECONDS + 30)) operation session generation='' seen='[]' step identity
  trap projects_cli_cancel_observer INT TERM
  session=$(jq -r .sessionId <<<"$cli_snapshot")
  while ((SECONDS < cli_deadline)); do
    projects_cli_snapshot
    [[ $(jq -r .sessionId <<<"$cli_snapshot") == "$session" ]] || projects_cli_fail OPERATION_LOST 'The shell session changed; this operation is no longer authoritative.' 'Inspect current state; accepted work is never automatically resubmitted.'
    if ! operation=$(projects_cli_ipc aranea.projects operation "$cli_operation_id"); then
      if ((SECONDS >= cli_deadline)); then projects_cli_observer_timeout; fi
      projects_cli_fail OWNER_UNAVAILABLE 'The observer disconnected from the owner.' "Reconnect with aranea projects operation $cli_operation_id --json."
    fi
    jq -e --arg id "$cli_operation_id" --arg session "$session" '.id==$id and .sessionId==$session and (.generation|type=="number") and (.steps|type=="array")' <<<"$operation" >/dev/null 2>&1 || projects_cli_fail OPERATION_LOST 'The owner no longer retains this session-bound operation.' 'Inspect current state; do not automatically resubmit.'
    if [[ -n "$cli_project_id" ]]; then
      jq -e --arg project "$cli_project_id" --arg checkout "$cli_checkout_id" '.projectId==$project and .checkoutId==$checkout' <<<"$operation" >/dev/null || projects_cli_fail OPERATION_LOST 'The returned operation targets a different registered checkout.' 'Inspect owner state before deciding to submit again.'
    fi
    if [[ -z "$generation" ]]; then generation=$(jq -r .generation <<<"$operation"); fi
    [[ $(jq -r .generation <<<"$operation") == "$generation" ]] || projects_cli_fail OPERATION_LOST 'The operation generation changed.' 'Inspect current state; do not automatically resubmit.'
    while IFS= read -r step; do
      identity=$(jq -cS . <<<"$step")
      if ! jq -e --argjson step "$identity" 'index($step)!=null' <<<"$seen" >/dev/null; then
        seen=$(jq -c --argjson step "$identity" '.+[$step]' <<<"$seen")
        projects_cli_event step "$(jq -r '.status // .state // "pending"' <<<"$step")" "$(jq -r '.id // .role // "progress"' <<<"$step")" "$(jq -r '.message // ""' <<<"$step")" "$(jq -r '.code // ""' <<<"$step")" "$step"
      fi
    done < <(jq -c '.steps[]' <<<"$operation")
    if [[ $(jq -r .state <<<"$operation") == completed ]]; then
      local outcome exit_code=1 code
      outcome=$(jq -r .outcome <<<"$operation")
      [[ "$outcome" == observed || "$outcome" == partial || "$outcome" == failed ]] || projects_cli_fail OPERATION_LOST 'The terminal outcome is invalid.' 'Inspect owner state.'
      [[ "$outcome" != observed ]] || exit_code=0
      code=$(jq -r '.error.code // ""' <<<"$operation")
      if [[ "$outcome" == failed ]]; then
        if [[ -z "$code" ]]; then code=$(jq -r '[.steps[].code | select(.=="TOOL_CHOICE_REQUIRED" or .=="DEPENDENCY_MISSING")][0] // ""' <<<"$operation"); fi
        [[ "$code" != TOOL_CHOICE_REQUIRED ]] || exit_code=3
        [[ "$code" != DEPENDENCY_MISSING ]] || exit_code=4
      fi
      projects_cli_finish "$outcome" "$code" 'Owner operation completed.' "$(jq -c '{operation:.}' <<<"$operation")" "$exit_code"
    fi
    sleep 0.25
  done
  projects_cli_observer_timeout
}

# Capabilities are self-describing and expose absent dependencies without failing.
projects_cli_capabilities() {
  local dependencies='{}' dependency available tools='null' owner='null'
  for dependency in git flock jq realpath setsid timeout omarchy-shell; do
    available=false
    command -v "$dependency" >/dev/null 2>&1 && available=true
    dependencies=$(jq -c --arg name "$dependency" --argjson available "$available" '.+{($name):$available}' <<<"$dependencies")
  done
  tools=$("$script_dir/aranea-project-tools" --json) || tools=null
  if command -v omarchy-shell >/dev/null && command -v timeout >/dev/null; then
    owner=$(projects_cli_ipc aranea.projects snapshot) || owner=null
    jq -e 'type=="object"' <<<"$owner" >/dev/null 2>&1 || owner=null
  fi
  local schemas
  schemas=$(
    cat <<'JSON'
[
{"name":"capabilities","arguments":{}},
{"name":"projects.list","arguments":{}},
{"name":"projects.inspect","arguments":{"projectId":{"type":"string","required":true}}},
{"name":"projects.roots.add","arguments":{"path":{"type":"string","required":true}}},
{"name":"projects.roots.remove","arguments":{"rootId":{"type":"string","required":true}}},
{"name":"projects.discover","arguments":{"root":{"type":"string"}}},
{"name":"projects.register","arguments":{"path":{"type":"array","items":"string","required":true}}},
{"name":"projects.ignore","arguments":{"path":{"type":"string","required":true}}},
{"name":"projects.ignored","arguments":{}},
{"name":"projects.unignore","arguments":{"path":{"type":"string","required":true}}},
{"name":"projects.configure","arguments":{"projectId":{"type":"string","required":true},"name":{"type":"string"},"editor":{"type":"string","enum":["code","nvim"]},"terminal":{"type":"string","enum":["alacritty","kitty","foot","ghostty"]},"workspace":{"type":"string","enum":["dedicated","current"]}}},
{"name":"projects.relocate","arguments":{"projectId":{"type":"string","required":true},"checkout":{"type":"string","required":true},"path":{"type":"string","required":true}}},
{"name":"projects.remove","arguments":{"projectId":{"type":"string","required":true}}},
{"name":"projects.open","arguments":{"projectId":{"type":"string","required":true},"checkout":{"type":"string"},"separate":{"type":"boolean"},"use-current-workspace":{"type":"boolean"},"new-window":{"type":"string","enum":["editor","terminal"]},"retry-role":{"type":"string","enum":["editor","terminal"]},"reobserve-role":{"type":"string","enum":["editor","terminal"]}}},
{"name":"projects.operation","arguments":{"operationId":{"type":"string","required":true}}},
{"name":"projects.details","arguments":{"projectId":{"type":"string","required":true}}},
{"name":"desktop.status","arguments":{}}
]
JSON
  )
  local activity
  activity=$(agents_cli_capabilities)
  projects_cli_finish observed '' 'Aranea capabilities.' "$(jq -cn --argjson activity "$activity" --argjson operations "$schemas" --argjson dependencies "$dependencies" --argjson tools "$tools" --argjson owner "$owner" '{operations:($operations+$activity.operations),activity:$activity.activity,availability:{dependencies:$dependencies,tools:$tools,owner:$owner}}')"
}

# Parse all public syntax before crossing registry or desktop boundaries.
projects_cli_main() {
  cli_json=false cli_operation=aranea cli_operation_id='' cli_checkout_id='' cli_project_id='' cli_state='' cli_snapshot=''
  local -a words=() paths=() discovery_args=()
  local arg command option value root_id='' path='' args='{}' action='' separate=false current=false new_role=null retry_role=null reobserve_role=null
  local -A supplied=()
  for arg in "$@"; do
    if [[ "$arg" == --json ]]; then cli_json=true; else words+=("$arg"); fi
  done
  # This fixed envelope is valid even when the JSON encoder is unavailable.
  if ! command -v jq >/dev/null 2>&1; then
    echo 'Install jq to use the public project protocol.' >&2
    if [[ "$cli_json" == true ]]; then
      local timestamp timestamp_json=null timestamp_available=false
      if timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) && [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        # Only validated digits/punctuation enter this encoder-free envelope.
        timestamp_json="\"$timestamp\""
        timestamp_available=true
      fi
      printf '{"schema":1,"event":"completed","operation":"aranea","timestamp":%s,"status":"failed","code":"DEPENDENCY_MISSING","data":{"outcome":"failed","dependency":"jq","timestampAvailable":%s,"recovery":"Install jq and retry."}}\n' "$timestamp_json" "$timestamp_available"
    fi
    exit 4
  fi
  set -- "${words[@]}"
  [[ $# -gt 0 ]] || projects_cli_usage
  case "$1" in
    capabilities)
      [[ $# == 1 ]] || projects_cli_usage
      cli_operation=capabilities
      projects_cli_capabilities
      ;;
    desktop)
      [[ $# == 2 && "$2" == status ]] || projects_cli_usage
      cli_operation=desktop.status
      command=desktop
      shift 2
      ;;
    projects)
      [[ $# -ge 2 ]] || projects_cli_usage
      command=$2
      shift 2
      if [[ "$command" == roots ]]; then
        [[ $# -ge 1 && ("$1" == add || "$1" == remove) ]] || projects_cli_usage
        command="roots.$1"
        shift
      fi
      cli_operation="projects.$command"
      ;;
    *) projects_cli_usage ;;
  esac
  case "$command" in
    inspect | configure | relocate | remove | open | details)
      [[ $# -ge 1 && -n "$1" && "$1" != -* ]] || projects_cli_usage
      cli_project_id=$1
      shift
      args=$(jq -cn --arg id "$cli_project_id" '{projectId:$id}')
      ;;
    roots.add | roots.remove | operation)
      [[ $# == 1 && -n "$1" && "$1" != -* ]] || projects_cli_usage
      case "$command" in
        roots.add)
          path=$1
          action='root-add'
          args=$(jq -cn --arg path "$path" '{path:$path}')
          ;;
        roots.remove)
          root_id=$1
          action='root-remove'
          args=$(jq -cn --arg id "$root_id" '{rootId:$id}')
          ;;
        operation)
          cli_operation_id=$1
          [[ "$1" =~ ^op-[0-9]+-[0-9]+$ ]] || projects_cli_usage
          ;;
      esac
      shift
      ;;
    list | ignored | discover | register | ignore | unignore | desktop) ;;
    *) projects_cli_usage ;;
  esac
  while (($#)); do
    option=$1
    [[ "$option" == --* && ! -v supplied[$option] ]] || { [[ "$command" == register && "$option" == --path ]] || projects_cli_usage; }
    supplied[$option]=1
    case "$command:$option" in
      open:--separate)
        separate=true
        shift
        continue
        ;;
      open:--use-current-workspace)
        current=true
        shift
        continue
        ;;
      configure:--name | configure:--editor | configure:--terminal | configure:--workspace | open:--checkout | open:--new-window | open:--retry-role | open:--reobserve-role | relocate:--checkout | relocate:--path | discover:--root | register:--path | ignore:--path | unignore:--path) ;;
      *) projects_cli_usage ;;
    esac
    [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || projects_cli_usage
    value=$2
    shift 2
    case "$option" in
      --path)
        path=$value
        paths+=("$value")
        ;;
      --root) root_id=$value ;;
      --checkout)
        cli_checkout_id=$value
        args=$(jq -c --arg id "$value" '.+{checkoutId:$id}' <<<"$args")
        ;;
      --name) args=$(jq -c --arg name "$value" '.+{name:$name}' <<<"$args") ;;
      --editor)
        [[ "$value" == code || "$value" == nvim ]] || projects_cli_usage
        args=$(jq -c --arg id "$value" '.+{editorId:$id}' <<<"$args")
        ;;
      --terminal)
        [[ "$value" == alacritty || "$value" == kitty || "$value" == foot || "$value" == ghostty ]] || projects_cli_usage
        args=$(jq -c --arg id "$value" '.+{terminalId:$id}' <<<"$args")
        ;;
      --workspace)
        [[ "$value" == dedicated || "$value" == current ]] || projects_cli_usage
        args=$(jq -c --arg mode "$value" '.+{workspaceMode:$mode}' <<<"$args")
        ;;
      --new-window | --retry-role | --reobserve-role)
        [[ "$value" == editor || "$value" == terminal ]] || projects_cli_usage
        case "$option" in
          --new-window) new_role=$value ;;
          --retry-role) retry_role=$value ;;
          --reobserve-role) reobserve_role=$value ;;
        esac
        ;;
    esac
  done
  [[ "$separate" != true || "$current" != true ]] || projects_cli_usage
  [[ "$new_role" == null || "$retry_role" == null ]] || projects_cli_usage
  [[ "$reobserve_role" == null || ("$new_role" == null && "$retry_role" == null) ]] || projects_cli_usage
  case "$command" in
    register | ignore | unignore) [[ ${#paths[@]} -gt 0 ]] || projects_cli_usage ;;
    relocate) [[ -n "$path" && -n "$cli_checkout_id" ]] || projects_cli_usage ;;
    configure) [[ ${#supplied[@]} -gt 0 ]] || projects_cli_usage ;;
  esac
  projects_cli_event started '' '' 'Starting project command.' '' '{}'
  if [[ "$command" == desktop || "$command" == operation ]]; then
    projects_cli_require omarchy-shell timeout
    projects_cli_snapshot
    [[ "$command" != operation ]] || projects_cli_observe
    projects_cli_finish observed '' 'Current owner observations.' "$cli_snapshot"
  fi
  projects_cli_require flock realpath
  case "$command" in register | ignore | relocate | open | discover) projects_cli_require git ;;
  esac
  case "$command" in open | discover) projects_cli_require setsid ;;
  esac
  projects_cli_store snapshot
  [[ -z "$cli_project_id" ]] || projects_cli_select
  if [[ -n "$root_id" ]]; then
    jq -e --arg id "$root_id" 'any(.roots[];.id==$id)' <<<"$cli_state" >/dev/null || projects_cli_usage
  fi
  case "$command" in
    list) projects_cli_finish observed '' 'Registered projects.' "$(jq -c '{revision,projects}' <<<"$cli_state")" ;;
    inspect) projects_cli_finish observed '' 'Registered project.' "$(jq -cn --argjson project "$cli_project" '{project:$project}')" ;;
    ignored) projects_cli_finish observed '' 'Ignored candidates.' "$(jq -c '{revision,ignored}' <<<"$cli_state")" ;;
    discover)
      local root line scan_result outcome=observed
      while IFS= read -r root; do discovery_args+=(--root "$(jq -r . <<<"$root")"); done < <(jq -c --arg id "$root_id" '.roots[]|select($id=="" or .id==$id)|.path' <<<"$cli_state")
      [[ ${#discovery_args[@]} -gt 0 ]] || projects_cli_fail ROOT_CHOICE_REQUIRED 'Choose an approved discovery root.' 'Add a root with aranea projects roots add PATH.' 3
      scan_result=$(mktemp)
      if ! "$script_dir/aranea-project-discover" "${discovery_args[@]}" --json >"$scan_result"; then outcome=partial; fi
      while IFS= read -r line; do
        if [[ $(jq -r .event <<<"$line") == candidate ]]; then
          # Ignored and fully registered groups stay outside the review list;
          # partially registered groups retain individually selectable siblings.
          jq -e --argjson candidate "$(jq -c .candidate <<<"$line")" '. as $registry |
            any(.ignored[];.path==$candidate.path or .commonDir==$candidate.commonDir) or
            ([$candidate.path, ($candidate.checkouts[]?.path)] | unique |
              all(.[]; . as $path | any($registry.projects[];
                .commonDir==$candidate.commonDir and any(.checkouts[];.path==$path))))' <<<"$cli_state" >/dev/null && continue
          projects_cli_event step observed candidate 'Discovered repository; registration requires explicit selection.' '' "$line"
        elif [[ $(jq -r .outcome <<<"$line") == partial ]]; then outcome=partial; fi
      done <"$scan_result"
      local summary='{}' exit_code=0
      [[ ! -s "$scan_result" ]] || summary=$(tail -n 1 "$scan_result")
      rm -f -- "$scan_result"
      [[ "$outcome" != partial ]] || exit_code=1
      projects_cli_finish "$outcome" '' 'Discovery completed.' "$summary" "$exit_code"
      ;;
    open)
      projects_cli_validate_checkout
      projects_cli_require omarchy-shell timeout
      projects_cli_snapshot
      jq -e '.availability.compositor==true' <<<"$cli_snapshot" >/dev/null || projects_cli_fail COMPOSITOR_UNAVAILABLE 'Workspace opening requires a live compositor.' 'Start a supported desktop session and retry.'
      local payload response ready_deadline=$((SECONDS + 5))
      payload=$(jq -cn --arg projectId "$cli_project_id" --arg checkoutId "$cli_checkout_id" --argjson separate "$separate" --argjson current "$current" --arg new "$new_role" --arg retry "$retry_role" --arg reobserve "$reobserve_role" '{projectId:$projectId,checkoutId:$checkoutId,separate:$separate,useCurrentWorkspace:$current} + (if $new=="null" then {} else {newWindowRole:$new} end) + (if $retry=="null" then {} else {retryRole:$retry} end) + (if $reobserve=="null" then {} else {reobserveRole:$reobserve} end)')
      local preparing=false
      while true; do
        if [[ "$preparing" == true ]] && ((SECONDS >= ready_deadline)); then projects_cli_internal_error "$response"; fi
        if ! response=$(projects_cli_ipc aranea.projects request "$payload"); then projects_cli_fail OWNER_UNAVAILABLE 'Submission could not be confirmed; it may have been accepted.' 'Inspect owner state before any new submission.'; fi
        if ! jq -e -s 'length==1 and (.[0]|type=="object")' <<<"$response" >/dev/null 2>&1; then
          projects_cli_fail OWNER_UNAVAILABLE 'Submission could not be confirmed; it may have been accepted.' 'Inspect owner state before any new submission.'
        fi
        if jq -e '.ok==true and has("error") and .error==null and (.operationId|type=="string" and length>0)' <<<"$response" >/dev/null 2>&1; then
          cli_operation_id=$(jq -r .operationId <<<"$response")
          break
        fi
        if ! jq -e '.ok==false and has("operationId") and .operationId==null and (.error|type=="object") and all(.error.code,.error.message,.error.recovery; type=="string" and length>0)' <<<"$response" >/dev/null 2>&1; then
          projects_cli_fail OWNER_UNAVAILABLE 'Submission could not be confirmed; it may have been accepted.' 'Inspect owner state before any new submission.'
        fi
        if jq -e '.ok==false and has("operationId") and .operationId==null and .error.code=="OWNER_NOT_READY"' <<<"$response" >/dev/null 2>&1 && ((SECONDS < ready_deadline)); then
          preparing=true
          sleep 0.25
        else projects_cli_internal_error "$response"; fi
      done
      projects_cli_event step accepted request 'Owner accepted the operation; observation follows.' '' "$response"
      projects_cli_observe
      ;;
    details)
      projects_cli_require omarchy-shell timeout
      local payload readback
      payload=$(jq -cn --arg projectId "$cli_project_id" '{section:"projects",projectId:$projectId}')
      projects_cli_ipc shell summon araneadev.settings "$payload" >/dev/null || projects_cli_fail OWNER_UNAVAILABLE 'Settings could not be summoned.' 'Activate Aranea and retry.'
      if readback=$(projects_cli_ipc aranea.settings.capture captureSnapshot) && jq -e --arg id "$cli_project_id" '.opened==true and .section=="projects" and .projectId==$id' <<<"$readback" >/dev/null 2>&1; then
        projects_cli_finish observed '' 'Project details observed.' "$(jq -cn --arg id "$cli_project_id" '{projectId:$id,accepted:true}')"
      fi
      projects_cli_finish partial DETAILS_UNCONFIRMED 'Settings accepted the summon; the exact destination is unconfirmed.' "$(jq -cn --arg id "$cli_project_id" '{projectId:$id,accepted:true,recovery:"Install/activate the Settings Projects destination and retry."}')" 1
      ;;
    register)
      action=register
      args=$(jq -cn --args '{paths:$ARGS.positional}' -- "${paths[@]}")
      ;;
    ignore | unignore)
      action=$command
      args=$(jq -cn --arg path "$path" '{path:$path}')
      ;;
    configure | remove) action=$command ;;
    relocate)
      action=relocate
      args=$(jq -c --arg path "$path" '.+{path:$path}' <<<"$args")
      ;;
  esac
  local request
  request=$(jq -cn --arg action "$action" --argjson args "$args" --argjson revision "$(jq .revision <<<"$cli_state")" '{action:$action,args:$args,expectedRevision:$revision}')
  projects_cli_store mutate <<<"$request"
  projects_cli_finish observed '' 'Registry mutation observed.' "$(jq -cn --argjson state "$cli_state" '{state:$state}')"
}
