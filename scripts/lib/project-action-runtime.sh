#!/usr/bin/env bash
# Shared execution helpers; sourced only by the private headless backend.
# shellcheck disable=SC2154

# Emit one actionable envelope, retaining the latest valid state and run.
runtime_error() {
  jq -c --arg c "$1" --arg m "$2" '.ok=false | .error={code:$c,message:$m,recovery:"Refresh the retained run; resolve its exact identity before retrying or removing actions."}' "$scratch/result"
  exit 1
}

# Validate ingress before lookup or effects; the store validates definition drafts.
runtime_validate() {
  jq -e --arg op "$operation" '
    def id($p): type=="string" and test("\\A"+$p+"-[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\\z");
    def keys_only($k): (keys_unsorted-$k|length)==0;
    if $op=="start" then keys_only(["projectId","checkoutId","actionId","requestId","expectedDefinitionRevision"]) and (.projectId|id("p")) and (.actionId|id("a")) and (.requestId|id("req")) and ((has("checkoutId")|not) or (.checkoutId|id("c"))) and ((has("expectedDefinitionRevision")|not) or (.expectedDefinitionRevision|type=="number" and .==floor and .>=1))
    elif $op=="restart" then keys_only(["runId","requestId","expectedDefinitionRevision"]) and (.runId|id("r")) and (.requestId|id("req")) and ((has("expectedDefinitionRevision")|not) or (.expectedDefinitionRevision|type=="number" and .==floor and .>=1))
    elif (["inspect","refresh","stop","logs","open-preview"]|index($op))!=null then keys_only(["runId"]) and (.runId|id("r"))
    elif $op=="snapshot" then keys_only(["projectId"]) and ((has("projectId")|not) or (.projectId|id("p")))
    elif $op=="configure" then keys_only(["projectId","definition","expectedRevision"]) and (.projectId|id("p")) and (.definition|type)=="object"
    elif $op=="remove" then keys_only(["projectId","actionId","expectedRevision"]) and (.projectId|id("p")) and (.actionId|id("a"))
    elif (["availability","activate","deactivate"]|index($op))!=null then .=={}
    else false end' "$scratch/request" >/dev/null 2>&1
}

# Serialize dispatch/lifecycle independently of the transaction lock (never nest it).
runtime_gate() {
  local current
  project_actions_dispatch_lock || runtime_error "$action_lock_error" 'Dispatch authority is busy or its coordination path is unsafe.'
  current=$(project_actions_generation)
  case "$operation" in
    activate | deactivate) ;;
    inspect | refresh | stop | logs)
      if [[ $current == draining:* && $current == "$action_generation" ]]; then
        action_generation=$current
        export ARANEA_ACTION_GENERATION=$current ARANEA_ACTION_DRAIN=1
      else
        [[ $current == "$action_generation" && $current != removed:* ]] || runtime_error ACTION_REMOVED 'This request belongs to retired action ingress.'
      fi
      ;;
    *) [[ $current == "$action_generation" && $current != removed:* && $current != draining:* ]] || runtime_error ACTION_REMOVED 'Action ingress has been retired.' ;;
  esac
}

# Explicitly close the dispatch descriptor before potentially slow presentation I/O.
runtime_ungate() {
  [[ -z ${dispatch_fd:-} ]] || exec {dispatch_fd}>&-
  dispatch_fd=''
}

# Child transports never inherit authority descriptors, including detached clients.
runtime_transport() (
  local duration=$1
  shift
  [[ -z ${dispatch_fd:-} ]] || exec {dispatch_fd}>&-
  timeout -k 0.2s "$duration" "$@"
)

# Call the independently locked store, retaining its exact success/failure envelope.
runtime_store() {
  if ! ARANEA_ACTION_DISPATCH_FD=${dispatch_fd:-} "$script_dir/aranea-project-action-store" "$@" >"$scratch/next"; then
    cat "$scratch/next"
    exit 1
  fi
  mv "$scratch/next" "$scratch/result"
}

