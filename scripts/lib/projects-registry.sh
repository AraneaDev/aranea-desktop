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

# Read a complete group from NUL-framed Git worktree records. A selected primary
# with --separate-git-dir replaces Git's misleading metadata-directory record.
# Return 1 for invalid checkout, 2 for unsafe path, 4 for an unsupported bare repo.
project_git_metadata() (
  local canonical top common git_dir bare token record_path='' branch='' primary=false related_status error_code
  local metadata_file checkout_path checkout_git_dir checkout_top checkout_common checkout_primary checkouts='[]' metadata_errors='[]'
  canonical=$(projects_registry_path "$1") || return $?
  projects_registry_git_value bare -C "$canonical" rev-parse --is-bare-repository 2>/dev/null || return 1
  [[ "$bare" != true ]] || return 4
  projects_registry_git_value top -C "$canonical" rev-parse --show-toplevel 2>/dev/null || return 1
  top=$(projects_registry_path "$top") || return $?
  [[ "$canonical" == "$top" ]] || return 1
  projects_registry_git_value common -C "$canonical" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || return 1
  common=$(projects_registry_path "$common") || return $?
  projects_registry_git_value git_dir -C "$canonical" rev-parse --absolute-git-dir 2>/dev/null || return 1
  git_dir=$(projects_registry_path "$git_dir") || return $?
  [[ "$git_dir" != "$common" ]] || primary=true
  metadata_file=$(mktemp) || return 1
  trap 'rm -f -- "$metadata_file"' EXIT
  projects_registry_git -C "$canonical" worktree list --porcelain -z >"$metadata_file" 2>/dev/null || return 1
  while IFS= read -r -d '' token; do
    case "$token" in
      'worktree '*)
        record_path=${token#worktree }
        branch=''
        ;;
      'branch '*) branch=${token#branch refs/heads/} ;;
      '')
        [[ -n "$record_path" ]] || continue
        # Git lacks a backlink to the root for separate git dirs. The selected
        # primary is reliable, whereas its metadata directory is not a checkout.
        if [[ "$record_path" == "$common" ]]; then
          if [[ "$primary" != true ]]; then
            metadata_errors=$(jq -cn --arg path "$record_path" '{code:"PRIMARY_UNAVAILABLE",path:$path,message:"Git does not record the primary checkout folder for this separate Git directory; choose the primary folder to discover it."} | [.]')
            record_path=''
            continue
          fi
          record_path=$canonical
        fi
        # Only the selected identity is fatal. Invalid unselected worktree
        # records are availability errors and cannot erase a validated selection.
        if checkout_path=$(projects_registry_path "$record_path") &&
          projects_registry_git_value checkout_git_dir -C "$checkout_path" rev-parse --absolute-git-dir 2>/dev/null &&
          projects_registry_git_value checkout_top -C "$checkout_path" rev-parse --show-toplevel 2>/dev/null &&
          projects_registry_git_value checkout_common -C "$checkout_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null &&
          checkout_git_dir=$(projects_registry_path "$checkout_git_dir") &&
          checkout_top=$(projects_registry_path "$checkout_top") &&
          checkout_common=$(projects_registry_path "$checkout_common"); then
          if [[ "$checkout_top" == "$checkout_path" && "$checkout_common" == "$common" ]]; then
            related_status=0
          else
            related_status=1
          fi
        else
          related_status=$?
        fi
        if ((related_status != 0)); then
          [[ "$record_path" != "$canonical" ]] || return "$related_status"
          error_code=CHECKOUT_UNAVAILABLE
          ((related_status != 2)) || error_code=INVALID_PATH
          metadata_errors=$(jq -cn --argjson errors "$metadata_errors" --arg code "$error_code" --arg path "$record_path" '$errors + [{code:$code,path:$path,message:"A related checkout could not be validated; choose a valid folder or repair its Git worktree record."}]')
          record_path=''
          continue
        fi
        checkout_primary=false
        [[ "$checkout_git_dir" != "$common" ]] || checkout_primary=true
        checkouts=$(jq -cn --argjson current "$checkouts" --arg path "$checkout_path" --arg branch "$branch" --argjson primary "$checkout_primary" \
          '$current + [{path:$path,branch:(if $branch == "" then null else $branch end),primary:$primary}]') || return 1
        record_path=''
        ;;
    esac
  done <"$metadata_file"
  projects_registry_git_value branch -C "$canonical" symbolic-ref --quiet --short HEAD 2>/dev/null || branch=''
  jq -cn --arg path "$canonical" --arg common "$common" --arg name "${canonical##*/}" --arg branch "$branch" --argjson primary "$primary" --argjson checkouts "$checkouts" --argjson metadataErrors "$metadata_errors" \
    '{metadataErrors:$metadataErrors,path:$path,name:$name,commonDir:$common,checkouts:($checkouts + [{path:$path,branch:(if $branch == "" then null else $branch end),primary:$primary}] | unique_by(.path) | sort_by(.primary|not))}'
)

