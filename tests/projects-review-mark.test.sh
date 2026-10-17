#!/usr/bin/env bash
# The store remembers when a task checkout was reviewed.
# Cases are invoked by name in the loop below.
# shellcheck disable=SC2329
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
store="$repo_root/scripts/aranea-project-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
result="$TMPDIR/result.json"
failures=0
head_a=$(printf 'a%.0s' {1..40})
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
# Send review-mark with the given checkout and a JSON object of the remaining arguments.
mark() { jq -cn --arg p "$project_id" --arg c "$1" --argjson rest "$2" '{action:"review-mark",args:({projectId:$p,checkoutId:$c}+$rest)}' | "$store" mutate >"$result"; }
# Catch a mark that is not saved with its head, task time and store time.
mark_saves() {
  setup
  mark "$linked_id" "$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:123}')"
  jq -e --arg c "$linked_id" --arg h "$head_a" '.ok and (.state.projects[0].checkouts[]|select(.id == $c)|.review
    | .reviewedHead == $h and .reviewedTaskAt == 123 and (.reviewedAt|type == "number" and . > 0 and . == floor))' "$result" >/dev/null
}
# Catch a missing task time being refused or dropped.
mark_null_task_time() {
  setup
  mark "$linked_id" "$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:null}')"
  jq -e --arg c "$linked_id" '.ok and (.state.projects[0].checkouts[]|select(.id == $c)|.review|has("reviewedTaskAt") and .reviewedTaskAt == null)' "$result" >/dev/null
}
# Catch the primary checkout being marked.
mark_refuses_primary() {
  setup
  if mark "$primary_id" "$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:1}')"; then return 1; fi
  jq -e '.ok == false and .error.code == "PRIMARY_CHECKOUT"' "$result" >/dev/null
}
# Catch malformed heads, task times or extra fields being accepted.
mark_validates() {
  setup
  local bad
  for bad in \
    '{"head":"abc","taskFinishedAt":1}' \
    "$(jq -cn --arg h "${head_a:0:39}A" '{head:$h,taskFinishedAt:1}')" \
    "$(jq -cn --arg h "${head_a:0:39}g" '{head:$h,taskFinishedAt:1}')" \
    "$(jq -cn --arg h "$head_a"$'\n' '{head:$h,taskFinishedAt:1}')" \
    "$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:"x"}')" \
    "$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:-1}')" \
    "$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:1,reviewedAt:5}')"; do
    if mark "$linked_id" "$bad"; then return 1; fi
    jq -e '.error.code == "INVALID_REQUEST"' "$result" >/dev/null
  done
}
# Catch unknown ids without a clear code.
unknown_ids() {
  setup
  local rest
  rest=$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:1}')
  if mark c-00000000-0000-4000-8000-000000000000 "$rest"; then return 1; fi
  jq -e '.error.code == "CHECKOUT_NOT_FOUND"' "$result" >/dev/null
  project_id=p-00000000-0000-4000-8000-000000000000
  if mark "$linked_id" "$rest"; then return 1; fi
  jq -e '.error.code == "PROJECT_NOT_FOUND"' "$result" >/dev/null
}
# Catch removal leaving a broken registry after a mark.
remove_drops_mark() {
  setup
  mark "$linked_id" "$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:1}')"
  jq -cn --arg p "$project_id" --arg c "$linked_id" '{action:"checkout-remove",args:{projectId:$p,checkoutId:$c}}' | "$store" mutate >"$result"
  jq -e '.ok and (.state.projects[0].checkouts|length == 1) and ([.state.projects[0].checkouts[]|has("review")]|any|not)' "$result" >/dev/null
}
# Catch a mark that stops the registry loading or later changes working.
registry_validates_with_mark() {
  setup
  mark "$linked_id" "$(jq -cn --arg h "$head_a" '{head:$h,taskFinishedAt:1}')"
  jq -cn --arg p "$project_id" --arg c "$linked_id" '{action:"select-checkout",args:{projectId:$p,checkoutId:$c}}' | "$store" mutate >"$result"
  jq -e '.ok' "$result" >/dev/null
  "$store" snapshot >"$result"
  jq -e --arg c "$linked_id" '.state.projects[0].checkouts[]|select(.id == $c)|.review.reviewedTaskAt == 1' "$result" >/dev/null
}
cases=(mark_saves mark_null_task_time mark_refuses_primary mark_validates unknown_ids remove_drops_mark registry_validates_with_mark)
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
