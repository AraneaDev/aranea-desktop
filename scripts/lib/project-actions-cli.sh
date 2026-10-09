#!/usr/bin/env bash
# Public headless adapter; the private backend retains all execution authority.
# Public envelope globals are consumed by projects_cli_event in the sourced adapter.
# shellcheck disable=SC2154,SC2034

# Additive capability schema; payloads are streamed, including large retained state.
project_actions_cli_capabilities() {
  local availability
  availability=$("$script_dir/aranea-project-actions" availability </dev/null) || availability='{"availability":null}'
  jq -c '{availability:.availability,projectActions:{schemaVersion:1,namedDefinitions:true,headless:true,automaticExecution:false,automaticRestart:false,definitionDefaults:{commandTimeoutSeconds:300,serviceTimeoutSeconds:null},formDefaults:{cwdRelative:".",previewUrl:null},definitionFields:["id?","name","kind","argv","cwdRelative","timeoutSeconds?","previewUrl"],runOwnership:["bootId","unitName","transient","definitionHash","invocationId"],protection:"pending/running/unconfirmed processState or submissionUnconfirmed",lifetime:"user-manager; independent of UI and observers",journalSource:"local user journal; retention follows system policy",observationSeconds:10,transportTerminationGraceSeconds:0.2,backendTransportSeconds:60,bounds:{requestBytes:1048576,stateBytes:16777216,definitions:200,definitionsPerProject:50,protectedRuns:50,terminalRuns:100,terminalRetentionDays:7,receipts:512,argvItems:64,argumentCharacters:1024,argvBytes:16384,outputEntries:200,outputBytes:262144}},operations:[
    {name:"projects.actions.list",arguments:{projectId:{type:"string",required:true}}},
    {name:"projects.actions.configure",arguments:{projectId:{type:"string",required:true},"json-input":{type:"boolean",required:true},stdin:{type:"object",description:"definition draft or {definition,expectedRevision?}; save never executes"}}},
    {name:"projects.actions.remove",arguments:{projectId:{type:"string",required:true},actionId:{type:"string",required:true}}},
    {name:"projects.actions.run",arguments:{projectId:{type:"string",required:true},actionId:{type:"string",required:true},checkout:{type:"string"},"request-id":{type:"string"},"definition-revision":{type:"integer",minimum:1}}},
    {name:"projects.runs.list",arguments:{project:{type:"string"}}},
    {name:"projects.runs.inspect",arguments:{runId:{type:"string",required:true}}},
    {name:"projects.runs.refresh",arguments:{runId:{type:"string",required:true}}},
    {name:"projects.runs.stop",arguments:{runId:{type:"string",required:true}}},
    {name:"projects.runs.restart",arguments:{runId:{type:"string",required:true},"request-id":{type:"string"}}},
    {name:"projects.runs.logs",arguments:{runId:{type:"string",required:true}}},
    {name:"projects.runs.open-preview",arguments:{runId:{type:"string",required:true}}}
  ]}' <<<"$availability"
}

# Detached helper owns copied stdin/results until backend completion and reader release.
# Only the shared backend mutates or dispatches; the lease owns scratch lifetime only.
project_actions_cli_worker() {
  local worker=$1 backend=$2 operation=$3 lease
  umask 077
  trap '/usr/bin/rm -rf -- "$worker"' EXIT
  /usr/bin/timeout -k .2s 60s "$backend" "$operation" <"$worker/request" >"$worker/result.next" 2>"$worker/diagnostics" || true
  /usr/bin/mv -- "$worker/result.next" "$worker/result"
  : >"$worker/done"
  exec {lease}<>"$worker/lease"
  /usr/bin/flock -x "$lease"
  /usr/bin/rm -rf -- "$worker"
  trap - EXIT
}

