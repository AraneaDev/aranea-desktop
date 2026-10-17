#!/usr/bin/env bash
# Public adapter for task checkouts and Fetch/Pull; the helper owns all Git work.
# shellcheck disable=SC2154,SC2034

# Print the projectGit capability object and git/task operations.
project_git_cli_capabilities() {
  jq -cn '{projectGit:{schemaVersion:1,worktreeLocation:"<repo>-worktrees/<branch>",base:"remote default branch, else local main/master",pull:"fast-forward only",removeKeepsBranch:true,networkSeconds:60,localSeconds:15},operations:[
    {name:"projects.git.fetch",arguments:{projectId:{type:"string",required:true},checkout:{type:"string"}}},
    {name:"projects.git.pull",arguments:{projectId:{type:"string",required:true},checkout:{type:"string"}},description:"Fetch, then fast-forward only; never merges or stashes"},
    {name:"projects.git.push",arguments:{projectId:{type:"string",required:true},checkout:{type:"string"}},description:"Pushes only the checkout branch with --set-upstream; never forces"},
    {name:"projects.review",arguments:{projectId:{type:"string",required:true},checkout:{type:"string",required:true}},readOnly:true,description:"Read a task checkout review against the base; never fetches"},
    {name:"projects.review.mark",arguments:{projectId:{type:"string",required:true},checkout:{type:"string",required:true}},description:"Remember the current head of a task checkout as reviewed"},
    {name:"projects.task.new",arguments:{projectId:{type:"string",required:true},branch:{type:"string",required:true}},description:"New branch from the remote default branch in <repo>-worktrees/<branch>; selected, nothing launches"},
    {name:"projects.task.remove",arguments:{projectId:{type:"string",required:true},checkout:{type:"string",required:true},check:{type:"boolean"},"confirm-unpushed":{type:"boolean"}},description:"Removes a clean task checkout folder; keeps the branch"}]}'
}

# Record the reviewed head with the latest finished task time; an unreadable activity state means null.
project_git_cli_mark() {
  local project=$1 checkout=$2 head=$3 finished=null snapshot
  mark_data=''
  if snapshot=$("$script_dir/aranea-agent-store" snapshot 2>/dev/null </dev/null); then
    finished=$(jq -c --arg p "$project" --arg c "$checkout" '[.state.tasks[]?|select(.reportedState|IN("ready-for-review","finished","failed"))|select(.association.status == "registered" and .association.projectId == $p and .association.checkoutId == $c)|.lastReceivedAt]|max // null' <<<"$snapshot" 2>/dev/null) || finished=null
    [[ -n $finished ]] || finished=null
  fi
  mark_data=$(jq -cn --arg p "$project" --arg c "$checkout" --arg h "$head" --argjson t "$finished" '{projectId:$p,checkoutId:$c,head:$h,taskFinishedAt:$t}')
  projects_cli_store mutate <<<"$(jq -c '{action:"review-mark",args:.}' <<<"$mark_data")"
}

