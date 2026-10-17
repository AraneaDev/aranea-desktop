#!/usr/bin/env bash
# Mutating Git operations. Identity is proved with the read-only observer's
# checks; the user's own Git config, credentials and hooks then run without
# prompts, bounded in time, one operation per repository at a time.
# shellcheck disable=SC2154,SC2034

# Emit one failure envelope and stop.
project_git_fail() {
  # A bounded local read that timed out outranks whatever it caused.
  if [[ -n ${git_tmp:-} && -e $git_tmp/read-timeout && $1 != GIT_TIMEOUT ]]; then
    set -- GIT_TIMEOUT 'Git did not finish in time.' 'Retry; if it persists, inspect this checkout in a terminal.'
  fi
  jq -cn --arg code "$1" --arg message "$2" --arg recovery "$3" \
    '{ok:false,data:null,error:{code:$code,message:$message,recovery:$recovery}}'
  exit 1
}

# Emit one success envelope and stop.
project_git_ok() {
  [[ -z ${git_tmp:-} || ! -e $git_tmp/read-timeout ]] || project_git_fail GIT_TIMEOUT 'Git did not finish in time.' 'Retry; if it persists, inspect this checkout in a terminal.'
  jq -cn --argjson data "$1" '{ok:true,data:$data,error:null}'
  exit 0
}

# Run a read-only, hook-free Git query within the local limit; a timeout leaves a marker.
project_git_read() {
  local status=0
  timeout -k 1s "${project_git_local_seconds}s" bash -c "$(declare -f projects_registry_git); projects_registry_git \"\$@\"" _ "$@" || status=$?
  if ((status == 124 || status == 137)); then : >"$git_tmp/read-timeout"; fi
  return "$status"
}

# Fail with GIT_TIMEOUT when any earlier bounded read timed out, before anything is changed.
project_git_alive() {
  [[ ! -e $git_tmp/read-timeout ]] || project_git_fail GIT_TIMEOUT 'Git did not finish in time.' 'Retry; if it persists, inspect this checkout in a terminal.'
}

# Print the user's own core.excludesFile (path-expanded) for the checkout, or nothing.
project_git_user_excludes() (
  local variable
  for variable in "${!GIT_@}"; do [[ $variable == GIT_CONFIG_GLOBAL || $variable == GIT_CONFIG_SYSTEM ]] || unset "$variable"; done
  timeout -k 1s "${project_git_local_seconds}s" git -C "$path" config --type=path --get core.excludesFile 2>/dev/null </dev/null || true
)

