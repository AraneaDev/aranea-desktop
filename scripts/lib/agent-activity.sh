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