# Parse the public git/task commands and run the Git helper.
project_git_cli_main() {
  cli_json=false cli_operation_id='' cli_operation=aranea
  local arg group command project='' checkout='' branch='' check=false confirm=false option response operation message
  local -a words=() helper_args=()
  local -A supplied=()
  for arg in "$@"; do
    if [[ $arg == --json ]]; then
      [[ $cli_json == false ]] || projects_cli_usage
      cli_json=true
    else words+=("$arg"); fi
  done
  command -v jq >/dev/null || projects_cli_main "$@"
  set -- "${words[@]}"
  [[ $# -ge 3 && $1 == projects ]] || projects_cli_usage
  # "review P" reads; "review mark P" records. Both normalize to group review.
  if [[ $2 == review && $3 == mark ]]; then set -- projects review mark "${@:4}"; elif [[ $2 == review ]]; then set -- projects review read "${@:3}"; fi
  [[ $# -ge 4 ]] || projects_cli_usage
  group=$2 command=$3 project=$4
  [[ -n $project && $project != -* ]] || projects_cli_usage
  shift 4
  cli_operation="projects.$group.$command"
  [[ $command != read ]] || cli_operation="projects.$group"
  case "$group:$command" in
    git:fetch) operation=fetch ;;
    git:pull) operation=pull ;;
    git:push) operation=push ;;
    review:read) operation=review ;;
    review:mark) operation=review ;;
    task:new) operation=task-create ;;
    task:remove) operation=task-remove ;;
    *) projects_cli_usage ;;
  esac
  while (($#)); do
    option=$1
    [[ $option == --* && ! -v supplied[$option] ]] || projects_cli_usage
    supplied[$option]=1
    case "$group:$command:$option" in
      task:remove:--check)
        check=true
        shift
        continue
        ;;
      task:remove:--confirm-unpushed)
        confirm=true
        shift
        continue
        ;;
      git:fetch:--checkout | git:pull:--checkout | git:push:--checkout | review:read:--checkout | review:mark:--checkout | task:remove:--checkout | task:new:--branch) ;;
      *) projects_cli_usage ;;
    esac
    [[ $# -ge 2 && -n $2 && $2 != --* ]] || projects_cli_usage
    case "$option" in --checkout) checkout=$2 ;; --branch) branch=$2 ;; esac
    shift 2
  done
  [[ $command != new || -n $branch ]] || projects_cli_usage
  [[ $command != remove || -n $checkout ]] || projects_cli_usage
  [[ $group != review || -n $checkout ]] || projects_cli_usage
  projects_cli_event started '' '' 'Running Git operation.' '' '{}'
  if [[ -z $checkout ]]; then
    projects_cli_store snapshot
    checkout=$(jq -r --arg p "$project" '.projects[]|select(.id == $p)|.lastCheckoutId // empty' <<<"$cli_state")
    # A new task is proved and placed from the main checkout, never the selected one.
    [[ $operation != task-create ]] || checkout=$(jq -r --arg p "$project" '.projects[]|select(.id == $p)|.checkouts[]|select(.primary)|.id // empty' <<<"$cli_state")
    [[ -n $checkout ]] || projects_cli_fail PROJECT_NOT_FOUND 'The project is not registered.' 'List projects and use an existing project ID.'
  fi
  helper_args=("$operation" --project "$project" --checkout "$checkout")
  [[ -z $branch ]] || helper_args+=(--branch "$branch")
  [[ $check == false ]] || helper_args+=(--check)
  [[ $confirm == false ]] || helper_args+=(--confirm-unpushed)
  response=$("$script_dir/aranea-project-git" "${helper_args[@]}" --json </dev/null 2>/dev/null) || true
  if jq -e '.ok == true' <<<"$response" >/dev/null 2>&1; then
    if [[ $command == mark ]]; then
      project_git_cli_mark "$project" "$checkout" "$(jq -r .data.head <<<"$response")"
      projects_cli_finish observed '' 'Review marked.' "$mark_data"
    fi
    case "$operation" in
      fetch) message="Fetched $(jq -r .data.remote <<<"$response")." ;;
      pull) if jq -e .data.updated <<<"$response" >/dev/null; then message="Pulled $(jq -r .data.remote <<<"$response")."; else message='Already up to date.'; fi ;;
      push) message="Pushed $(jq -r .data.remote <<<"$response")." ;;
      review) message='Review read.' ;;
      task-create) message='Task checkout created.' ;;
      task-remove) if [[ $check == true ]]; then message='Removal checked.'; else message='Task checkout removed.'; fi ;;
    esac
    projects_cli_finish observed '' "$message" "$(jq -c .data <<<"$response")"
  fi
  if jq -e '.ok == false and (.error.code|type == "string")' <<<"$response" >/dev/null 2>&1; then
    projects_cli_fail "$(jq -r .error.code <<<"$response")" "$(jq -r .error.message <<<"$response")" "$(jq -r .error.recovery <<<"$response")"
  fi
  projects_cli_fail GIT_ERROR 'The Git helper did not answer.' 'Retry; if it persists, reinstall Aranea.'
}
