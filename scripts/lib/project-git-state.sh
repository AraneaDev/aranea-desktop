#!/usr/bin/env bash
# Selected-checkout observation. All identity reads, Git reads and parsing run
# inside the same deadline; registry/repository files are never initialized.

# Emit one structured failure without leaking partial Git state.
project_git_state_error() {
  jq -cn --arg code "$1" --arg message "$2" --arg recovery "$3" \
    '{ok:false,data:null,error:{code:$code,message:$message,recovery:$recovery}}'
  return 1
}

# Capture at most the byte limit plus one sentinel byte. Closing the pipe
# terminates an oversized producer; no incomplete capture reaches the parser.
project_git_state_capture() {
  local output=$1 status
  shift
  if projects_registry_git "$@" 2>/dev/null | project_git_state_limit "$output"; then status=0; else status=$?; fi
  if ((status != 0)); then
    project_git_state_error "${git_state_failure_code:-GIT_ERROR}" 'Git could not read the selected checkout.' 'Check repository permissions and Git metadata, then refresh.'
    return 1
  fi
}

# The deadline supervisor owns a private process group. A byte-limit breach
# terminates that group immediately, including producers that ignore SIGPIPE.
project_git_state_limit() {
  local output=$1 bytes
  head -c 2097153 >"$output" || return 1
  bytes=$(wc -c <"$output")
  if ((bytes > 2097152)); then
    : >"$git_state_tmp/output-limit"
    kill -KILL 0
    return 1
  fi
}

# Read one bounded Git metadata value, preserving its final path bytes.
project_git_state_value() {
  local destination=$1 value
  shift
  project_git_state_capture "$git_state_tmp/value" "$@" || return 1
  value=$(<"$git_state_tmp/value")
  printf -v "$destination" '%s' "$value"
}