# Publish accepted only for a receipt matching the submitted semantic tuple.
# Omitted checkout is resolved by its original receipt, never the changed default.
project_actions_cli_receipt() {
  jq --slurpfile q "$action_cli_scratch/request" --slurpfile target "$action_cli_scratch/target" '
    .state as $s | $q[0] as $q |
    ($s.requests[]? | select(.requestId==$q.requestId)) as $receipt |
    ($s.runs[]? | select(.id==$receipt.runId)) as $run |
    (if $q.runId then ($target[0] // ($s.runs[]? | select(.id==$q.runId))) else $q end) as $target |
    select($run.projectId==$target.projectId and $run.actionId==$target.actionId and
      (($target.checkoutId==null) or $run.checkoutId==$target.checkoutId)) |
    {ok:true,state:$s,error:null,run:$run,reused:false}' "$1" >"$action_cli_scratch/receipt"
  [[ -s $action_cli_scratch/receipt ]]
}

# Local cancellation/timeout retains receipt identity and never controls the worker.
project_actions_cli_partial() {
  local code=$1 message=$2
  if [[ -s $action_cli_scratch/receipt ]]; then
    cp -- "$action_cli_scratch/receipt" "$action_cli_scratch/result"
  else printf '{"ok":false,"state":null,"error":null}\n' >"$action_cli_scratch/result"; fi
  jq --arg code "$code" --arg message "$message" '.ok=false | .error={code:$code,message:$message,recovery:"Refresh the retained run, or list runs to recover this exact request receipt. Never automatically resubmit."}' "$action_cli_scratch/result" >"$action_cli_scratch/partial"
  mv -- "$action_cli_scratch/partial" "$action_cli_scratch/result"
}

# Signals end only this observer and release its OS-owned scratch read lease.
project_actions_cli_cancel_observer() {
  trap '' INT TERM
  project_actions_cli_partial OBSERVER_CANCELLED 'Stopped observing; accepted backend work continues.'
  project_actions_cli_finish
}

# Observe durable acceptance for ten seconds; detached work never belongs to the CLI.
project_actions_cli_observe() {
  local operation=$1 worker deadline=$((SECONDS + 10)) remaining accepted=false
  printf 'null\n' >"$action_cli_scratch/target"
  # Capture original restart identity before new acceptance can prune old history.
  if [[ $operation == restart ]]; then
    remaining=$((deadline - SECONDS))
    if /usr/bin/timeout -k .2s "${remaining}s" "$script_dir/aranea-project-action-store" snapshot >"$action_cli_scratch/original-state" 2>/dev/null; then
      jq --slurpfile q "$action_cli_scratch/request" '[.state.runs[]? | select(.id==$q[0].runId) | {projectId,checkoutId,actionId}][0] // null' "$action_cli_scratch/original-state" >"$action_cli_scratch/target"
    fi
  fi
  worker=$(mktemp -d "${TMPDIR:-/tmp}/aranea-action-observer.XXXXXX")
  cp -- "$action_cli_scratch/request" "$worker/request"
  exec {action_cli_lease_fd}<>"$worker/lease"
  /usr/bin/flock -s "$action_cli_lease_fd"
  export -f project_actions_cli_worker
  trap project_actions_cli_cancel_observer INT TERM
  # Close the inherited read lease before a detached fixed helper can execute.
  # Its stdio is private: EOF/CLI closure must not wait for helper completion.
  (
    exec {action_cli_lease_fd}>&-
    exec /usr/bin/setsid /usr/bin/bash -c 'project_actions_cli_worker "$@"' aranea-action-observer "$worker" "$script_dir/aranea-project-actions" "$operation"
  ) </dev/null >/dev/null 2>&1 &
  while ((SECONDS < deadline)); do
    remaining=$((deadline - SECONDS))
    if [[ $accepted == false ]] && /usr/bin/timeout -k .2s "${remaining}s" "$script_dir/aranea-project-action-store" snapshot >"$action_cli_scratch/acceptance-state" 2>/dev/null && project_actions_cli_receipt "$action_cli_scratch/acceptance-state"; then
      local event_data
      event_data=$(jq -c --arg request "$action_cli_request_id" '{runId:.run.id,run,requestId:$request}' "$action_cli_scratch/receipt")
      projects_cli_event step accepted request 'Run accepted; its lifetime is independent of this observer.' '' "$event_data"
      accepted=true
    fi
    if [[ -e $worker/done ]]; then
      cp -- "$worker/result" "$action_cli_scratch/result"
      if [[ $accepted == false ]] && project_actions_cli_receipt "$action_cli_scratch/result"; then
        local event_data
        event_data=$(jq -c --arg request "$action_cli_request_id" '{runId:.run.id,run,requestId:$request,reused:(.reused//false)}' "$action_cli_scratch/receipt")
        projects_cli_event step accepted request 'Run accepted; its lifetime is independent of this observer.' '' "$event_data"
      fi
      exec {action_cli_lease_fd}>&-
      trap - INT TERM
      return
    fi
    sleep .1
  done
  # Retain immutable acceptance, even if the final backend transport is still busy.
  # A request-only timeout may be recovered by exact receipt after late acceptance.
  project_actions_cli_partial OBSERVATION_TIMEOUT 'The CLI observation deadline expired; backend work continues.'
  trap - INT TERM
  exec {action_cli_lease_fd}>&-
}

# Preserve the exact latest envelope and run even on authoritative refusals.
project_actions_cli_call() {
  if [[ $1 == start || $1 == restart ]]; then
    project_actions_cli_observe "$1"
  else "$script_dir/aranea-project-actions" "$1" >"$action_cli_scratch/result" <"$action_cli_scratch/request" || true; fi
  if ! jq -e -s 'length==1 and (.[0]|type=="object" and (.ok|type=="boolean") and has("error"))' "$action_cli_scratch/result" >/dev/null 2>&1; then
    project_actions_cli_partial SUBMISSION_UNCONFIRMED 'Backend response unavailable; acceptance may be retained.'
  fi
}

# Classify main result independently from protected cleanup and backend success.
project_actions_cli_finish() {
  local outcome=observed code message='Project action result.' exit_code=0 data
  code=$(jq -r '.error.code // .run.error.code // ""' "$action_cli_scratch/result")
  if jq -e '.run.submissionUnconfirmed==true or (.run.processState=="pending" or .run.processState=="unconfirmed") or (.ok==false and .run.processState=="running") or .error.code=="SUBMISSION_UNCONFIRMED" or .error.code=="OBSERVATION_TIMEOUT" or .error.code=="OBSERVER_CANCELLED"' "$action_cli_scratch/result" >/dev/null; then
    outcome=partial exit_code=1
  elif jq -e '.ok==false or .run.processState=="failed" or .run.outcome=="failed"' "$action_cli_scratch/result" >/dev/null; then
    outcome=failed exit_code=1
  fi
  [[ "$code" != DEPENDENCY_MISSING ]] || exit_code=4
  data=$(jq -c --arg request "$action_cli_request_id" --arg outcome "$outcome" '. + {outcome:$outcome} + (if .run then {runId:.run.id} else {} end) + (if $request!="" then {requestId:$request} else {} end)' "$action_cli_scratch/result")
  if [[ $outcome != observed ]]; then
    message=$(jq -r '.error.message // .run.error.message // "Command failed."' "$action_cli_scratch/result")
    local recovery
    recovery=$(jq -r '.error.recovery // .run.error.recovery // "Refresh the retained run or view its logs."' "$action_cli_scratch/result")
    printf '%s: %s\n' "${code:-ACTION_FAILED}" "$message" >&2
    projects_cli_event recovery action_required '' "$recovery" "$code" "$data"
  fi
  projects_cli_event completed "$outcome" '' "$message" "$code" "$data"
  exit "$exit_code"
}

# Parse the entire strict public command before reading stdin or touching authority.
project_actions_cli_main() {
  cli_json=false cli_operation_id='' cli_operation=aranea
  action_cli_request_id=''
  local arg group command option value project='' action='' run='' checkout='' revision='' json_input=false
  local -a words=()
  local -A supplied=()
  for arg in "$@"; do
    if [[ $arg == --json ]]; then
      [[ $cli_json == false ]] || {
        command -v jq >/dev/null && projects_cli_usage
        exit 2
      }
      cli_json=true
    else words+=("$arg"); fi
  done
  # Retain the existing encoder-free missing-jq protocol.
  command -v jq >/dev/null || projects_cli_main "$@"
  set -- "${words[@]}"
  [[ $# -ge 3 && $1 == projects ]] || projects_cli_usage
  group=$2 command=$3
  shift 3
  cli_operation="projects.$group.$command"
  case "$group:$command" in
    actions:list | actions:configure | actions:remove | actions:run)
      [[ $# -ge 1 && $1 != -* && -n $1 ]] || projects_cli_usage
      project=$1
      shift
      if [[ $command == remove || $command == run ]]; then
        [[ $# -ge 1 && $1 != -* && -n $1 ]] || projects_cli_usage
        action=$1
        shift
      fi
      ;;
    runs:list) ;;
    runs:inspect | runs:refresh | runs:stop | runs:restart | runs:logs | runs:open-preview)
      [[ $# -ge 1 && $1 != -* && -n $1 ]] || projects_cli_usage
      run=$1
      shift
      ;;
    *) projects_cli_usage ;;
  esac
  while (($#)); do
    option=$1
    [[ $option == --* && ! -v supplied[$option] ]] || projects_cli_usage
    supplied[$option]=1
    case "$group:$command:$option" in
      actions:configure:--json-input)
        json_input=true
        shift
        continue
        ;;
      actions:run:--checkout | actions:run:--request-id | actions:run:--definition-revision | runs:restart:--request-id | runs:list:--project) ;;
      *) projects_cli_usage ;;
    esac
    [[ $# -ge 2 && -n $2 && $2 != --* ]] || projects_cli_usage
    value=$2
    shift 2
    case "$option" in
      --checkout) checkout=$value ;;
      --project) project=$value ;;
      --request-id) action_cli_request_id=$value ;;
      --definition-revision)
        [[ $value =~ ^[1-9][0-9]*$ && ${#value} -le 15 ]] || projects_cli_usage
        revision=$value
        ;;
    esac
  done
  [[ $command != configure || $json_input == true ]] || projects_cli_usage
  projects_cli_require head stat mktemp
  if [[ $command == run || $command == restart ]]; then projects_cli_require setsid timeout flock cp mv; fi
  # Preserve ingress generation across blocked configuration stdin.
  # shellcheck source=scripts/lib/paths.sh
  source "$script_dir/lib/paths.sh"
  # shellcheck source=scripts/lib/project-actions.sh
  source "$script_dir/lib/project-actions.sh"
  ARANEA_ACTION_GENERATION=$(project_actions_generation)
  export ARANEA_ACTION_GENERATION
  umask 077
  action_cli_scratch=$(mktemp -d)
  trap 'rm -rf -- "$action_cli_scratch"' EXIT
  jq -cn --arg p "$project" --arg a "$action" --arg r "$run" --arg c "$checkout" --arg req "$action_cli_request_id" --arg rev "$revision" '{} + (if $p!="" then {projectId:$p} else {} end) + (if $a!="" then {actionId:$a} else {} end) + (if $r!="" then {runId:$r} else {} end) + (if $c!="" then {checkoutId:$c} else {} end) + (if $req!="" then {requestId:$req} else {} end) + (if $rev!="" then {expectedDefinitionRevision:($rev|tonumber)} else {} end)' >"$action_cli_scratch/request"
  if [[ $command == configure ]]; then
    head -c 1048577 >"$action_cli_scratch/input"
    [[ $(stat -c %s "$action_cli_scratch/input") -le 1048576 ]] || projects_cli_fail INPUT_TOO_LARGE 'Request exceeds 1 MiB.' 'Provide a bounded definition draft.'
    jq -ecs --arg p "$project" 'if length==1 and (.[0]|type)=="object" then .[0] else error("one object") end | if has("definition") then if (keys-["definition","expectedRevision"]|length)==0 then .+{projectId:$p} else error("wrapper fields") end else {projectId:$p,definition:.} end' "$action_cli_scratch/input" >"$action_cli_scratch/request" 2>/dev/null || projects_cli_fail INVALID_REQUEST 'Provide one definition draft or revision wrapper.' 'Use --json-input with the documented draft.'
  fi
  if [[ $command == run || $command == restart ]]; then
    if [[ -z $action_cli_request_id ]]; then
      action_cli_request_id="req-$(/usr/bin/cat /proc/sys/kernel/random/uuid)"
      jq --arg id "$action_cli_request_id" '.+{requestId:$id}' "$action_cli_scratch/request" >"$action_cli_scratch/new-request"
      mv "$action_cli_scratch/new-request" "$action_cli_scratch/request"
    fi
  fi
  projects_cli_event started '' '' 'Reading or submitting project action.' '' '{}'
  local backend_command=$command
  [[ $command != run ]] || backend_command=start
  [[ $command != list ]] || backend_command=snapshot
  project_actions_cli_call "$backend_command"
  if [[ $command == list ]]; then
    if [[ $group == actions ]]; then
      jq '.+{definitions:.state.definitions,revision:.state.revision}' "$action_cli_scratch/result" >"$action_cli_scratch/list"
    else jq '.+{runs:.state.runs,revision:.state.revision}' "$action_cli_scratch/result" >"$action_cli_scratch/list"; fi
    mv "$action_cli_scratch/list" "$action_cli_scratch/result"
  fi
  # Running is an observed launch; timeout/uncertainty never cancel accepted work.
  project_actions_cli_finish
}
