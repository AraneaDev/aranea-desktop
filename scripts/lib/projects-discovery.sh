#!/usr/bin/env bash
# Bounded breadth-first repository discovery. Registry/Git helpers are sourced
# by the executable before this file; discovery never writes registry state.
: "${discovery_json:=false}"
discovery_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Retain one structured reason while letting already observed candidates survive.
projects_discovery_error() {
  discovery_error_codes+=("$1")
  discovery_error_paths+=("$2")
  discovery_error_messages+=("$3")
}

# Emit a terminal result with authoritative partial status after limits/errors.
projects_discovery_complete() {
  local outcome=observed i discovery_errors
  discovery_errors=$(
    for ((i = 0; i < ${#discovery_error_codes[@]}; i++)); do
      printf '%s\0%s\0%s\0' "${discovery_error_codes[i]}" "${discovery_error_paths[i]}" "${discovery_error_messages[i]}"
    done | jq -Rsc 'split("\u0000") | .[:-1] | [range(0;length;3) as $i | {code:.[$i],path:.[$i+1],message:.[$i+2]}]'
  )
  [[ "$discovery_errors" == '[]' ]] || outcome=partial
  if [[ "$discovery_json" == true ]]; then
    jq -cn --arg outcome "$outcome" --argjson visited "$discovery_visited" --argjson errors "$discovery_errors" '{event:"completed",outcome:$outcome,visited:$visited,errors:$errors}'
  else
    jq -nr --arg outcome "$outcome" --argjson visited "$discovery_visited" --argjson errors "$discovery_errors" '"Scan \($outcome): \($visited) directories visited.", ($errors[] | "\(.code): \(.path): \(.message)")'
  fi
  [[ "$outcome" == observed ]]
}

# Cancellation is handled inside the private process group after child commands
# receive the same signal, so no outstanding Git process can outlive the scan.
projects_discovery_cancel() {
  trap '' TERM INT
  projects_discovery_error CANCELLED '' 'Scan cancelled; choose a folder to scan again.'
  projects_discovery_complete || true
  exit 1
}

# Traverse canonical explicit roots using arrays/globs (no per-directory Git,
# realpath or jq). Directory names remain individual array elements throughout.
projects_discovery_scan() {
  local root canonical path child name depth index=0 metadata status common registry loaded error_code error_path error_message discovery_count_limited=false
  local -a queue=() depths=() children=()
  local -A scheduled=() groups=() ignored_paths=() ignored_groups=()
  discovery_visited=0
  discovery_error_codes=() discovery_error_paths=() discovery_error_messages=()
  trap projects_discovery_cancel TERM INT
  registry="$(aranea_state_root)/projects.json"
  if [[ -e "$registry" || -L "$registry" ]]; then
    if ! loaded=$(jq -cs 'if length == 1 then .[0] else error("Expected one registry object") end' "$registry" 2>/dev/null) ||
      ! jq -e --arg operation validate --argjson request null -f "$discovery_lib_dir/projects-registry.jq" <<<"$loaded" >/dev/null 2>&1; then
      projects_discovery_error REGISTRY_INVALID "$registry" 'Repair the project registry before scanning.'
      projects_discovery_complete || true
      return 1
    fi
    while IFS= read -r -d '' path && IFS= read -r -d '' common; do
      ignored_paths["$path"]=1
      ignored_groups["$common"]=1
    done < <(jq -j '.ignored[] | .path,"\u0000",.commonDir,"\u0000"' <<<"$loaded")
  fi
  for root in "$@"; do
    if canonical=$(projects_registry_path "$root"); then
      if [[ "$canonical" == */.git || "$canonical" == */.git/* ]]; then
        projects_discovery_error ROOT_INVALID "$root" 'Git metadata directories cannot be scanned; choose a checkout folder.'
        continue
      fi
      if [[ -z "${scheduled[$canonical]:-}" ]]; then
        if ((${#queue[@]} >= 20000)); then
          projects_discovery_error DIRECTORY_LIMIT "$root" 'Directory limit reached; choose fewer folders.'
          discovery_count_limited=true
          break
        fi
        queue+=("$canonical")
        depths+=(0)
        scheduled["$canonical"]=1
      fi
    else
      status=$?
      if ((status == 2)); then projects_discovery_error INVALID_PATH "$root" 'Folder paths cannot contain ASCII controls.'; else projects_discovery_error ROOT_INVALID "$root" 'Choose an existing readable folder.'; fi
    fi
  done
  shopt -s nullglob dotglob
  while ((index < ${#queue[@]})); do
    path=${queue[index]} depth=${depths[index]}
    index=$((index + 1))
    discovery_visited=$((discovery_visited + 1))
    if [[ ! -r "$path" || ! -x "$path" ]]; then
      projects_discovery_error DIRECTORY_UNREADABLE "$path" 'Folder could not be read; check its permissions.'
      continue
    fi
    if [[ -e "$path/.git" || (-f "$path/HEAD" && -d "$path/objects" && -d "$path/refs") ]]; then
      if metadata=$(project_git_metadata "$path"); then
        common=$(jq -r '.commonDir' <<<"$metadata")
        if [[ -z "${groups[$common]:-}" ]]; then
          groups["$common"]=1
          if [[ -z "${ignored_paths[$path]:-}" && -z "${ignored_groups[$common]:-}" ]]; then
            while IFS= read -r -d '' error_code && IFS= read -r -d '' error_path && IFS= read -r -d '' error_message; do
              projects_discovery_error "$error_code" "$error_path" "$error_message"
            done < <(jq -j '.metadataErrors[] | .code,"\u0000",.path,"\u0000",.message,"\u0000"' <<<"$metadata")
            metadata=$(jq -c 'del(.metadataErrors)' <<<"$metadata")
            if [[ "$discovery_json" == true ]]; then jq -cn --argjson candidate "$metadata" '{event:"candidate",candidate:$candidate}'; else jq -r '"\(.name): \(.path)", (.checkouts[] | "  \(.path) [\(.branch // "detached")]" )' <<<"$metadata"; fi
          fi
        fi
      else
        status=$?
        case "$status" in
          2) projects_discovery_error INVALID_PATH "$path" 'Checkout paths cannot contain ASCII controls.' ;;
          4)
            projects_discovery_error BARE_UNSUPPORTED "$path" 'Bare repositories are unsupported; choose a checkout.'
            continue
            ;;
          *) projects_discovery_error GIT_METADATA_FAILED "$path" 'Could not read checkout metadata; check the repository.' ;;
        esac
      fi
    fi
    children=("$path"/*)
    for child in "${children[@]}"; do
      [[ -d "$child" && ! -L "$child" ]] || continue
      name=${child##*/}
      case "$name" in .git | node_modules | .venv | venv | vendor | target | build | dist) continue ;; esac
      [[ -z "${scheduled[$child]:-}" ]] || continue
      if ((depth >= 8)); then
        projects_discovery_error DEPTH_LIMIT "$path" 'Depth limit reached; choose a narrower folder.'
        break
      fi
      if ((${#queue[@]} >= 20000)); then
        # Report the ceiling once; process every already queued directory.
        if [[ "${discovery_count_limited:-false}" != true ]]; then
          projects_discovery_error DIRECTORY_LIMIT "$path" 'Directory limit reached; choose a narrower folder.'
          discovery_count_limited=true
        fi
        break
      fi
      queue+=("$child")
      depths+=("$((depth + 1))")
      scheduled["$child"]=1
    done
  done
  trap - TERM INT
  projects_discovery_complete
}