# Parse complete NUL records, consuming rename sources as separate records.
# Counts overlap intentionally; only file details are capped.
project_git_state_parse() {
  local input=$1 project=$2 checkout=$3 path=$4 record rest kind xy original fields i count=0 encoded_path encoded_original file_record
  local branch='' branch_seen=false detached=false upstream='' ahead=null behind=null staged=0 unstaged=0 untracked=0 conflicts=0 conflict=false
  : >"$git_state_tmp/files"
  while :; do
    record=''
    if ! IFS= read -r -d '' record; then
      [[ -z "$record" ]] && break
      project_git_state_error GIT_ERROR 'Git returned an incomplete status record.' 'Retry the observation or inspect Git status in a terminal.'
      return 1
    fi
    original=''
    conflict=false
    case "$record" in
      '# branch.head '*)
        branch_seen=true
        branch=${record#\# branch.head }
        if [[ "$branch" == '(detached)' ]]; then
          branch=''
          detached=true
        fi
        continue
        ;;
      '# branch.upstream '*)
        upstream=${record#\# branch.upstream }
        continue
        ;;
      '# branch.ab '*)
        if [[ "$record" =~ ^\#\ branch\.ab\ \+([0-9]+)\ -([0-9]+)$ ]]; then
          ahead=${BASH_REMATCH[1]}
          behind=${BASH_REMATCH[2]}
        fi
        continue
        ;;
      '# '*) continue ;;
      '? '*)
        xy='??'
        rest=${record#'? '}
        untracked=$((untracked + 1))
        ;;
      '1 '* | '2 '* | 'u '*)
        kind=${record:0:1}
        xy=${record:2:2}
        case "$kind" in 1) fields=8 ;; 2) fields=9 ;; u)
          fields=10
          conflict=true
          conflicts=$((conflicts + 1))
          ;;
        esac
        rest=$record
        for ((i = 0; i < fields; i++)); do
          if [[ "$rest" != *' '* ]]; then
            project_git_state_error GIT_ERROR 'Git returned a malformed status record.' 'Retry the observation or inspect Git status in a terminal.'
            return 1
          fi
          rest=${rest#* }
        done
        [[ ${xy:0:1} == '.' ]] || staged=$((staged + 1))
        [[ ${xy:1:1} == '.' ]] || unstaged=$((unstaged + 1))
        if [[ "$kind" == 2 ]]; then
          if ! IFS= read -r -d '' original || [[ -z "$original" ]]; then
            project_git_state_error GIT_ERROR 'Git returned an incomplete rename record.' 'Retry the observation or inspect Git status in a terminal.'
            return 1
          fi
        fi
        ;;
      *)
        project_git_state_error GIT_ERROR 'Git returned an unsupported status record.' 'Retry using a supported Git version.'
        return 1
        ;;
    esac
    [[ -n "$rest" ]] || return 1
    if ((count < 500)); then
      # Raw paths are typed JSON strings; controls are escaped on the wire and
      # display escaping belongs to presentation, never to identity parsing.
      jq -jn --arg path "$rest" --arg original "$original" --arg index "${xy:0:1}" --arg worktree "${xy:1:1}" --argjson conflict "$conflict" \
        '$path,"\u0000",$original,"\u0000",({path:$path,originalPath:(if $original == "" then null else $original end),indexStatus:$index,worktreeStatus:$worktree,conflict:$conflict}|tojson),"\u0000"' >"$git_state_tmp/record" || return 1
      # JSON strings require UTF-8. Reject jq replacement bytes rather than
      # reporting a different filename; the same check covers rename sources.
      {
        IFS= read -r -d '' encoded_path &&
          IFS= read -r -d '' encoded_original &&
          IFS= read -r -d '' file_record
      } <"$git_state_tmp/record" || return 1
      if [[ "$encoded_path" != "$rest" || "$encoded_original" != "$original" ]]; then
        project_git_state_error GIT_ERROR 'A changed filename cannot be represented faithfully as UTF-8 JSON.' 'Inspect Git status in a terminal or rename the file to a valid UTF-8 name, then refresh.'
        return 1
      fi
      printf '%s\n' "$file_record" >>"$git_state_tmp/files"
    fi
    count=$((count + 1))
  done <"$input"
  if [[ "$branch_seen" != true ]]; then
    project_git_state_error GIT_ERROR 'Git did not report the checkout branch state.' 'Retry the observation or inspect Git status in a terminal.'
    return 1
  fi
  [[ -n "$upstream" ]] || {
    ahead=null
    behind=null
  }
  jq -sc --arg project "$project" --arg checkout "$checkout" --arg path "$path" --argjson observed "$(date +%s%3N)" \
    --arg branch "$branch" --argjson detached "$detached" --arg upstream "$upstream" --argjson ahead "$ahead" --argjson behind "$behind" \
    --argjson staged "$staged" --argjson unstaged "$unstaged" --argjson untracked "$untracked" --argjson conflicts "$conflicts" --argjson truncated "$((count > 500))" \
    '{ok:true,error:null,data:{projectId:$project,checkoutId:$checkout,path:$path,observedAt:$observed,branch:(if $branch == "" then null else $branch end),detached:$detached,upstream:(if $upstream == "" then null else $upstream end),ahead:$ahead,behind:$behind,counts:{staged:$staged,unstaged:$unstaged,untracked:$untracked,conflicts:$conflicts},files:.,truncated:($truncated == 1)}}' "$git_state_tmp/files"
}

# Validate only the selected registered checkout, without enumerating relatives.
project_git_state_observe() {
  local project=$1 checkout=$2 registry selected path canonical common registered_common primary registered_primary top bare git_dir
  local git_state_failure_code=CHECKOUT_INVALID
  registry="$(aranea_state_root)/projects.json"
  if [[ ! -f "$registry" ]] || ! jq -es \
    'if length == 1 then .[0] else null end' "$registry" >"$git_state_tmp/registry" 2>/dev/null ||
    ! jq -e --arg operation validate --argjson request null -f "$git_state_lib/projects-registry.jq" "$git_state_tmp/registry" >/dev/null 2>&1; then
    project_git_state_error REGISTRY_INVALID 'The project registry is missing or invalid.' 'Register the project or repair projects.json, then refresh.'
    return 1
  fi
  selected=$(jq -c --arg project "$project" --arg checkout "$checkout" \
    '.projects[] | select(.id == $project) | .commonDir as $common | .checkouts[] | select(.id == $checkout) | . + {commonDir:$common}' "$git_state_tmp/registry")
  if [[ -z "$selected" ]]; then
    project_git_state_error CHECKOUT_INVALID 'The selected project and checkout are not registered together.' 'Refresh Projects and select a registered checkout.'
    return 1
  fi
  path=$(jq -r .path <<<"$selected")
  registered_common=$(jq -r .commonDir <<<"$selected")
  registered_primary=$(jq -r .primary <<<"$selected")
  if ! canonical=$(projects_registry_path "$path") || [[ "$canonical" != "$path" ]]; then
    project_git_state_error CHECKOUT_INVALID 'The registered checkout folder is missing or has moved.' 'Locate the exact checkout in Manage project, then refresh.'
    return 1
  fi
  project_git_state_value bare -C "$path" rev-parse --is-bare-repository || return 1
  project_git_state_value top -C "$path" rev-parse --show-toplevel || return 1
  project_git_state_value common -C "$path" rev-parse --path-format=absolute --git-common-dir || return 1
  project_git_state_value git_dir -C "$path" rev-parse --absolute-git-dir || return 1
  primary=false
  [[ "$git_dir" != "$common" ]] || primary=true
  if [[ "$bare" != false || "$top" != "$path" || "$common" != "$registered_common" || "$primary" != "$registered_primary" ]]; then
    project_git_state_error CHECKOUT_INVALID 'The checkout no longer matches its registered Git identity.' 'Repair or locate the registered checkout in Manage project.'
    return 1
  fi
  git_state_failure_code=GIT_ERROR
  project_git_state_capture "$git_state_tmp/status" -C "$path" status --porcelain=v2 --branch -z --untracked-files=all || return 1
  project_git_state_parse "$git_state_tmp/status" "$project" "$checkout" "$path"
}

