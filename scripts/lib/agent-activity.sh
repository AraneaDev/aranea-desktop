#!/usr/bin/env bash
# Activity filesystem preparation. The caller holds the activity lock throughout.

# Canonicalize only exact existing directories, never infer a containing checkout.
agent_activity_prepare() {
  local request="$1" action item cwd canonical prepared index=0
  action=$(jq -r .action <<<"$request")
  prepared=$request
  if [[ "$action" == register ]]; then
    while IFS= read -r item; do
      cwd=$(jq -r .cwd <<<"$item")
      canonical=$(realpath -e -- "$cwd") || return 1
      [[ -d "$canonical" && ! "$canonical" =~ [[:cntrl:]] ]] || return 1
      prepared=$(jq -c --arg p "$canonical" --argjson i "$index" '.args.tasks[$i].cwd=$p' <<<"$prepared")
      index=$((index + 1))
    done < <(jq -c '.args.tasks[]' <<<"$request")
  elif [[ "$action" == report && $(jq -r .args.kind <<<"$request") == snapshot ]]; then
    cwd=$(jq -r .args.payload.cwd <<<"$request")
    canonical=$(realpath -e -- "$cwd") || return 1
    [[ -d "$canonical" && ! "$canonical" =~ [[:cntrl:]] ]] || return 1
    prepared=$(jq -c --arg p "$canonical" '.args.payload.cwd=$p' <<<"$prepared")
  fi
  printf '%s\n' "$prepared"
}

# Native adapters use only this bounded first nonblank line as a default label.
# Reads raw prompt stdin and emits plain display text; never saves full input.
agent_activity_prompt_description() {
  jq -Rrs 'split("\n") | map(gsub("^[[:space:]]+|[[:space:]]+$";"")) | map(select(length > 0)) | (.[0] // "") | gsub("[\\x00-\\x1f\\x7f]";"") | .[:160]'
}

# A replay must not re-resolve a disappeared checkout or refresh connection time.
agent_activity_is_replay() {
  local request="$1" state="$2" hash="$3"
  jq -e --arg hash "$hash" --argjson r "$(jq '{action,args:(.args|{provider,providerSessionId,producerEpoch,eventId})}' <<<"$request")" '
    any(.sessions[]; .provider == $r.args.provider and .providerSessionId == $r.args.providerSessionId and .producerEpoch == $r.args.producerEpoch
      and (if $r.action == "register" then .registrationHash == $hash else any(.receipts[];.eventId == $r.args.eventId and .hash == $hash) end))' <<<"$state" >/dev/null
}

# Capture ingress lifetime before waiting or reading hook input. The coordination
# inode survives uninstall; its content changes only under its transaction lock.
agent_activity_generation() {
  local lock generation=''
  lock="$(aranea_state_root)/agent-activity.json.lock"
  if [[ -L "$lock" || (-e "$lock" && ! -f "$lock") ]]; then
    printf 'unsafe\n'
    return 0
  fi
  [[ ! -e "$lock" ]] || generation=$(head -c 128 -- "$lock") || return 1
  printf '%s\n' "${generation:-initial}"
}

# Join the same authority for stores and helper startup. A retired ingress cannot
# cross teardown or reinstall, even if it had not reached the store yet.
# Caller supplies activity_generation and consumes activity_lock_error/fd.
# shellcheck disable=SC2034,SC2154
agent_activity_lock() {
  local wait=$1 lifecycle=${2:-false} current
  local lock
  lock="$(aranea_state_root)/agent-activity.json.lock"
  activity_lock_error=ACTIVITY_WRITE_FAILED
  mkdir -p -- "$(dirname "$lock")" || return 1
  activity_lock_error=UNSAFE_STATE_PATH
  [[ ! -L "$lock" && (! -e "$lock" || -f "$lock") ]] || return 1
  activity_lock_error=ACTIVITY_WRITE_FAILED
  exec {activity_lock_fd}<>"$lock" || return 1
  activity_lock_error=ACTIVITY_LOCK_FAILED
  flock -w "$wait" -x "$activity_lock_fd" || return 1
  current=$(agent_activity_generation) || return 1
  activity_lock_error=ACTIVITY_REMOVED
  if [[ "$lifecycle" != true ]]; then
    [[ "$current" != removed:* && "$current" == "$activity_generation" ]] || return 1
  fi
}
