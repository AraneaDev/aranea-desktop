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

# A task checkout with one commit, pushed nowhere yet.
task_with_commit() {
  setup
  cli_run projects task new "$project_id" --branch t
  task_id=$(jq -sr 'last.data.checkoutId' "$events")
  task_path=$(jq -sr 'last.data.path' "$events")
  git -C "$task_path" -c user.name=T -c user.email=t@example.invalid commit -q --allow-empty -m work
}
# Catch a review that does not report the commits ahead of the base.
review_reads() {
  task_with_commit
  cli_run projects review "$project_id" --checkout "$task_id"
  last '.operation=="projects.review" and .status=="observed" and .message=="Review read." and .data.ahead==1'
}
# Catch a mark that is not saved on the checkout, or that fails without activity state.
review_mark_saves() {
  task_with_commit
  local head
  head=$(git -C "$task_path" rev-parse HEAD)
  cli_run projects review mark "$project_id" --checkout "$task_id"
  jq -se --arg h "$head" 'last|.message=="Review marked." and .data.head==$h and .data.taskFinishedAt==null' "$events" >/dev/null
  "$store" snapshot | jq -e --arg c "$task_id" --arg h "$head" '.state.projects[0].checkouts[]|select(.id==$c)|.review.reviewedHead==$h' >/dev/null
}
# Report one task in a directory through the real agent store; $1 task id, $2 cwd, $3 state, $4 sequence.
agent_task() {
  jq -cn --arg t "$1" --arg cwd "$2" --arg s "$3" --argjson n "$4" '{action:"report",args:{schemaVersion:1,eventId:("e-"+$t+"-"+($n|tostring)),provider:"claude",providerSessionId:"session",producerEpoch:"epoch",sequence:$n,taskId:$t,kind:"snapshot",payload:{cwd:$cwd,reportedState:$s,description:"Task"}}}' | "$repo_root/scripts/aranea-agent-store" mutate >/dev/null
}
# Register the agent session, then mark the task checkout and compare taskFinishedAt with $1 (jq filter on the snapshot, or null).
mark_task_time() {
  local want
  cli_run projects review mark "$project_id" --checkout "$task_id"
  want=$("$repo_root/scripts/aranea-agent-store" snapshot | jq -c "$1")
  jq -se --argjson w "$want" 'last.data.taskFinishedAt==$w' "$events" >/dev/null
}
# Register an empty agent session and epoch in the real agent store.
agent_register() { jq -cn '{action:"register",args:{provider:"claude",providerSessionId:"session",producerEpoch:"epoch",tasks:[]}}' | "$repo_root/scripts/aranea-agent-store" mutate >/dev/null; }
# Catch a finished task in the checkout not giving the mark its task time.
mark_task_time_finished() {
  task_with_commit
  agent_register
  agent_task one "$task_path" ready-for-review 1
  mark_task_time '[.state.tasks[]|select(.taskId=="one")|.lastReceivedAt][0]'
  jq -se 'last.data.taskFinishedAt|type=="number"' "$events" >/dev/null
}
# Catch the earlier task time winning over the later one.
mark_task_time_latest() {
  task_with_commit
  agent_register
  agent_task one "$task_path" failed 1
  sleep 1
  agent_task two "$task_path" finished 2
  mark_task_time '[.state.tasks[]|select(.taskId=="two")|.lastReceivedAt][0]'
  jq -se 'last.data.taskFinishedAt as $t|$t|type=="number"' "$events" >/dev/null
  "$repo_root/scripts/aranea-agent-store" snapshot | jq -e '[.state.tasks[].lastReceivedAt]|(max > min)' >/dev/null
}
# Catch a finished task of another checkout leaking into the mark.
mark_task_time_other_checkout() {
  task_with_commit
  agent_register
  agent_task one "$repo" finished 1
  mark_task_time null
}
# Catch a working task counting as finished.
mark_task_time_working() {
  task_with_commit
  agent_register
  agent_task one "$task_path" working 1
  mark_task_time null
}
# Catch a push that does not report the pushed branch.
push_pushes() {
  task_with_commit
  cli_run projects git push "$project_id" --checkout "$task_id"
  last '.operation=="projects.git.push" and .status=="observed" and .data.pushed==true'
}
# Catch review commands without a checkout that do not exit 2.
review_usage() {
  setup
  local s
  for args in "review $project_id" "review mark $project_id"; do
    s=0
    # shellcheck disable=SC2086
    cli_run projects $args || s=$?
    [[ $s == 2 ]]
    last '.code=="INVALID_USAGE"'
  done
}
# Catch review and push missing from the capabilities.
capabilities_list_review() {
  setup
  cli_run capabilities
  jq -se 'last.data as $d | all(["projects.review","projects.review.mark","projects.git.push"][]; . as $n | any($d.operations[]; .name==$n))' "$events" >/dev/null
}

cases=(fetch_envelope checkout_defaults_to_last task_new_and_remove task_new_ignores_selected_checkout failure_envelope usage_errors capabilities_list_git review_reads review_mark_saves mark_task_time_finished mark_task_time_latest mark_task_time_other_checkout mark_task_time_working push_pushes review_usage capabilities_list_review)
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