# Public argument/dependency boundary and private deadline supervisor.
project_git_state_main() (
  local project='' checkout='' json=false dependency status
  for dependency in jq git timeout mktemp head wc date realpath bash cat rm dirname; do
    if ! command -v "$dependency" >/dev/null; then
      printf '{"ok":false,"data":null,"error":{"code":"DEPENDENCY_MISSING","message":"Install %s to inspect Git state.","recovery":"Install the missing dependency and refresh."}}\n' "$dependency"
      return 1
    fi
  done
  while (($#)); do
    case "$1" in
      --project | --checkout)
        [[ $# -ge 2 && -n "$2" ]] || {
          project_git_state_error INVALID_REQUEST 'Provide project and checkout IDs.' 'Select a registered checkout and retry.'
          return 1
        }
        if [[ "$1" == --project ]]; then project=$2; else checkout=$2; fi
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *)
        project_git_state_error INVALID_REQUEST 'Unsupported Git-state argument.' 'Use --project, --checkout and --json.'
        return 1
        ;;
    esac
  done
  [[ -n "$project" && -n "$checkout" && "$json" == true ]] || {
    project_git_state_error INVALID_REQUEST 'Provide project and checkout IDs with --json.' 'Select a registered checkout and retry.'
    return 1
  }
  umask 077
  git_state_tmp=$(mktemp -d) || {
    project_git_state_error GIT_ERROR 'Cannot create a private observation directory.' 'Check temporary-directory permissions and space.'
    return 1
  }
  trap 'rm -rf -- "$git_state_tmp"' EXIT
  git_state_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # These variables expand in the child Bash, not the supervisor.
  # shellcheck disable=SC2016
  if { timeout --kill-after=1s 8s bash -c '
    set -euo pipefail
    git_state_lib=$1; git_state_tmp=$2
    source "$git_state_lib/paths.sh"
    source "$git_state_lib/projects-registry.sh"
    source "$git_state_lib/project-git-state.sh"
    project_git_state_observe "$3" "$4"
  ' bash "$git_state_lib" "$git_state_tmp" "$project" "$checkout" >"$git_state_tmp/response"; } 2>/dev/null; then status=0; else status=$?; fi
  if [[ -e "$git_state_tmp/output-limit" ]]; then
    project_git_state_error GIT_OUTPUT_LIMIT 'The checkout produced more than 2 MiB of Git output.' 'Reduce checkout changes or inspect this repository in a terminal.'
  elif [[ "$status" == 124 || "$status" == 137 ]]; then
    project_git_state_error GIT_TIMEOUT 'Reading the checkout exceeded the eight-second deadline.' 'Retry or inspect this repository in a terminal.'
  elif [[ -s "$git_state_tmp/response" ]]; then
    # A timed-out parser never publishes a partial successful observation.
    cat "$git_state_tmp/response"
    return "$status"
  else
    project_git_state_error GIT_ERROR 'The selected checkout could not be observed.' 'Check checkout permissions and Git metadata, then refresh.'
  fi
)
