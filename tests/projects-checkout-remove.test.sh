#!/usr/bin/env bash
# The store drops one linked checkout with its associations and environments.
# Cases are invoked by name in the loop below.
# shellcheck disable=SC2329
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
store="$repo_root/scripts/aranea-project-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
result="$TMPDIR/result.json"
failures=0
# One project with a primary checkout and one linked worktree, both registered.
setup() {
  rm -rf "$ARANEA_STATE_ROOT" "$ARANEA_TEST_SANDBOX/app" "$ARANEA_TEST_SANDBOX/app-worktrees"
  repo="$ARANEA_TEST_SANDBOX/app"
  git init -q -b main "$repo"
  git -C "$repo" -c user.name=T -c user.email=t@example.invalid commit -q --allow-empty -m init
  linked="$ARANEA_TEST_SANDBOX/app-worktrees/feat"
  git -C "$repo" worktree add -q -b feat "$linked"
  jq -cn --arg a "$repo" --arg b "$linked" '{action:"register",args:{paths:[$a,$b]}}' | "$store" mutate >"$result"
  project_id=$(jq -r '.state.projects[0].id' "$result")
  primary_id=$(jq -r '.state.projects[0].checkouts[]|select(.primary)|.id' "$result")
  linked_id=$(jq -r '.state.projects[0].checkouts[]|select(.primary|not)|.id' "$result")
}
# Remove the checkout through the store and save the response.
remove() { jq -cn --arg p "$1" --arg c "$2" '{action:"checkout-remove",args:{projectId:$p,checkoutId:$c}}' | "$store" mutate >"$result"; }
# Catch removing a task checkout that fails or leaves it selected.
removes_linked_and_moves_selection() {
  setup
  jq -cn --arg p "$project_id" --arg c "$linked_id" '{action:"select-checkout",args:{projectId:$p,checkoutId:$c}}' | "$store" mutate >/dev/null
  remove "$project_id" "$linked_id"
  jq -e --arg p "$primary_id" '.ok and (.state.projects[0].checkouts|length == 1) and .state.projects[0].lastCheckoutId == $p' "$result" >/dev/null
}
# Catch removal of the primary or the only remaining checkout.
refuses_primary_and_last() {
  setup
  if remove "$project_id" "$primary_id"; then return 1; fi
  jq -e '.ok == false and .error.code == "CHECKOUT_REQUIRED"' "$result" >/dev/null
  remove "$project_id" "$linked_id"
  if remove "$project_id" "$primary_id"; then return 1; fi
  jq -e '.error.code == "CHECKOUT_REQUIRED"' "$result" >/dev/null
}
# Catch unknown checkout or project ids that do not fail with a clear code.
unknown_ids_fail_cleanly() {
  setup
  if remove "$project_id" c-00000000-0000-4000-8000-000000000000; then return 1; fi
  jq -e '.error.code == "CHECKOUT_NOT_FOUND"' "$result" >/dev/null
  if remove p-00000000-0000-4000-8000-000000000000 "$linked_id"; then return 1; fi
  jq -e '.error.code == "PROJECT_NOT_FOUND"' "$result" >/dev/null
}
# Catch extra request fields such as force being accepted.
extra_fields_are_rejected() {
  setup
  if jq -cn --arg p "$project_id" --arg c "$linked_id" '{action:"checkout-remove",args:{projectId:$p,checkoutId:$c,force:true}}' | "$store" mutate >"$result"; then return 1; fi
  jq -e '.error.code == "INVALID_REQUEST"' "$result" >/dev/null
}
# Send one store mutation with the given action and arguments.
mutate_args() { jq -cn --arg a "$1" --argjson args "$2" '{action:$a,args:$args}' | "$store" mutate >"$result"; }
# Catch removal leaving associations or environments of the removed checkout.
drops_associations_and_environments() {
  setup
  mutate_args profile-save "$(jq -cn --arg p "$project_id" '{projectId:$p,profile:{name:"Dev",roles:["terminal"],tools:{editorId:null,terminalId:"kitty",agentId:null}}}')"
  local profile
  profile=$(jq -c '.state.projects[0].profiles[0]' "$result")
  local n=1 c
  for c in "$primary_id" "$linked_id"; do
    mutate_args associate "$(jq -cn --arg p "$project_id" --arg c "$c" '{projectId:$p,checkoutId:$c,mode:"dedicated",workspaceId:7,separate:true}')"
    jq .state "$result" >"$TMPDIR/state.json"
    mutate_args environment-register "$(jq -cn --slurpfile state "$TMPDIR/state.json" --arg p "$project_id" --arg c "$c" --argjson profile "$profile" --arg n "$n" '$state[0].projects[0] as $pr | {projectId:$p,environment:{id:("e-1111111\($n)-1111-4111-8111-111111111111"),projectId:$p,checkoutId:$c,activationId:("a-1111111\($n)-1111-4111-8111-111111111111"),workspaceId:9,sessionId:"s",createdAt:123,checkoutSnapshot:($pr.checkouts[]|select(.id==$c)),profileSnapshot:$profile,resolvedTools:$profile.tools}}')"
    n=$((n + 1))
  done
  jq -e --arg c "$linked_id" '[.state.projects[0].associations[]|select(.checkoutId==$c)]|length > 0' "$result" >/dev/null
  remove "$project_id" "$linked_id"
  jq -e --arg c "$primary_id" '.ok
    and ([.state.projects[0].associations[]|select(.checkoutId != $c)]|length == 0)
    and ([.state.projects[0].environments[]|select(.checkoutId != $c)]|length == 0)
    and ([.state.projects[0].environments[]|select(.checkoutId == $c)]|length == 1)
    and ([.state.projects[0].associations[]|select(.checkoutId == $c)]|length == 1)' "$result" >/dev/null
}
cases=(removes_linked_and_moves_selection refuses_primary_and_last unknown_ids_fail_cleanly extra_fields_are_rejected drops_associations_and_environments)
if (($#)); then cases=("$@"); fi
for case_name in "${cases[@]}"; do
  set +e
  (
    set -e
    "$case_name"
  )
  status=$?
  set -e
  if ((status == 0)); then printf 'PASS %s\n' "$case_name"; else
    printf 'FAIL %s\n' "$case_name"
    failures=$((failures + 1))
  fi
done
exit "$((failures > 0))"