# Revalidate a single explicit checkout, never register unselected relatives.
projects_registry_checkout() {
  local metadata
  metadata=$(project_git_metadata "$1") || return $?
  jq -cn --argjson metadata "$metadata" --arg id "$(projects_registry_id c)" --arg projectId "$(projects_registry_id p)" \
    '$metadata as $group | ($group.checkouts[] | select(.path == $group.path)) + ($group|{name,commonDir}) + {id:$id,projectId:$projectId}'
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

# Default profile drafts from the read-only tool probe; empty on any probe failure.
projects_registry_presets() {
  local probe
  # shellcheck disable=SC2154 # script_dir is the scripts/ directory set by every sourcing caller
  probe=$(timeout -k 0.2s 5s "$script_dir/aranea-project-tools" --json </dev/null 2>/dev/null) || probe=''
  jq -e 'type=="object"' <<<"$probe" >/dev/null 2>&1 || probe='{}'
  jq -cn --argjson tools "$probe" -f "$script_dir/lib/project-presets.jq" 2>/dev/null || printf '[]\n'
}

# Give each draft its own fresh opaque profile ID.
projects_registry_preset_ids() {
  local drafts=$1 out='[]' draft
  while IFS= read -r draft; do
    out=$(jq -c --argjson d "$draft" --arg id "$(projects_registry_id f)" '. + [$d + {id:$id}]' <<<"$out")
  done < <(jq -c '.[]' <<<"$drafts")
  printf '%s\n' "$out"
}

# Enrich a validated raw request with canonical metadata under the store lock.
# Return 1 for invalid checkout, 2 for unsafe path, 3 for incompatible grouping.
projects_registry_prepare_request() {
  local request=$1 state=${2:-null} action path metadata checkouts='[]'
  action=$(jq -r '.action' <<<"$request")
  case "$action" in
    environment-register)
      if jq -e '.args.environment|has("id")' <<<"$request" >/dev/null; then
        printf '%s\n' "$request"
      else
        jq -c --arg id "$(projects_registry_id e)" '.args.environment.id=$id' <<<"$request"
      fi
      ;;
    profiles-seed)
      # No probe for a missing or already-profiled project; the reducer ignores the draft anyway.
      if ! jq -e --argjson state "$state" '.args.projectId as $id | any(($state.projects // [])[]; .id == $id and (.profiles|length) == 0)' <<<"$request" >/dev/null; then
        jq -c '.args.profiles=[]' <<<"$request"
      else
        jq -c --argjson profiles "$(projects_registry_preset_ids "$(projects_registry_presets)")" '.args.profiles=$profiles' <<<"$request"
      fi
      ;;
    profile-save)
      if jq -e '.args.profile|has("id")' <<<"$request" >/dev/null; then
        printf '%s\n' "$request"
      else
        jq -c --arg id "$(projects_registry_id f)" '.args.profile.id=$id' <<<"$request"
      fi
      ;;
    navigation-set)
      # The store owns visit time; callers cannot supply or backdate recency.
      if [[ "$(jq -r '.args.visit // false' <<<"$request")" == true ]]; then
        jq -c --argjson visitedAt "$(date +%s%3N)" '.args.visitedAt=$visitedAt' <<<"$request"
      else
        printf '%s\n' "$request"
      fi
      ;;
    review-mark)
      # The store owns review time; callers cannot supply or backdate it.
      jq -c --argjson reviewedAt "$(date +%s%3N)" '.args.reviewedAt=$reviewedAt' <<<"$request"
      ;;
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
      local drafts presets='{}' new_id new_ids
      # Presets are best-effort: any failure leaves registration without them.
      new_ids=$(jq -r --argjson state "$state" '.[] | .projectId as $p | .commonDir as $c | select(($state.projects // []) | any(.[]; .commonDir == $c) | not) | $p' <<<"$checkouts" | sort -u) || new_ids=''
      if [[ -n "$new_ids" ]]; then
        drafts=$(projects_registry_presets) || drafts='[]'
        while IFS= read -r new_id; do
          presets=$(jq -c --arg p "$new_id" --argjson ids "$(projects_registry_preset_ids "$drafts")" '. + {($p):$ids}' <<<"$presets" 2>/dev/null) || presets='{}'
        done <<<"$new_ids"
      fi
      [[ -n "$presets" ]] || presets='{}'
      jq -c --argjson checkouts "$checkouts" --argjson presets "$presets" '.args.checkouts=$checkouts | .args.presets=$presets' <<<"$request"
      ;;
    *) printf '%s\n' "$request" ;;
  esac
}

# Supply one ID per legacy project; jq migration itself remains pure.
projects_registry_profile_ids() {
  local state=$1 project_id ids='{}'
  while IFS= read -r project_id; do
    ids=$(jq -cn --argjson ids "$ids" --arg projectId "$project_id" --arg id "$(projects_registry_id f)" '$ids + {($projectId):$id}') || return 1
  done < <(jq -r '.projects[].id' <<<"$state")
  printf '%s\n' "$ids"
}
