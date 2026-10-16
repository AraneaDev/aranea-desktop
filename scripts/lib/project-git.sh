#!/usr/bin/env bash
# Mutating Git operations. Identity is proved with the read-only observer's
# checks; the user's own Git config, credentials and hooks then run without
# prompts, bounded in time, one operation per repository at a time.
# shellcheck disable=SC2154,SC2034

# Emit one failure envelope and stop.
project_git_fail() {
  jq -cn --arg code "$1" --arg message "$2" --arg recovery "$3" \
    '{ok:false,data:null,error:{code:$code,message:$message,recovery:$recovery}}'
  exit 1
}

# Emit one success envelope and stop.
project_git_ok() {
  jq -cn --argjson data "$1" '{ok:true,data:$data,error:null}'
  exit 0
}

# Run the user's Git without prompts; output lands in $git_tmp/out and err.
project_git_user() {
  local seconds=$1
  shift
  (
    local variable
    for variable in "${!GIT_@}"; do [[ $variable == GIT_SSH_COMMAND || $variable == GIT_SSH ]] || unset "$variable"; done
    unset SSH_ASKPASS
    export GIT_TERMINAL_PROMPT=0 SSH_ASKPASS_REQUIRE=never GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes"
    exec timeout -k 1s "${seconds}s" git -c credential.interactive=never "$@"
  ) </dev/null >"$git_tmp/out" 2>"$git_tmp/err"
}

# Translate a failed Git call into a stable code.
project_git_classify() {
  local status=$1 first
  if ((status == 124 || status == 137)); then
    project_git_fail GIT_TIMEOUT 'Git did not finish in time.' 'Check the network connection and retry.'
  fi
  if grep -qiE 'terminal prompts disabled|could not read (username|password)|authentication failed|permission denied \(|host key verification failed' "$git_tmp/err"; then
    project_git_fail AUTH_REQUIRED 'Git needs credentials for this remote.' 'Run git fetch once in a terminal to sign in.'
  fi
  first=$(grep -m1 -E '^(fatal|error): ' "$git_tmp/err" | cut -c1-300 || true)
  project_git_fail GIT_ERROR "${first:-Git failed.}" 'Inspect this checkout in a terminal, then refresh.'
}

