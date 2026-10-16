#!/usr/bin/env bash
# Public git/task commands over a real bare remote; asserts the NDJSON envelope.
# shellcheck disable=SC2329
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
store="$repo_root/scripts/aranea-project-store"
cli="$repo_root/scripts/aranea"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
events="$TMPDIR/events"
result="$TMPDIR/result.json"
failures=0
# A bare remote, a registered clone and the CLI state, rebuilt fresh for each case.
setup() {
  rm -rf "$ARANEA_STATE_ROOT" "$ARANEA_TEST_SANDBOX/w"
  mkdir -p "$ARANEA_TEST_SANDBOX/w"
  remote="$ARANEA_TEST_SANDBOX/w/remote.git"
  git init -q --bare -b main "$remote"
  seed="$ARANEA_TEST_SANDBOX/w/seed"
  git clone -q "$remote" "$seed" 2>/dev/null
  git -C "$seed" -c user.name=T -c user.email=t@example.invalid commit -q --allow-empty -m init
  git -C "$seed" push -q origin HEAD:main
  repo="$ARANEA_TEST_SANDBOX/w/app"
  git clone -q "$remote" "$repo"
  git -C "$repo" config user.name T
  git -C "$repo" config user.email t@example.invalid
  jq -cn --arg path "$repo" '{action:"register",args:{paths:[$path]}}' | "$store" mutate >"$result"
  project_id=$(jq -r '.state.projects[0].id' "$result")
  checkout_id=$(jq -r '.state.projects[0].checkouts[0].id' "$result")
}
# Run the public CLI, keep NDJSON, and return its exit status.
cli_run() {
  local status=0
  "$cli" "$@" --json >"$events" 2>/dev/null </dev/null || status=$?
  return "$status"
}
# Assert a jq expression on the last event of the CLI run.
last() { jq -se "last | $1" "$events" >/dev/null; }

# Catch a fetch whose public events lack the start event or the remote name.
fetch_envelope() {
  setup
  cli_run projects git fetch "$project_id" --checkout "$checkout_id"
  last '.event=="completed" and .operation=="projects.git.fetch" and .status=="observed" and .data.remote=="origin"'
  jq -se 'first.event=="started"' "$events" >/dev/null
}
# Catch a missing --checkout that fails instead of using the selected checkout.
checkout_defaults_to_last() {
  setup
  cli_run projects git fetch "$project_id"
  jq -se --arg c "$checkout_id" 'last.data.checkoutId==$c' "$events" >/dev/null
}
# Catch a task checkout that is created without a folder, or removed by its check.
task_new_and_remove() {
  setup
  cli_run projects task new "$project_id" --branch t
  last '.operation=="projects.task.new" and .status=="observed" and (.data.path|length>0)'
  local path new_id
  path=$(jq -sr 'last.data.path' "$events")
  [[ -d $path ]]
  new_id=$(jq -sr 'last.data.checkoutId' "$events")
  cli_run projects task remove "$project_id" --checkout "$new_id" --check
  last '.operation=="projects.task.remove" and .data.dirty==false'
  [[ -d $path ]]
  cli_run projects task remove "$project_id" --checkout "$new_id"
  last '.status=="observed" and .data.removed==true'
  [[ ! -d $path ]]
}
# Catch a task made while a vanished task checkout is selected failing instead of using the main checkout.
task_new_ignores_selected_checkout() {
  setup
  cli_run projects task new "$project_id" --branch first
  local path
  path=$(jq -sr 'last.data.path' "$events")
  rm -rf "$path"
  cli_run projects task new "$project_id" --branch second
  last '.status=="observed" and (.data.path|endswith("/app-worktrees/second"))'
}
# Catch a helper failure that loses its error code, recovery or exit status 1.
failure_envelope() {
  setup
  git -C "$repo" branch --unset-upstream
  local s=0
  cli_run projects git pull "$project_id" --checkout "$checkout_id" || s=$?
  [[ $s == 1 ]]
  last '.event=="completed" and .status=="failed" and .code=="NO_UPSTREAM" and (.data.recovery|length>0)'
}
# Catch malformed task and git commands that do not exit 2 with INVALID_USAGE.
usage_errors() {
  setup
  local s
  for args in "task new $project_id" "task remove $project_id" "git fetch" "task new $project_id --branch a --branch b"; do
    s=0
    # shellcheck disable=SC2086
    cli_run projects $args || s=$?
    [[ $s == 2 ]]
    last '.code=="INVALID_USAGE"'
  done
}
# Catch missing git and task operations or projectGit object in the capabilities.
capabilities_list_git() {
  setup
  cli_run capabilities
  jq -se 'last.data as $d | all(["projects.git.fetch","projects.git.pull","projects.task.new","projects.task.remove"][]; . as $n | any($d.operations[]; .name==$n)) and $d.projectGit.worktreeLocation=="<repo>-worktrees/<branch>"' "$events" >/dev/null
}

cases=(fetch_envelope checkout_defaults_to_last task_new_and_remove task_new_ignores_selected_checkout failure_envelope usage_errors capabilities_list_git)
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