# Run the user's Git without prompts; output lands in $git_tmp/out and err.
project_git_user() {
  local seconds=$1
  shift
  (
    local variable ssh_base=${GIT_SSH_COMMAND:-}
    # The lock belongs to this helper alone; detached Git children must not keep it.
    [[ -z ${project_git_lock_fd:-} ]] || exec {project_git_lock_fd}>&-
    for variable in "${!GIT_@}"; do [[ $variable == GIT_SSH_COMMAND || $variable == GIT_SSH ]] || unset "$variable"; done
    unset SSH_ASKPASS
    if [[ -z $ssh_base ]]; then
      ssh_base=$(timeout -k 1s 15s git -C "$path" config --get core.sshCommand 2>/dev/null </dev/null || true)
    fi
    export LC_ALL=C GIT_TERMINAL_PROMPT=0 SSH_ASKPASS_REQUIRE=never GIT_SSH_COMMAND="${ssh_base:-ssh} -o BatchMode=yes"
    exec timeout -k 1s "${seconds}s" git -c credential.interactive=never -c core.askPass= "$@"
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
  first=$(grep -m1 -E '^ ! \[|^(fatal|error): ' "$git_tmp/err" | cut -c1-300 || true)
  project_git_fail GIT_ERROR "${first:-Git failed.}" 'Inspect this checkout in a terminal, then refresh.'
}

# Remote of the current branch's upstream, else origin, else the only remote.
project_git_remote() {
  local branch remote
  local -a remotes=()
  branch=$(project_git_read -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  if [[ -n $branch ]] && remote=$(project_git_read -C "$path" config --get "branch.$branch.remote" 2>/dev/null) && [[ -n $remote && $remote != . ]]; then
    printf '%s\n' "$remote"
    return
  fi
  mapfile -t remotes < <(project_git_read -C "$path" remote 2>/dev/null)
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

# Fetch the chosen remote and report it.
project_git_fetch() {
  local remote
  remote=$(project_git_remote)
  [[ -n $remote ]] || project_git_fail NO_REMOTE 'This repository has no remote to fetch from.' 'Add a remote in a terminal, then retry.'
  project_git_fetch_remote "$remote"
  project_git_ok "$(jq -cn --arg p "$project" --arg c "$checkout" --arg r "$remote" '{projectId:$p,checkoutId:$c,remote:$r}')"
}

# Fetch, then fast-forward only; never merge or stash.
project_git_pull() {
  local branch remote from to status=0
  branch=$(project_git_read -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  remote=''
  [[ -z $branch ]] || remote=$(project_git_read -C "$path" config --get "branch.$branch.remote" 2>/dev/null || true)
  if [[ -z $branch || -z $remote ]] || ! project_git_read -C "$path" rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1; then
    project_git_fail NO_UPSTREAM 'This branch does not track a remote branch.' 'Push the branch with an upstream in a terminal, then retry.'
  fi
  project_git_fetch_remote "$remote"
  from=$(project_git_read -C "$path" rev-parse HEAD)
  project_git_user "$project_git_local_seconds" -C "$path" merge --ff-only --quiet '@{upstream}' || status=$?
  if ((status != 0)); then
    if grep -qi 'would be overwritten' "$git_tmp/err"; then
      project_git_fail LOCAL_CHANGES 'Local changes would be overwritten by the pull.' 'Commit or stash those changes in a terminal, then retry.'
    elif grep -qiE 'not possible to fast-forward|diverg' "$git_tmp/err"; then
      project_git_fail NOT_FAST_FORWARD 'Branches have diverged; merge or rebase in a terminal.' 'Merge or rebase in a terminal, then refresh.'
    fi
    project_git_classify "$status"
  fi
  to=$(project_git_read -C "$path" rev-parse HEAD)
  project_git_ok "$(jq -cn --arg p "$project" --arg c "$checkout" --arg r "$remote" --arg f "$from" --arg t "$to" '{projectId:$p,checkoutId:$c,remote:$r,from:$f,to:$t,updated:($f != $t)}')"
}

# Hold one exclusive lock per Git common directory for the whole operation.
project_git_lock() {
  local dir key
  dir="$(aranea_state_root)/git-locks"
  mkdir -p -- "$dir" || project_git_fail GIT_ERROR 'Cannot create the Git lock directory.' 'Check state-directory permissions and retry.'
  key=$(printf '%s' "$common" | sha256sum | cut -c1-32)
  exec {project_git_lock_fd}>"$dir/$key.lock"
  local seconds=${ARANEA_GIT_LOCK_SECONDS:-75}
  [[ $seconds =~ ^[0-9]{1,3}$ ]] && ((10#$seconds >= 1)) || seconds=75
  flock -w "$((10#$seconds))" "$project_git_lock_fd" || project_git_fail GIT_BUSY 'Another Git operation on this repository is still running.' 'Wait for it to finish, then retry.'
}

# Call the registry store; prints the new state or returns 1.
project_git_store() {
  local response
  response=$("$git_state_lib/../aranea-project-store" mutate <<<"$1" 2>/dev/null) || true
  jq -e '.ok == true' <<<"$response" >/dev/null 2>&1 || return 1
  jq -c .state <<<"$response"
}

# Registered primary checkout path of the selected project.
project_git_primary_path() {
  jq -r --arg p "$project" '.projects[]|select(.id == $p)|.checkouts[]|select(.primary)|.path' "$git_tmp/registry"
}

# Print the default branch to start from: the remote's, else local main/master; nothing when none.
project_git_default_base() {
  local remote=$1 base='' candidate
  if [[ -n $remote ]]; then
    base=$(project_git_read -C "$path" symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)
    for candidate in main master; do
      [[ -z $base ]] || break
      ! project_git_read -C "$path" rev-parse --verify --quiet "refs/remotes/$remote/$candidate" >/dev/null || base="$remote/$candidate"
    done
  else
    for candidate in main master; do
      [[ -z $base ]] || break
      ! project_git_read -C "$path" rev-parse --verify --quiet "refs/heads/$candidate" >/dev/null || base=$candidate
    done
  fi
  printf '%s' "$base"
}

# Create a branch and worktree from the default branch, then register and select it.
project_git_task_create() {
  local primary_path folder remote base state new_id status=0
  if [[ -z $branch || $branch == -* || $branch == *'@{'* ]] || ! projects_registry_git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    project_git_fail INVALID_BRANCH 'That is not a valid branch name.' 'Use letters, numbers, - _ . and /, without spaces or ~ ^ : ? * [ \.'
  fi
  ! project_git_read -C "$path" show-ref --verify --quiet "refs/heads/$branch" ||
    project_git_fail BRANCH_EXISTS "A branch named $branch already exists." 'Choose another branch name.'
  primary_path=$(project_git_primary_path)
  folder="$(dirname -- "$primary_path")/$(basename -- "$primary_path")-worktrees/${branch//\//-}"
  [[ ! -e $folder && ! -L $folder ]] || project_git_fail PATH_EXISTS "A folder already exists at $folder." 'Choose another branch name or move that folder.'
  remote=$(project_git_remote)
  [[ -z $remote ]] || project_git_fetch_remote "$remote"
  base=$(project_git_default_base "$remote")
  [[ -n $base ]] || project_git_fail NO_DEFAULT_BRANCH 'Cannot find the default branch to start from.' 'Create a main or master branch, or run git remote set-head origin --auto.'
  project_git_alive
  mkdir -p -- "$(dirname -- "$folder")" || project_git_fail GIT_ERROR "Cannot create $(dirname -- "$folder")." 'Check folder permissions and retry.'
  project_git_user "$project_git_network_seconds" -C "$path" worktree add --quiet --no-track -b "$branch" -- "$folder" "$base" || status=$?
  if ((status != 0)); then
    # Git may have created the checkout before it was stopped; report it, delete nothing.
    if [[ -e $folder || -L $folder ]]; then
      project_git_fail REGISTER_FAILED "Git stopped while creating the task checkout, but a folder exists at $folder." "Run aranea projects register --path $folder to keep it, or remove it with git worktree remove $folder."
    elif project_git_read -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
      project_git_fail GIT_ERROR "Git stopped before the task checkout was ready; the branch $branch was created without a folder." "Delete the unused branch with git branch -d $branch, run git worktree prune, then retry."
    fi
    project_git_classify "$status"
  fi
  folder=$(realpath -e -- "$folder")
  if ! state=$(project_git_store "$(jq -cn --arg path "$folder" '{action:"register",args:{paths:[$path]}}')"); then
    project_git_fail REGISTER_FAILED "The task checkout was created at $folder but could not be registered." "Run aranea projects register --path $folder, or remove it with git worktree remove $folder."
  fi
  new_id=$(jq -r --arg p "$project" --arg path "$folder" '.projects[]|select(.id == $p)|.checkouts[]|select(.path == $path)|.id' <<<"$state")
  [[ -n $new_id ]] || project_git_fail REGISTER_FAILED "The task checkout at $folder joined another project." "Run aranea projects register --path $folder, or remove it with git worktree remove $folder."
  project_git_store "$(jq -cn --arg p "$project" --arg c "$new_id" '{action:"select-checkout",args:{projectId:$p,checkoutId:$c}}')" >/dev/null || true
  project_git_ok "$(jq -cn --arg p "$project" --arg c "$new_id" --arg path "$folder" --arg b "$branch" --arg base "$base" '{projectId:$p,checkoutId:$c,path:$path,branch:$b,base:$base}')"
}

# Sets `unpushed` to the commits of REF (in DIR) that no remote has; without
# remotes, those not on main/master. Returns 1 when Git fails.
project_git_unpushed() {
  local dir=$1 ref=$2 candidate
  unpushed=0
  if [[ -n $(project_git_read -C "$dir" remote 2>/dev/null) ]]; then
    unpushed=$(project_git_read -C "$dir" rev-list --count "$ref" --not --remotes 2>/dev/null) || return 1
    return 0
  fi
  for candidate in main master; do
    if project_git_read -C "$dir" rev-parse --verify --quiet "refs/heads/$candidate" >/dev/null; then
      unpushed=$(project_git_read -C "$dir" rev-list --count "$ref" --not "refs/heads/$candidate" 2>/dev/null) || return 1
      return 0
    fi
  done
  return 0
}

# Sets `busy` to true when a protected action run exists for this checkout.
# Returns 1 when the action store cannot be read, so callers fail closed.
project_git_busy() {
  local runs
  runs=$("$git_state_lib/../aranea-project-action-store" snapshot 2>/dev/null) || runs=''
  jq -e '.ok == true' <<<"$runs" >/dev/null 2>&1 || return 1
  busy=$(jq --arg p "$project" --arg c "$checkout" '[.state.runs[]? | select(.projectId == $p and .checkoutId == $c and (.submissionUnconfirmed or .processState == "pending" or .processState == "running" or .processState == "unconfirmed"))] | length > 0' <<<"$runs") || return 1
}

# Fail closed with ACTIONS_UNAVAILABLE when the action store cannot be read.
project_git_busy_or_fail() {
  project_git_busy || project_git_fail ACTIONS_UNAVAILABLE 'Could not check for running actions in this checkout.' 'Refresh Projects and retry.'
}

# Remove a clean task checkout folder, keeping its branch; --check only reports facts.
project_git_task_remove() {
  local primary_path current_branch status_file record excludes dirty=false untracked=false ignored=0 busy='' unpushed=0 detached=0 facts status=0
  [[ $primary != true ]] || project_git_fail PRIMARY_CHECKOUT 'The main checkout cannot be removed.' 'Choose a task checkout.'
  primary_path=$(project_git_primary_path)
  current_branch=$(project_git_read -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  status_file="$git_tmp/status"
  excludes=$(project_git_user_excludes)
  project_git_read ${excludes:+-c "core.excludesFile=$excludes"} -C "$path" status --porcelain=v1 -z --ignored=matching --untracked-files=normal >"$status_file" 2>/dev/null ||
    project_git_fail GIT_ERROR 'Git could not read the task checkout.' 'Inspect this checkout in a terminal, then refresh.'
  while IFS= read -r -d '' record; do
    [[ -n $record ]] || continue
    if [[ $record == '?? '* ]]; then
      untracked=true
    elif [[ $record == '!! '* ]]; then
      ignored=$((ignored + 1))
    else
      dirty=true
    fi
  done <"$status_file"
  project_git_busy_or_fail
  project_git_unpushed "$path" HEAD || project_git_fail GIT_ERROR 'Git could not count unpushed commits.' 'Inspect this checkout in a terminal, then refresh.'
  if [[ -z $current_branch ]]; then
    detached=$(project_git_read -C "$path" rev-list --count HEAD --not --branches --remotes 2>/dev/null) ||
      project_git_fail GIT_ERROR 'Git could not count unpushed commits.' 'Inspect this checkout in a terminal, then refresh.'
  fi
  facts=$(jq -cn --arg p "$project" --arg c "$checkout" --arg path "$path" --arg b "$current_branch" --argjson d "$dirty" --argjson u "$untracked" --argjson i "$ignored" --argjson busy "$busy" --argjson n "$unpushed" --argjson dt "$detached" \
    '{projectId:$p,checkoutId:$c,path:$path,branch:(if $b == "" then null else $b end),dirty:$d,untracked:$u,ignored:$i,busy:$busy,unpushed:$n,detached:$dt,missing:false}')
  [[ $check != true ]] || project_git_ok "$facts"
  [[ $dirty == false && $untracked == false ]] || project_git_fail CHECKOUT_DIRTY 'This checkout has uncommitted or untracked changes.' 'Commit, stash or delete them, then retry.'
  [[ $busy == false ]] || project_git_fail CHECKOUT_BUSY 'An action is still running in this checkout.' 'Stop the running action, then retry.'
  if ((detached > 0)); then
    project_git_fail UNPUSHED_COMMITS "$detached commit$( ((detached == 1)) || printf s) on a detached HEAD would be lost." 'Create a branch for them first.'
  fi
  if ((unpushed > 0)) && [[ $confirm != true ]]; then
    project_git_fail UNPUSHED_COMMITS "$unpushed commit$( ((unpushed == 1)) || printf s) on ${current_branch:-this checkout} $( ((unpushed == 1)) && printf "isn't" || printf "aren't") on any remote." 'Push first, or confirm removal; the branch is kept.'
  fi
  project_git_alive
  project_git_user "$project_git_local_seconds" -C "$primary_path" worktree remove -- "$path" || status=$?
  ((status == 0)) || project_git_classify "$status"
  project_git_store "$(jq -cn --arg p "$project" --arg c "$checkout" '{action:"checkout-remove",args:{projectId:$p,checkoutId:$c}}')" >/dev/null ||
    project_git_fail UNREGISTER_FAILED 'The folder was removed but Projects could not forget the checkout.' 'Refresh Projects; the checkout now shows as missing and can be removed or located.'
  project_git_ok "$(jq -c '{projectId,checkoutId,path,branch,removed:true}' <<<"$facts")"
}

# Forget Git's record of exactly one vanished worktree. Plain removal first;
# otherwise prune only when that one worktree is the sole stale entry.
project_git_forget_worktree() {
  local primary_path=$1 registered=$2 status=0 entry own='' listed name
  local -a names=()
  project_git_alive
  project_git_user "$project_git_local_seconds" -C "$primary_path" worktree remove -- "$registered" || status=$?
  ((status == 0)) && return 0
  if ((status == 124 || status == 137)); then project_git_classify "$status"; fi
  for entry in "$common"/worktrees/*/gitdir; do
    [[ -f $entry ]] || continue
    [[ $(<"$entry") == "$registered/.git" ]] && own=$(basename -- "$(dirname -- "$entry")")
  done
  [[ -n $own ]] || return 0
  listed=$(LC_ALL=C project_git_read -C "$primary_path" worktree prune --dry-run --verbose 2>&1) ||
    project_git_fail GIT_ERROR 'Git could not list stale worktrees.' 'Run git worktree prune in a terminal, then retry.'
  while IFS= read -r name; do
    [[ $name == 'Removing worktrees/'* ]] || continue
    name=${name#Removing worktrees/}
    names+=("${name%%:*}")
  done <<<"$listed"
  if ((${#names[@]} == 1)) && [[ ${names[0]} == "$own" ]]; then
    project_git_read -C "$primary_path" worktree prune >/dev/null 2>&1 ||
      project_git_fail GIT_ERROR 'Git could not prune the missing worktree.' 'Run git worktree prune in a terminal, then retry.'
  elif ((${#names[@]} > 1)) || { ((${#names[@]} == 1)) && [[ ${names[0]} != "$own" ]]; }; then
    project_git_fail GIT_ERROR 'Other stale worktrees exist; run git worktree prune in a terminal.' 'Run git worktree prune in a terminal, then retry.'
  else
    project_git_fail GIT_ERROR 'Git still tracks this worktree and will not prune it; it may be locked.' 'Run git worktree list in a terminal, then retry.'
  fi
}

# A task checkout whose folder is gone cannot be proved; forget Git's record of
# it from the primary checkout and unregister it. Returns 1 when not applicable.
# Proving the primary overwrites path/common/primary, never project/checkout.
project_git_remove_missing() {
  local registered primary_flag primary_id primary_path registered_branch busy='' unpushed=0 facts
  [[ -s $git_tmp/registry ]] || return 1
  registered=$(jq -r --arg p "$project" --arg c "$checkout" '.projects[]|select(.id == $p)|.checkouts[]|select(.id == $c)|.path' "$git_tmp/registry") || return 1
  primary_flag=$(jq -r --arg p "$project" --arg c "$checkout" '.projects[]|select(.id == $p)|.checkouts[]|select(.id == $c)|.primary' "$git_tmp/registry") || return 1
  [[ -n $registered && $primary_flag == false && ! -e $registered && ! -L $registered ]] || return 1
  primary_id=$(jq -r --arg p "$project" '.projects[]|select(.id == $p)|.checkouts[]|select(.primary)|.id' "$git_tmp/registry")
  primary_path=$(project_git_primary_path)
  [[ -n $primary_id && -n $primary_path ]] || return 1
  registered_branch=$(jq -r --arg p "$project" --arg c "$checkout" '.projects[]|select(.id == $p)|.checkouts[]|select(.id == $c)|.branch // empty' "$git_tmp/registry")
  project_git_state_prove "$project" "$primary_id" >"$git_tmp/primary-proof" || return 1
  [[ $check == true ]] || project_git_lock
  project_git_busy_or_fail
  if [[ -n $registered_branch ]] && project_git_read -C "$primary_path" show-ref --verify --quiet "refs/heads/$registered_branch"; then
    project_git_unpushed "$primary_path" "refs/heads/$registered_branch" || project_git_fail GIT_ERROR 'Git could not count unpushed commits.' 'Inspect the main checkout in a terminal, then refresh.'
  fi
  facts=$(jq -cn --arg p "$project" --arg c "$checkout" --arg path "$registered" --arg b "$registered_branch" --argjson busy "$busy" --argjson n "$unpushed" \
    '{projectId:$p,checkoutId:$c,path:$path,branch:(if $b == "" then null else $b end),dirty:false,untracked:false,ignored:0,busy:$busy,unpushed:$n,detached:0,missing:true}')
  [[ $check != true ]] || project_git_ok "$facts"
  [[ $busy == false ]] || project_git_fail CHECKOUT_BUSY 'An action is still running in this checkout.' 'Stop the running action, then retry.'
  project_git_forget_worktree "$primary_path" "$registered"
  project_git_store "$(jq -cn --arg p "$project" --arg c "$checkout" '{action:"checkout-remove",args:{projectId:$p,checkoutId:$c}}')" >/dev/null ||
    project_git_fail UNREGISTER_FAILED 'Projects could not forget the missing checkout.' 'Refresh Projects and retry.'
  project_git_ok "$(jq -c '{projectId,checkoutId,path,branch,removed:true}' <<<"$facts")"
}

# Report a task checkout's commits and files against where its branch started; reads only.
project_git_review() {
  local remote base base_sha merge_base='' head current excludes record ahead behind dirty=false untracked=false
  # Reads here never fetch a missing object, so repository transport settings cannot run.
  local -x ARANEA_GIT_NO_LAZY_FETCH=1
  [[ $primary != true ]] || project_git_fail PRIMARY_CHECKOUT 'The main checkout has nothing to review.' 'Choose a task checkout.'
  remote=$(project_git_remote)
  base=$(project_git_default_base "$remote")
  [[ -n $base ]] || project_git_fail NO_DEFAULT_BRANCH 'Cannot find the default branch to review against.' 'Create a main or master branch, or run git remote set-head origin --auto.'
  # Without the repository lock a fetch can land mid-read, so every value derives from these two SHAs.
  head=$(project_git_read -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
  base_sha=$(project_git_read -C "$path" rev-parse --verify "$base^{commit}" 2>/dev/null || true)
  [[ $base_sha =~ ^[0-9a-f]{40}$ ]] && merge_base=$(project_git_read -C "$path" merge-base "$base_sha" "$head" 2>/dev/null || true)
  [[ $merge_base =~ ^[0-9a-f]{40}$ && $head =~ ^[0-9a-f]{40}$ ]] || project_git_fail GIT_ERROR 'Git could not find where this branch started.' 'Inspect this checkout in a terminal, then refresh.'
  current=$(project_git_read -C "$path" symbolic-ref --quiet HEAD 2>/dev/null || true)
  current=${current#refs/heads/}
  if ! { ahead=$(project_git_read -C "$path" rev-list --count "$merge_base..$head" 2>/dev/null) &&
    behind=$(project_git_read -C "$path" rev-list --count "$head..$base_sha" 2>/dev/null) &&
    project_git_read -C "$path" log --format=%H%x00%s -z -n 51 "$merge_base..$head" >"$git_tmp/review-log" 2>/dev/null &&
    project_git_read -C "$path" diff --numstat -z "$merge_base...$head" >"$git_tmp/review-files" 2>/dev/null; }; then
    project_git_fail GIT_ERROR 'Git could not read this branch.' 'Inspect this checkout in a terminal, then refresh.'
  fi
  excludes=$(project_git_user_excludes)
  project_git_read ${excludes:+-c "core.excludesFile=$excludes"} -C "$path" status --porcelain=v1 -z --untracked-files=normal >"$git_tmp/status" 2>/dev/null ||
    project_git_fail GIT_ERROR 'Git could not read this branch.' 'Inspect this checkout in a terminal, then refresh.'
  while IFS= read -r -d '' record; do
    [[ -n $record ]] || continue
    if [[ $record == '?? '* ]]; then untracked=true; else dirty=true; fi
  done <"$git_tmp/status"
  project_git_ok "$(jq -cn --arg p "$project" --arg c "$checkout" --arg b "$current" --arg base "$base" --arg mb "$merge_base" --arg h "$head" --argjson ahead "$ahead" --argjson behind "$behind" --argjson d "$dirty" --argjson u "$untracked" --rawfile log "$git_tmp/review-log" --rawfile files "$git_tmp/review-files" '
    def pairs: if length < 2 then empty else {sha: .[0], subject: .[1]}, (.[2:] | pairs) end;
    def numstat: if length == 0 then empty else
      (.[0] | capture("^(?<a>[^\t]*)\t(?<r>[^\t]*)\t(?<p>.*)$"; "s")) as $m
      | (if $m.p == "" then .[2] else $m.p end) as $path
      | {path: $path, added: ($m.a | tonumber? // null), removed: ($m.r | tonumber? // null)},
        (.[(if $m.p == "" then 3 else 1 end):] | numstat) end;
    ($log | rtrimstr("\u0000") | if . == "" then [] else split("\u0000") end | [pairs]) as $commits
    | ($files | rtrimstr("\u0000") | if . == "" then [] else split("\u0000") end | [numstat]) as $changed
    | {projectId: $p, checkoutId: $c, branch: (if $b == "" then null else $b end), base: $base, mergeBase: $mb, head: $h,
       ahead: $ahead, behind: $behind, commits: $commits[:50], files: $changed[:200],
       uncommitted: {dirty: $d, untracked: $u}, truncated: (($commits | length) > 50 or ($changed | length) > 200)}')"
}

# Push the current branch to its remote with an upstream; never forces, never pushes other branches.
project_git_push() {
  local current remote status=0
  current=$(project_git_read -C "$path" symbolic-ref --quiet HEAD 2>/dev/null || true)
  current=${current#refs/heads/}
  [[ -n $current ]] || project_git_fail NO_BRANCH 'This checkout is not on a branch.' 'Switch to a branch in a terminal, then retry.'
  remote=$(project_git_remote)
  [[ -n $remote ]] || project_git_fail NO_REMOTE 'This repository has no remote to push to.' 'Add a remote in a terminal, then retry.'
  project_git_alive
  project_git_user "$project_git_network_seconds" -C "$path" push --set-upstream --no-follow-tags --recurse-submodules=no -- "$remote" "refs/heads/$current:refs/heads/$current" || status=$?
  if ((status != 0)); then
    if ((status != 124 && status != 137)) && grep -qE '^ ! \[rejected\].*\((fetch first|non-fast-forward)\)' "$git_tmp/err"; then
      project_git_fail PUSH_REJECTED 'The remote has newer commits; fetch and update first.' 'Pull or merge in a terminal, then push again.'
    fi
    project_git_classify "$status"
  fi
  project_git_ok "$(jq -cn --arg p "$project" --arg c "$checkout" --arg r "$remote" --arg b "$current" '{projectId:$p,checkoutId:$c,remote:$r,branch:$b,upstream:($r + "/" + $b),pushed:true}')"
}

# Parse arguments, prove the checkout, lock the repository and dispatch.
project_git_main() {
  local operation=${1:-} project='' checkout='' branch='' check=false confirm=false json=false dependency
  local path common primary git_state_failure_code=CHECKOUT_INVALID
  project_git_network_seconds=${ARANEA_GIT_NETWORK_SECONDS:-60}
  project_git_local_seconds=${ARANEA_GIT_LOCAL_SECONDS:-15}
  for dependency in jq git timeout flock mktemp sha256sum realpath; do
    command -v "$dependency" >/dev/null || project_git_fail DEPENDENCY_MISSING "Install $dependency to run Git operations." 'Install the missing dependency and retry.'
  done
  case "$operation" in fetch | pull | task-create | task-remove | review | push) shift ;; *) project_git_fail INVALID_REQUEST 'Unsupported Git operation.' 'Use fetch, pull, task-create, task-remove, review or push.' ;; esac
  while (($#)); do
    case "$1" in
      --project | --checkout | --branch)
        [[ $# -ge 2 && -n $2 ]] || project_git_fail INVALID_REQUEST "Provide a value for $1." 'Retry with every required value.'
        case "$1" in --project) project=$2 ;; --checkout) checkout=$2 ;; --branch) branch=$2 ;; esac
        shift 2
        ;;
      --check)
        check=true
        shift
        ;;
      --confirm-unpushed)
        confirm=true
        shift
        ;;
      --json)
        json=true
        shift
        ;;
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
    if [[ $operation == task-remove ]] && jq -e '.error.code == "CHECKOUT_INVALID"' "$git_tmp/proof" >/dev/null 2>&1; then
      project_git_remove_missing || true
    fi
    cat "$git_tmp/proof"
    exit 1
  fi
  # Review only reads, with optional locks off, so it never queues behind a fetch or push.
  [[ $operation == review ]] || project_git_lock
  case "$operation" in
    fetch) project_git_fetch ;;
    pull) project_git_pull ;;
    task-create) project_git_task_create ;;
    task-remove) project_git_task_remove ;;
    review) project_git_review ;;
    push) project_git_push ;;
  esac
}
