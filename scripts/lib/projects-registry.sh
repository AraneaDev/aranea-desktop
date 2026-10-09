#!/usr/bin/env bash
# Filesystem and read-only Git identity boundary for projects-registry.jq.

projects_registry_id() {
  printf '%s-%s\n' "$1" "$(cat /proc/sys/kernel/random/uuid)"
}

projects_registry_path() {
  [[ -d "$1" ]] || return 1
  realpath -e -- "$1"
}

# Only explicit checkout roots are accepted; no repository scripts run.
# Discovery extends this boundary with full related-worktree metadata.
projects_registry_checkout() {
  local canonical top common branch primary=false
  canonical=$(projects_registry_path "$1") || return 1
  top=$(GIT_OPTIONAL_LOCKS=0 git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$canonical" rev-parse --show-toplevel 2>/dev/null) || return 1
  top=$(projects_registry_path "$top") || return 1
  [[ "$canonical" == "$top" ]] || return 1
  common=$(GIT_OPTIONAL_LOCKS=0 git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$canonical" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  common=$(projects_registry_path "$common") || return 1
  [[ "$common" != "$canonical/.git" ]] || primary=true
  branch=$(GIT_OPTIONAL_LOCKS=0 git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$canonical" symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=''
  jq -cn --arg path "$canonical" --arg common "$common" --arg branch "$branch" --argjson primary "$primary" \
    --arg name "${canonical##*/}" --arg id "$(projects_registry_id c)" --arg projectId "$(projects_registry_id p)" \
    '{path:$path,commonDir:$common,branch:(if $branch == "" then null else $branch end),primary:$primary,name:$name,id:$id,projectId:$projectId}'
}

projects_registry_prepare_request() {
  local request=$1 action path metadata checkouts='[]'
  action=$(jq -r '.action' <<<"$request")
  case "$action" in
    root-add)
      path=$(projects_registry_path "$(jq -r '.args.path' <<<"$request")") || return 1
      jq -c --arg path "$path" --arg id "$(projects_registry_id r)" '.args.path=$path | .args.id=$id' <<<"$request"
      ;;
    ignore | relocate)
      metadata=$(projects_registry_checkout "$(jq -r '.args.path' <<<"$request")") || return 1
      jq -c --argjson metadata "$metadata" '.args += ($metadata|{path,commonDir,branch,primary})' <<<"$request"
      ;;
    unignore)
      # Forgetting an ignored checkout remains possible after it disappears.
      path=$(realpath -m -- "$(jq -r '.args.path' <<<"$request")") || return 1
      jq -c --arg path "$path" '.args.path=$path' <<<"$request"
      ;;
    register)
      while IFS= read -r path; do
        path=$(jq -r '.' <<<"$path")
        metadata=$(projects_registry_checkout "$path") || return 1
        checkouts=$(jq -cn --argjson current "$checkouts" --argjson metadata "$metadata" '$current + [$metadata] | unique_by(.path) | sort_by(.primary | not)') || return 1
      done < <(jq -c '.args.paths[]' <<<"$request")
      jq -c --argjson checkouts "$checkouts" '.args.checkouts=$checkouts' <<<"$request"
      ;;
    *) printf '%s\n' "$request" ;;
  esac
}
