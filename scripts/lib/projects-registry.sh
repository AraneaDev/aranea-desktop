#!/usr/bin/env bash
# Filesystem and read-only Git identity boundary for projects-registry.jq.

# Generate one stable opaque UUID with the requested record-kind prefix.
projects_registry_id() {
  printf '%s-%s\n' "$1" "$(cat /proc/sys/kernel/random/uuid)"
}

# Reject ASCII controls before any line-based or substitution boundary.
projects_registry_path_safe() {
  jq -en --arg path "$1" '$path | test("[\\x00-\\x1f\\x7f]") | not' >/dev/null
}

# Read canonical paths with NUL framing, then reject unsafe resolved targets.
# The optional missing mode supports forgetting an already vanished checkout.
projects_registry_path() {
  local canonical mode=${2:-existing}
  local -a flags=(-ze)
  projects_registry_path_safe "$1" || return 2
  if [[ "$mode" == missing ]]; then flags=(-zm); else [[ -d "$1" ]] || return 1; fi
  IFS= read -r -d '' canonical < <(realpath "${flags[@]}" -- "$1") || return 1
  projects_registry_path_safe "$canonical" || return 2
  printf '%s\n' "$canonical"
}

# Read Git metadata without inherited repository/configuration overrides.
projects_registry_git() (
  local git_context
  for git_context in "${!GIT_@}"; do unset "$git_context"; done
  export GIT_OPTIONAL_LOCKS=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"
)

# Capture one newline-terminated Git value without discarding path bytes.
projects_registry_git_value() {
  local destination=$1 git_value
  shift
  git_value=$(projects_registry_git "$@" && printf '\001') || return 1
  git_value=${git_value%$'\001'}
  git_value=${git_value%$'\n'}
  printf -v "$destination" '%s' "$git_value"
}

# Only explicit checkout roots are accepted; no repository scripts run.
# Discovery extends this boundary with full related-worktree metadata.
projects_registry_checkout() {
  local canonical top common branch primary=false
  canonical=$(projects_registry_path "$1") || return $?
  projects_registry_git_value top -C "$canonical" rev-parse --show-toplevel 2>/dev/null || return 1
  top=$(projects_registry_path "$top") || return $?
  [[ "$canonical" == "$top" ]] || return 1
  projects_registry_git_value common -C "$canonical" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || return 1
  common=$(projects_registry_path "$common") || return $?
  [[ "$common" != "$canonical/.git" ]] || primary=true
  projects_registry_git_value branch -C "$canonical" symbolic-ref --quiet --short HEAD 2>/dev/null || branch=''
  jq -cn --arg path "$canonical" --arg common "$common" --arg branch "$branch" --argjson primary "$primary" \
    --arg name "${canonical##*/}" --arg id "$(projects_registry_id c)" --arg projectId "$(projects_registry_id p)" \
    '{path:$path,commonDir:$common,branch:(if $branch == "" then null else $branch end),primary:$primary,name:$name,id:$id,projectId:$projectId}'
}

# Reject regrouping while any surviving sibling has a different Git identity.
# Missing old paths are allowed during an explicitly confirmed whole-repo move.
projects_registry_relocation_valid() {
  local request=$1 state=$2 replacement=$3 other_path other_metadata common
  common=$(jq -r '.commonDir' <<<"$replacement")
  while IFS= read -r other_path; do
    other_path=$(jq -r '.' <<<"$other_path")
    [[ -e "$other_path" || -L "$other_path" ]] || continue
    other_metadata=$(projects_registry_checkout "$other_path") || return $?
    [[ "$(jq -r '.commonDir' <<<"$other_metadata")" == "$common" ]] || return 3
  done < <(jq -c --argjson request "$request" '.projects[] | select(.id == $request.args.projectId) | .checkouts[] | select(.id != $request.args.checkoutId) | .path' <<<"$state")
}

# Enrich a validated raw request with canonical metadata under the store lock.
# Return 1 for invalid checkout, 2 for unsafe path, 3 for incompatible grouping.
projects_registry_prepare_request() {
  local request=$1 state=${2:-null} action path metadata checkouts='[]'
  action=$(jq -r '.action' <<<"$request")
  case "$action" in
    root-add)
      path=$(projects_registry_path "$(jq -r '.args.path' <<<"$request")") || return $?
      jq -c --arg path "$path" --arg id "$(projects_registry_id r)" '.args.path=$path | .args.id=$id' <<<"$request"
      ;;
    ignore | relocate)
      metadata=$(projects_registry_checkout "$(jq -r '.args.path' <<<"$request")") || return $?
      if [[ "$action" == relocate ]]; then
        projects_registry_relocation_valid "$request" "$state" "$metadata" || return $?
      fi
      jq -c --argjson metadata "$metadata" '.args += ($metadata|{path,commonDir,branch,primary})' <<<"$request"
      ;;
    unignore)
      # Forgetting an ignored checkout remains possible after it disappears.
      path=$(projects_registry_path "$(jq -r '.args.path' <<<"$request")" missing) || return $?
      jq -c --arg path "$path" '.args.path=$path' <<<"$request"
      ;;
    register)
      while IFS= read -r path; do
        path=$(jq -r '.' <<<"$path")
        metadata=$(projects_registry_checkout "$path") || return $?
        checkouts=$(jq -cn --argjson current "$checkouts" --argjson metadata "$metadata" '$current + [$metadata] | unique_by(.path) | sort_by(.primary | not)') || return 1
      done < <(jq -c '.args.paths[]' <<<"$request")
      jq -c --argjson checkouts "$checkouts" '.args.checkouts=$checkouts' <<<"$request"
      ;;
    *) printf '%s\n' "$request" ;;
  esac
}