# Load an exact retained run without consulting a possibly removed registry project.
runtime_load() {
  runtime_store snapshot
  jq -ce --slurpfile q "$scratch/request" '.state.runs[]|select(.id==$q[0].runId)' "$scratch/result" >"$scratch/run" || runtime_error RUN_NOT_FOUND 'The retained run was not found.'
  jq --slurpfile r "$scratch/run" '.run=$r[0]' "$scratch/result" >"$scratch/next"
  mv "$scratch/next" "$scratch/result"
}

# Trusted absolute search directories exclude the checkout and caller working tree.
runtime_path() {
  local entry resolved excluded root observed_root run_cwd search_path=$action_search_path
  local -a entries roots
  roots=("$(pwd -P)")
  if [[ -s $scratch/run ]]; then
    run_cwd=$(jq -r .cwd "$scratch/run")
    roots+=("$run_cwd")
    if [[ -z ${checkout_path:-} ]]; then
      if projects_registry_git_value observed_root -C "$run_cwd" rev-parse --show-toplevel 2>/dev/null && observed_root=$(projects_registry_path "$observed_root"); then
        checkout_path=$observed_root
      else
        # A vanished checkout cannot authorize repository-adjacent helper search.
        search_path=/usr/local/bin:/usr/bin
      fi
    fi
  fi
  [[ -z ${checkout_path:-} ]] || roots+=("$checkout_path")
  IFS=: read -r -a entries <<<"$search_path:/usr/local/bin:/usr/bin"
  safe_path=''
  for entry in "${entries[@]}"; do
    [[ $entry == /* && -d $entry ]] || continue
    resolved=$(realpath -e -- "$entry") || continue
    excluded=false
    for root in "${roots[@]}"; do
      [[ $resolved != "$root" && $resolved != "$root/"* ]] || excluded=true
    done
    [[ $excluded == false ]] || continue
    case ":$safe_path:" in *":$resolved:"*) continue ;; esac
    safe_path+=${safe_path:+:}$resolved
  done
}

# Resolve executable files with trusted bootstrap utilities and a sanitized PATH.
runtime_find() {
  local name=$1 entry candidate
  local -a entries
  IFS=: read -r -a entries <<<"$safe_path"
  for entry in "${entries[@]}"; do
    candidate=$entry/$name
    [[ -f $candidate && -x $candidate ]] || continue
    candidate=$(realpath -e -- "$candidate") || continue
    [[ -z ${checkout_path:-} || ($candidate != "$checkout_path" && $candidate != "$checkout_path/"*) ]] || continue
    printf '%s\n' "$entry/$name"
    return
  done
  return 1
}

# Resolve all effect boundaries outside the action checkout; no test-only overrides.
runtime_tools() {
  runtime_path
  ctl=$(runtime_find systemctl || true)
  runner=$(runtime_find systemd-run || true)
  journal=$(runtime_find journalctl || true)
  curl_tool=$(runtime_find curl || true)
  opener=$(runtime_find xdg-open || true)
}

# A responsive manager and systemd-run >=254 are required before accepting intent.
runtime_available() {
  [[ -n $ctl && -n $runner ]] || return 1
  runtime_transport 2s "$ctl" --user --no-ask-password show --property=Version >"$scratch/version" 2>/dev/null || return 1
  [[ $(cat "$scratch/version") =~ ^Version=([0-9]+) ]] && ((BASH_REMATCH[1] >= 254)) || return 1
  runtime_transport 2s "$runner" --version >"$scratch/version" 2>/dev/null || return 1
  [[ $(head -1 "$scratch/version") =~ ^systemd\ ([0-9]+) ]] && ((BASH_REMATCH[1] >= 254))
}

# Publish dependency availability without pretending that a missing manager is idle.
runtime_availability() {
  local available=false
  runtime_available && available=true
  jq -cn --argjson a "$available" --argjson j "$([[ -n $journal ]] && echo true || echo false)" --argjson c "$([[ -n $curl_tool ]] && echo true || echo false)" --argjson o "$([[ -n $opener ]] && echo true || echo false)" '{ok:true,state:null,error:null,availability:{execution:$a,userManager:$a,journal:$j,previewProbe:$c,opener:$o}}' >"$scratch/result"
}

# Guarded observations compare both the loaded global revision and invocation pin.
runtime_observe() {
  jq -n --slurpfile r "$scratch/run" --slurpfile s "$scratch/result" --slurpfile p "$scratch/patch" '{action:"observe",expectedRevision:$s[0].state.revision,args:{runId:$r[0].id,expectedInvocationId:$r[0].invocationId,patch:$p[0]}}' | runtime_store mutate
  jq '.run' "$scratch/result" >"$scratch/run"
}

# Uncertainty protects the original acceptance indefinitely and never resubmits it.
runtime_uncertain() {
  local code=$1
  jq -cn --arg c "$code" '{state:"completed",outcome:"partial",processState:"unconfirmed",readiness:"unknown",error:{code:$c,message:"Exact process control could not be confirmed.",recovery:"Refresh this retained run; do not repeat the command."}}' >"$scratch/patch"
  runtime_observe
}

# Prove the exact transient unit and boot, then pin/check its manager invocation.
runtime_proof() {
  local key value unit marker invocation boot show_status=0
  proof_missing=false
  proof_error=RUN_IDENTITY_LOST
  unit=$(jq -r .unitName "$scratch/run")
  marker=$(jq -r '"Aranea project action "+(.id|ltrimstr("r-"))+" "+.definitionHash' "$scratch/run")
  boot=$(cat /proc/sys/kernel/random/boot_id)
  [[ $(jq -r .bootId "$scratch/run") == "$boot" ]] || return 1
  proof_error=OBSERVATION_UNAVAILABLE
  [[ -n $ctl ]] || return 1
  runtime_transport 2s "$ctl" --user --no-ask-password show --property=Id,LoadState,Transient,Description,InvocationID,ActiveState,SubState,Result,ExecMainCode,ExecMainStatus -- "$unit" >"$scratch/show" 2>/dev/null || show_status=$?
  [[ $show_status == 0 || $show_status == 1 ]] || return 1
  [[ $(stat -c %s "$scratch/show") -le 16384 ]] || return 1
  declare -gA unit_props=()
  while IFS='=' read -r key value; do
    case "$key" in Id | LoadState | Transient | Description | InvocationID | ActiveState | SubState | Result | ExecMainCode | ExecMainStatus) ;;
    *) return 1 ;;
    esac
    [[ ! -v unit_props[$key] ]] || return 1
    unit_props[$key]=$value
  done <"$scratch/show"
  [[ ${#unit_props[@]} == 10 ]] || return 1
  if [[ ${unit_props[Id]} == "$unit" && ${unit_props[LoadState]} == not-found && ${unit_props[ActiveState]} == inactive ]]; then
    proof_missing=true
    return 1
  fi
  [[ $show_status == 0 ]] || return 1
  proof_error=RUN_IDENTITY_LOST
  invocation=${unit_props[InvocationID]}
  [[ ${unit_props[Id]} == "$unit" && ${unit_props[LoadState]} == loaded && ${unit_props[Transient]} == yes && ${unit_props[Description]} == "$marker" && $invocation =~ ^[0-9a-f]{32}$ ]] || return 1
  [[ $(jq -r .invocationId "$scratch/run") == null || $(jq -r .invocationId "$scratch/run") == "$invocation" ]] || return 1
  proof_error=OBSERVATION_UNAVAILABLE
  [[ ${unit_props[ExecMainCode]} =~ ^[0-3]$ && ${unit_props[ExecMainStatus]} =~ ^[0-9]{1,3}$ ]] || return 1
  ((10#${unit_props[ExecMainStatus]} <= 255)) || return 1
  proof_error=''
}

# Persisted terminal proof can authorize history when the manager proves unit absence.
# An existing mismatched unit, unknown transport or old boot never grants this path.
runtime_read_proof() {
  runtime_proof && return 0
  [[ $proof_missing == true ]] || return 1
  jq -e '(.submissionUnconfirmed|not) and .invocationId!=null and .state=="completed" and (.processState=="succeeded" or .processState=="failed" or .processState=="stopped")' "$scratch/run" >/dev/null || return 1
  [[ $(jq .definitionSnapshot "$scratch/run" | project_actions_definition_hash) == "$(jq -r .definitionHash "$scratch/run")" ]]
}

# Distinguish persisted main-process exit evidence from completed cgroup cleanup.
runtime_terminal_evidence() {
  jq -e '.state=="completed" and .invocationId!=null and (.processState=="succeeded" or .processState=="failed" or .processState=="stopped")' "$scratch/run" >/dev/null
}

# Keep the recorded exit result protected when unit/cgroup cleanup cannot be proved.
runtime_cleanup_uncertain() {
  local code=$1
  jq --arg c "$code" '{submissionUnconfirmed:true,outcome:"partial",readiness:"unknown",error:(if .error.code=="TIMEOUT" then .error else {code:$c,message:"Main-process exit is recorded, but unit cleanup is unconfirmed.",recovery:"Refresh or Stop this retained run before starting another or removing actions."} end)}' "$scratch/run" >"$scratch/patch"
  runtime_observe
  runtime_error "$code" 'Main-process exit is recorded, but exact unit cleanup remains unconfirmed.'
}

# Clear protection only after a terminal receipt plus exact inactive/absent evidence.
runtime_cleanup_complete() {
  jq '{submissionUnconfirmed:false,outcome:(if .processState=="failed" then "failed" else "observed" end),error:(if .error.code=="TIMEOUT" then .error else null end)}' "$scratch/run" >"$scratch/patch"
  runtime_observe
}

# Main exit is durable before release; stop failure cannot discard cgroup authority.
runtime_release() {
  runtime_terminal_evidence || runtime_error STOP_UNCONFIRMED 'No persisted main-process terminal evidence is available.'
  if ! runtime_proof; then
    if [[ $proof_missing == true ]]; then
      runtime_cleanup_complete
      return
    fi
    runtime_cleanup_uncertain "$proof_error"
  fi
  if [[ ${unit_props[ActiveState]} != inactive ]]; then
    runtime_transport 5s "$ctl" --user --no-ask-password stop -- "$(jq -r .unitName "$scratch/run")" >/dev/null 2>&1 || true
    if ! runtime_proof; then
      if [[ $proof_missing == true ]]; then
        runtime_cleanup_complete
        return
      fi
      runtime_cleanup_uncertain "$proof_error"
    fi
    [[ ${unit_props[ActiveState]} == inactive ]] || runtime_cleanup_uncertain STOP_UNCONFIRMED
  fi
  runtime_cleanup_complete
  # Inactive is durable; recheck identity before best-effort metadata reset.
  runtime_proof || return 0
  [[ ${unit_props[ActiveState]} == inactive ]] || return 0
  runtime_transport 2s "$ctl" --user --no-ask-password reset-failed -- "$(jq -r .unitName "$scratch/run")" >/dev/null 2>&1 || true
}

# Interpret actual service state; active/exited is terminal, never a running process.
runtime_refresh() {
  local process outcome code=null signal=null error=null terminal=false
  if runtime_terminal_evidence; then
    if jq -e '.submissionUnconfirmed' "$scratch/run" >/dev/null; then runtime_release; fi
    return 0
  fi
  if ! runtime_proof; then
    local failure=$proof_error
    runtime_uncertain "$failure"
    runtime_error "$failure" 'The exact owned invocation could not be observed.'
  fi
  case "${unit_props[ActiveState]}/${unit_props[SubState]}" in
    active/running) process=running outcome=observed ;;
    active/exited | inactive/dead | failed/failed)
      terminal=true process=failed outcome=failed
      if [[ ${unit_props[ExecMainCode]} == 1 ]]; then code=${unit_props[ExecMainStatus]}; fi
      if [[ ${unit_props[ExecMainCode]} == 2 || ${unit_props[ExecMainCode]} == 3 ]] && ((10#${unit_props[ExecMainStatus]} <= 128)); then signal=${unit_props[ExecMainStatus]}; fi
      if [[ ${unit_props[ActiveState]} == inactive && $(jq -r .stopRequested "$scratch/run") == true ]]; then
        process=stopped outcome=observed
      elif [[ ${unit_props[Result]} == success && $code == 0 ]]; then
        process=succeeded outcome=observed
      fi
      if [[ ${unit_props[Result]} == timeout ]]; then error='{"code":"TIMEOUT","message":"The configured command time limit expired.","recovery":"Review the command or its configured timeout."}'; fi
      ;;
    *)
      runtime_uncertain OBSERVATION_PENDING
      return
      ;;
  esac
  jq -cn --arg p "$process" --arg o "$outcome" --arg i "${unit_props[InvocationID]}" --argjson c "$code" --argjson s "$signal" --argjson e "$error" --argjson terminal "$terminal" '{invocationId:$i,state:"completed",outcome:(if $terminal then "partial" else $o end),processState:$p,readiness:"unknown",exitCode:$c,exitSignal:$s,error:$e,submissionUnconfirmed:$terminal}' >"$scratch/patch"
  runtime_observe
  if [[ $terminal == true ]]; then runtime_release; else runtime_probe; fi
}

# Probe reachability independently, with no locks and no curl config/proxy/redirects.
runtime_probe() {
  local url readiness=unknown
  url=$(jq -r '.definitionSnapshot|if .kind=="service" then .previewUrl else null end' "$scratch/run")
  [[ $url != null ]] || return 0
  runtime_ungate
  if [[ -n $curl_tool ]]; then
    readiness=unreachable
    if runtime_transport 2s "$curl_tool" -q --silent --output /dev/null --noproxy '*' --max-time 1 --connect-timeout 1 --max-redirs 0 --proto '=http,https' -- "$url" >/dev/null 2>&1; then readiness=reachable; fi
  fi
  jq -cn --arg r "$readiness" '{readiness:$r}' >"$scratch/patch"
  runtime_observe
}

# Stop only an exact proof, then require terminal observation before reporting success.
runtime_stop() {
  if jq -e '(.submissionUnconfirmed|not) and (.processState=="succeeded" or .processState=="failed" or .processState=="stopped")' "$scratch/run" >/dev/null; then return; fi
  jq -n --slurpfile r "$scratch/run" '{action:"request-stop",args:{runId:$r[0].id}}' | runtime_store mutate
  jq '.run' "$scratch/result" >"$scratch/run"
  if runtime_terminal_evidence; then
    runtime_release
    return 0
  fi
  if ! runtime_proof; then
    local failure=$proof_error
    runtime_uncertain "$failure"
    runtime_error "$failure" 'The retained run cannot be safely stopped without its exact identity.'
  fi
  # Pin first adoption before issuing any stop effect.
  jq -cn --arg i "${unit_props[InvocationID]}" '{invocationId:$i}' >"$scratch/patch"
  runtime_observe
  if ! runtime_transport 5s "$ctl" --user --no-ask-password stop -- "$(jq -r .unitName "$scratch/run")" >/dev/null 2>&1; then
    runtime_uncertain STOP_UNCONFIRMED
    runtime_error STOP_UNCONFIRMED 'The user manager did not confirm the stop.'
  fi
  runtime_refresh
  jq -e '(.submissionUnconfirmed|not) and (.processState=="succeeded" or .processState=="failed" or .processState=="stopped")' "$scratch/run" >/dev/null || runtime_error STOP_UNCONFIRMED 'The run is not yet confirmed inactive.'
}

# Resolve receipt replay before default checkout, otherwise freshly verify Git/cwd.
runtime_start() {
  local id action definition_hash cwd executable request_id reused
  runtime_store snapshot
  request_id=$(jq -r .requestId "$scratch/request")
  if jq -e --arg id "$request_id" 'any(.state.requests[];.requestId==$id)' "$scratch/result" >/dev/null; then
    jq --arg id "$request_id" '.state as $s | ($s.requests[]|select(.requestId==$id)|.runId) as $r | .run=($s.runs[]|select(.id==$r)) | .reused=true' "$scratch/result" >"$scratch/next"
    mv "$scratch/next" "$scratch/result"
    jq -e --slurpfile q "$scratch/request" '.run.projectId==$q[0].projectId and .run.actionId==$q[0].actionId and (($q[0]|has("checkoutId")|not) or .run.checkoutId==$q[0].checkoutId)' "$scratch/result" >/dev/null || runtime_error REQUEST_CONFLICT 'This request ID already refers to another action or checkout.'
    return
  fi
  id=$(jq -r .projectId "$scratch/request") action=$(jq -r .actionId "$scratch/request")
  jq -ce --arg p "$id" --arg a "$action" '.state.definitions[]|select(.projectId==$p and .id==$a)' "$scratch/result" >"$scratch/definition" || runtime_error ACTION_NOT_FOUND 'The saved action was not found.'
  jq -e --slurpfile d "$scratch/definition" '(has("expectedDefinitionRevision")|not) or .expectedDefinitionRevision==$d[0].revision' "$scratch/request" >/dev/null || runtime_error ACTION_CONFLICT 'The displayed action definition changed; review it before starting.'
  "$script_dir/aranea-project-store" snapshot >"$scratch/projects-result" || runtime_error REGISTRY_INVALID 'The project registry could not be read.'
  jq '.state' "$scratch/projects-result" >"$scratch/projects"
  jq -e --arg p "$id" 'any(.projects[];.id==$p)' "$scratch/projects" >/dev/null || runtime_error PROJECT_NOT_FOUND 'The registered project was removed.'
  jq --slurpfile p "$scratch/projects" '. as $q | .checkoutId //= ($p[0].projects[]|select(.id==$q.projectId)|.lastCheckoutId)' "$scratch/request" >"$scratch/selected"
  mv "$scratch/selected" "$scratch/request"
  checkout_path=$(jq -r --slurpfile q "$scratch/request" '.projects[]|select(.id==$q[0].projectId)|.checkouts[]|select(.id==$q[0].checkoutId)|.path' "$scratch/projects")
  [[ -n $checkout_path ]] || runtime_error CHECKOUT_INVALID 'The exact selected checkout is no longer registered.'
  cwd=$(realpath -e -- "$checkout_path/$(jq -r .cwdRelative "$scratch/definition")") || runtime_error CHECKOUT_INVALID 'The configured working folder is unavailable.'
  definition_hash=$(project_actions_definition_hash <"$scratch/definition")
  jq --slurpfile d "$scratch/definition" --arg cwd "$cwd" --arg hash "$definition_hash" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" '{action:"reserve",args:(del(.expectedDefinitionRevision) + {cwd:$cwd,definitionRevision:$d[0].revision,definitionHash:$hash,bootId:$boot})}' "$scratch/request" >"$scratch/reserve"
  project_actions_checkout "$scratch/reserve" "$scratch/projects" "$scratch/definition" || runtime_error CHECKOUT_INVALID 'The exact checkout or canonical working folder changed.'
  # A new receipt may reuse protected intent even when observation is unavailable.
  # The store still revalidates the fresh registry, definition and exact checkout.
  if jq -e --slurpfile q "$scratch/request" 'any(.state.runs[];.projectId==$q[0].projectId and .checkoutId==$q[0].checkoutId and .actionId==$q[0].actionId and (.submissionUnconfirmed or .processState=="pending" or .processState=="running" or .processState=="unconfirmed"))' "$scratch/result" >/dev/null; then
    runtime_store mutate <"$scratch/reserve"
    return 0
  fi
  runtime_tools
  runtime_available || runtime_error EXECUTION_UNAVAILABLE 'A systemd user manager and systemd-run version 254 or newer are required.'
  executable=$(jq -r '.argv[0]' "$scratch/definition")
  case "$executable" in
    /*) executable=$(realpath -e -- "$executable") || runtime_error EXECUTABLE_MISSING 'The configured executable is unavailable.' ;;
    ./*)
      executable=$(realpath -e -- "$cwd/$executable") || runtime_error EXECUTABLE_MISSING 'The configured executable is unavailable.'
      [[ $executable == "$checkout_path/"* ]] || runtime_error CHECKOUT_INVALID 'The explicit repository executable escapes the checkout.'
      ;;
    *) executable=$(runtime_find "$executable") || runtime_error EXECUTABLE_MISSING 'The executable was not found on the safe search path.' ;;
  esac
  [[ -f $executable && -x $executable ]] || runtime_error EXECUTABLE_MISSING 'The configured executable is not executable.'
  runtime_store mutate <"$scratch/reserve"
  reused=$(jq -r .reused "$scratch/result")
  [[ $reused != true ]] || return 0
  jq '.run' "$scratch/result" >"$scratch/run"
  local -a argv flags
  mapfile -d '' -t argv < <(jq -j '.definitionSnapshot.argv[]|.,"\u0000"' "$scratch/run")
  argv[0]=$executable
  flags=(--user --no-ask-password --quiet "--unit=$(jq -r .unitName "$scratch/run")" "--description=$(jq -r '"Aranea project action "+(.id|ltrimstr("r-"))+" "+.definitionHash' "$scratch/run")" --service-type=exec --remain-after-exit --expand-environment=no --property=Restart=no --property=KillMode=control-group --property=TimeoutStopSec=5s --property=NoNewPrivileges=yes --property=StandardInput=null --property=StandardOutput=journal --property=StandardError=journal "--working-directory=$cwd" "--setenv=PATH=$safe_path")
  [[ $(jq -r .definitionSnapshot.kind "$scratch/run") != command ]] || flags+=("--property=RuntimeMaxSec=$(jq -r .definitionSnapshot.timeoutSeconds "$scratch/run")s")
  # Intent is durable; even a transport error can mean the manager accepted it.
  if ! runtime_transport 2s "$runner" "${flags[@]}" -- "${argv[@]}" >"$scratch/launch" 2>&1; then
    runtime_uncertain SUBMISSION_UNCONFIRMED
    jq '.reused=false' "$scratch/result" >"$scratch/next"
    mv "$scratch/next" "$scratch/result"
    return
  fi
  runtime_refresh
  jq '.reused=false' "$scratch/result" >"$scratch/next"
  mv "$scratch/next" "$scratch/result"
}

# Read bounded JSON journal records, independently filtering the pinned invocation.
runtime_logs() {
  [[ -n $journal ]] || runtime_error JOURNAL_UNAVAILABLE 'Install journalctl to read the local journal.'
  local invocation unit boot transport_lost=false
  boot=$(jq -r ' .bootId|gsub("-";"")' "$scratch/run")
  invocation=$(jq -r .invocationId "$scratch/run") unit=$(jq -r .unitName "$scratch/run")
  [[ $invocation != null ]] || runtime_error RUN_IDENTITY_LOST 'Refresh to persist the invocation before reading logs.'
  if ! runtime_transport 2s "$journal" --user --no-pager --quiet --all --output=json --output-fields=MESSAGE,_SYSTEMD_INVOCATION_ID,_SYSTEMD_USER_UNIT,_SYSTEMD_UNIT,_BOOT_ID --lines=200 "--unit=$unit" "_SYSTEMD_INVOCATION_ID=$invocation" "_BOOT_ID=$boot" 2>/dev/null | head -c 1048577 >"$scratch/journal"; then
    transport_lost=true
    [[ -s $scratch/journal ]] || runtime_error JOURNAL_UNAVAILABLE 'The local journal could not be read.'
  fi
  jq -Rn --arg i "$invocation" --arg u "$unit" --arg b "$boot" '
    # Decode real journal byte arrays, rejecting overlong/surrogate/out-of-range UTF-8.
    def utf8_bytes:
      . as $bytes | reduce range(0;length) as $n ({points:[],skip:0,lost:false};
        if .skip>0 then .skip-=1 else $bytes[$n] as $lead
          | (if $lead<128 then 1 elif $lead>=194 and $lead<=223 then 2 elif $lead>=224 and $lead<=239 then 3 elif $lead>=240 and $lead<=244 then 4 else 0 end) as $width
          | $bytes[$n:$n+$width] as $chunk
          | (if $width>0 and ($chunk|length)==$width and all($chunk[1:][];.>=128 and .<=191)
             then reduce $chunk[1:][] as $c ((if $width==1 then $lead elif $width==2 then $lead-192 elif $width==3 then $lead-224 else $lead-240 end); .*64+$c-128) else -1 end) as $cp
          | if $cp>=([0,0,128,2048,65536][$width]) and $cp<=1114111 and ($cp<55296 or $cp>57343)
            then .points+=[$cp] | .skip=($width-1)
            else .points+=[65533] | .lost=true end
        end) | {text:(.points|implode),lost};
    def message:
      if type=="string" then {text:.,lost:false}
      elif type=="array" and all(.[];type=="number" and .==floor and .>=0 and .<=255) then utf8_bytes
      else {text:"[Journal message unavailable]",lost:true} end;
    [inputs | (try {record:fromjson} catch {lost:true})
      | if .lost or (.record|type)!="object" then {lost:true}
        elif .record._SYSTEMD_INVOCATION_ID==$i and .record._BOOT_ID==$b and (.record._SYSTEMD_USER_UNIT==$u or .record._SYSTEMD_UNIT==$u)
        then (try (.record.MESSAGE|message) catch {text:"[Journal message unavailable]",lost:true})
        else empty end]
    | (length>=200) as $full | .[:200] as $records
    | [$records[]|.text//empty] | join("\n") | gsub("\u001b\\[[0-?]*[ -/]*[@-~]";"") | gsub("[\u0000-\u0008\u000b-\u001f\u007f-\u009f]";"")
    | {output:.,truncated:($full or any($records[];.lost) or utf8bytelength>262144)}' <"$scratch/journal" >"$scratch/output"
  # Byte limit is applied before JSON encoding; incomplete UTF-8 is decoded safely.
  jq -j .output "$scratch/output" | head -c 262144 >"$scratch/text" || true
  jq --rawfile t "$scratch/text" --slurpfile o "$scratch/output" --argjson lost "$transport_lost" --argjson clipped "$([[ $(stat -c %s "$scratch/journal") -gt 1048576 ]] && echo true || echo false)" '.output=$t | until((.output|utf8bytelength)<=262144; .output|=.[0:-1]) | .truncated=($o[0].truncated or $clipped or $lost) | .availability={journal:true}' "$scratch/result" >"$scratch/next"
  mv "$scratch/next" "$scratch/result"
}

# Opening a configured preview requires exact active service proof, never a port claim.
runtime_preview() {
  [[ ${unit_props[ActiveState]} == active && ${unit_props[SubState]} == running ]] || runtime_error PREVIEW_UNAVAILABLE 'The exact service is not currently running.'
  local url
  url=$(jq -r '.definitionSnapshot|if .kind=="service" then .previewUrl else null end' "$scratch/run")
  [[ $url != null && -n $opener ]] || runtime_error PREVIEW_UNAVAILABLE 'Configure a service preview URL and install xdg-open.'
  runtime_transport 2s "$opener" "$url" >/dev/null 2>&1 || runtime_error PREVIEW_UNAVAILABLE 'The browser opener did not acknowledge this URL.'
}

# Fence ingress first; only proven stopped runs permit payload removal and activation.
runtime_deactivate() {
  runtime_store retire
  action_generation=$(project_actions_generation)
  export ARANEA_ACTION_GENERATION=$action_generation ARANEA_ACTION_DRAIN=1
  runtime_store snapshot
  jq -r '.state.runs[]|select(.submissionUnconfirmed or .processState=="pending" or .processState=="running" or .processState=="unconfirmed")|.id' "$scratch/result" >"$scratch/drain"
  while IFS= read -r id; do
    jq -cn --arg r "$id" '{runId:$r}' >"$scratch/request"
    runtime_load
    checkout_path=''
    runtime_tools
    runtime_stop
  done <"$scratch/drain"
  runtime_store deactivate
  cat "$scratch/result"
}
