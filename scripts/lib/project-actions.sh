#!/usr/bin/env bash
# Action store coordination and inert checkout validation; no process execution.

# Reject symlinks and non-directory ancestors, including an overridden state root.
project_actions_safe_path() {
  local path=$1 parent
  [[ "$path" == /* ]] || path="$PWD/$path"
  while [[ "$path" != / ]]; do
    [[ ! -L "$path" ]] || return 1
    parent=${path%/*}
    [[ -n "$parent" ]] || parent=/
    [[ ! -e "$parent" || -d "$parent" ]] || return 1
    path=$parent
  done
}

# Capture ingress lifetime before reading stdin or waiting for the store lock.
project_actions_generation() {
  local lock value=''
  lock="$(aranea_state_root)/project-actions.json.lock"
  if ! project_actions_safe_path "$lock" || [[ -e "$lock" && ! -f "$lock" ]]; then
    printf 'unsafe\n'
    return
  fi
  [[ ! -e "$lock" ]] || value=$(head -c 128 -- "$lock") || return 1
  printf '%s\n' "${value:-initial}"
}

# Caller owns action_generation and consumes action_lock_fd/action_lock_error.
# Lifecycle calls bypass generation checks but retain the exact same lock inode.
# shellcheck disable=SC2034,SC2154
project_actions_lock() {
  local wait=${1:-2} lifecycle=${2:-false} lock current
  lock="$(aranea_state_root)/project-actions.json.lock"
  action_lock_error=UNSAFE_STATE_PATH
  project_actions_safe_path "$lock" && [[ ! -e "$lock" || -f "$lock" ]] || return 1
  action_lock_error=ACTION_WRITE_FAILED
  mkdir -p -- "$(dirname "$lock")" || return 1
  exec {action_lock_fd}<>"$lock" || return 1
  chmod 600 "$lock" || return 1
  action_lock_error=ACTION_LOCK_FAILED
  flock -w "$wait" -x "$action_lock_fd" || return 1
  current=$(project_actions_generation) || return 1
  action_lock_error=ACTION_REMOVED
  [[ "$lifecycle" == true || ("$current" != removed:* && "$current" == "$action_generation" && ("$current" != draining:* || ${ARANEA_ACTION_DRAIN:-} == 1)) ]]
}

# Hash exactly the immutable definition content, excluding wall-clock metadata.
# Reads one definition JSON on stdin and prints its SHA256 digest.
project_actions_definition_hash() {
  jq -Sc 'del(.createdAt,.updatedAt)' | sha256sum | cut -d' ' -f1
}

# Verify the exact registered checkout and derived cwd, never infer or relocate.
# Request and registry are private JSON files to keep variable payloads off argv.
project_actions_checkout() {
  local request=$1 projects=$2 definition=$3 project checkout path common metadata cwd relative
  project=$(jq -r '.args.projectId' "$request")
  checkout=$(jq -r '.args.checkoutId' "$request")
  path=$(jq -r --arg p "$project" --arg c "$checkout" '.projects[]|select(.id==$p)|.checkouts[]|select(.id==$c)|.path' "$projects")
  [[ -n "$path" ]] || return 1
  common=$(jq -r --arg p "$project" '.projects[]|select(.id==$p)|.commonDir' "$projects")
  metadata=$(project_git_metadata "$path") || return 1
  [[ $(jq -r .path <<<"$metadata") == "$path" && $(jq -r .commonDir <<<"$metadata") == "$common" ]] || return 1
  relative=$(jq -r .cwdRelative "$definition")
  cwd=$(projects_registry_path "$path/$relative") || return 1
  [[ "$cwd" == "$path" || "$cwd" == "$path/"* ]] || return 1
  [[ "$cwd" == "$(jq -r .args.cwd "$request")" ]]
}

# Dispatch always precedes the transaction lock. Lifecycle store subprocesses reuse
# a validated inherited open-file description instead of recursively locking it.
# shellcheck disable=SC2034
project_actions_dispatch_lock() {
  local lock inherited=${ARANEA_ACTION_DISPATCH_FD:-}
  lock="$(aranea_state_root)/project-actions.json.dispatch.lock"
  action_lock_error=UNSAFE_STATE_PATH
  project_actions_safe_path "$lock" && [[ ! -e $lock || -f $lock ]] || return 1
  action_lock_error=ACTION_WRITE_FAILED
  mkdir -p -- "$(dirname "$lock")" || return 1
  if [[ -n $inherited ]]; then
    action_lock_error=UNSAFE_STATE_PATH
    [[ $inherited =~ ^[0-9]+$ && -f /proc/$$/fd/$inherited && -f $lock ]] || return 1
    [[ $(stat -Lc '%d:%i' "/proc/$$/fd/$inherited") == "$(stat -Lc '%d:%i' "$lock")" ]] || return 1
    dispatch_fd=$inherited
  else
    exec {dispatch_fd}<>"$lock" || return 1
  fi
  chmod 600 "$lock" || return 1
  action_lock_error=ACTION_LOCK_FAILED
  flock -x -w 2 "$dispatch_fd"
}