# Remote of the current branch's upstream, else origin, else the only remote.
project_git_remote() {
  local branch remote
  local -a remotes=()
  branch=$(projects_registry_git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  if [[ -n $branch ]] && remote=$(projects_registry_git -C "$path" config --get "branch.$branch.remote" 2>/dev/null) && [[ -n $remote && $remote != . ]]; then
    printf '%s\n' "$remote"
    return
  fi
  mapfile -t remotes < <(projects_registry_git -C "$path" remote 2>/dev/null)
  if printf '%s\n' "${remotes[@]}" | grep -qx origin; then
    printf 'origin\n'
  elif ((${#remotes[@]} == 1)); then
    printf '%s\n' "${remotes[0]}"
  fi
}

# Fetch one named remote within the network limit.
project_git_fetch_remote() {
  local status=0
  project_git_user "$project_git_network_seconds" -C "$path" fetch --quiet -- "$1" || status=$?
  ((status == 0)) || project_git_classify "$status"
}

project_git_fetch() {
  local remote
  remote=$(project_git_remote)
  [[ -n $remote ]] || project_git_fail NO_REMOTE 'This repository has no remote to fetch from.' 'Add a remote in a terminal, then retry.'
  project_git_fetch_remote "$remote"
  project_git_ok "$(jq -cn --arg p "$project" --arg c "$checkout" --arg r "$remote" '{projectId:$p,checkoutId:$c,remote:$r}')"
}

project_git_pull() {
  local branch remote from to status=0
  branch=$(projects_registry_git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  remote=''
  [[ -z $branch ]] || remote=$(projects_registry_git -C "$path" config --get "branch.$branch.remote" 2>/dev/null || true)
  if [[ -z $branch || -z $remote ]] || ! projects_registry_git -C "$path" rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1; then
    project_git_fail NO_UPSTREAM 'This branch does not track a remote branch.' 'Push the branch with an upstream in a terminal, then retry.'
  fi
  project_git_fetch_remote "$remote"
  from=$(projects_registry_git -C "$path" rev-parse HEAD)
  project_git_user "$project_git_local_seconds" -C "$path" merge --ff-only --quiet '@{upstream}' || status=$?
  if ((status != 0)); then
    if grep -qi 'would be overwritten' "$git_tmp/err"; then
      project_git_fail LOCAL_CHANGES 'Local changes would be overwritten by the pull.' 'Commit or stash those changes in a terminal, then retry.'
    elif grep -qiE 'not possible to fast-forward|diverg' "$git_tmp/err"; then
      project_git_fail NOT_FAST_FORWARD 'Branches have diverged; merge or rebase in a terminal.' 'Merge or rebase in a terminal, then refresh.'
    fi
    project_git_classify "$status"
  fi
  to=$(projects_registry_git -C "$path" rev-parse HEAD)
  project_git_ok "$(jq -cn --arg p "$project" --arg c "$checkout" --arg r "$remote" --arg f "$from" --arg t "$to" '{projectId:$p,checkoutId:$c,remote:$r,from:$f,to:$t,updated:($f != $t)}')"
}

# Hold one exclusive lock per Git common directory for the whole operation.
project_git_lock() {
  local dir key
  dir="$(aranea_state_root)/git-locks"
  mkdir -p -- "$dir" || project_git_fail GIT_ERROR 'Cannot create the Git lock directory.' 'Check state-directory permissions and retry.'
  key=$(printf '%s' "$common" | sha256sum | cut -c1-32)
  exec {project_git_lock_fd}>"$dir/$key.lock"
  flock -w 75 "$project_git_lock_fd" || project_git_fail GIT_BUSY 'Another Git operation on this repository is still running.' 'Wait for it to finish, then retry.'
}

# Temporary stubs; Task 3 replaces them with the task checkout operations.
project_git_task_create() {
  project_git_fail INVALID_REQUEST 'Not available yet.' 'Update Aranea.'
}

project_git_task_remove() {
  project_git_fail INVALID_REQUEST 'Not available yet.' 'Update Aranea.'
}

project_git_main() {
  local operation=${1:-} project='' checkout='' branch='' check=false confirm=false json=false dependency
  local path common primary git_state_failure_code=CHECKOUT_INVALID
  project_git_network_seconds=${ARANEA_GIT_NETWORK_SECONDS:-60}
  project_git_local_seconds=15
  for dependency in jq git timeout flock mktemp sha256sum realpath; do
    command -v "$dependency" >/dev/null || project_git_fail DEPENDENCY_MISSING "Install $dependency to run Git operations." 'Install the missing dependency and retry.'
  done
  case "$operation" in fetch | pull | task-create | task-remove) shift ;; *) project_git_fail INVALID_REQUEST 'Unsupported Git operation.' 'Use fetch, pull, task-create or task-remove.' ;; esac
  while (($#)); do
    case "$1" in
      --project | --checkout | --branch)
        [[ $# -ge 2 && -n $2 ]] || project_git_fail INVALID_REQUEST "Provide a value for $1." 'Retry with every required value.'
        case "$1" in --project) project=$2 ;; --checkout) checkout=$2 ;; --branch) branch=$2 ;; esac
        shift 2
        ;;
      --check) check=true; shift ;;
      --confirm-unpushed) confirm=true; shift ;;
      --json) json=true; shift ;;
      *) project_git_fail INVALID_REQUEST 'Unsupported Git argument.' 'Use --project, --checkout, --branch, --check, --confirm-unpushed and --json.' ;;
    esac
  done
  [[ -n $project && -n $checkout && $json == true ]] || project_git_fail INVALID_REQUEST 'Provide project and checkout IDs with --json.' 'Select a registered checkout and retry.'
  umask 077
  git_tmp=$(mktemp -d) || project_git_fail GIT_ERROR 'Cannot create a private scratch directory.' 'Check temporary-directory permissions and space.'
  git_state_tmp=$git_tmp
  git_state_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  trap 'rm -rf -- "$git_tmp"' EXIT
  if ! project_git_state_prove "$project" "$checkout" >"$git_tmp/proof"; then
    cat "$git_tmp/proof"
    exit 1
  fi
  project_git_lock
  case "$operation" in
    fetch) project_git_fetch ;;
    pull) project_git_pull ;;
    task-create) project_git_task_create ;;
    task-remove) project_git_task_remove ;;
  esac
}
