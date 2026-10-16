#!/usr/bin/env bash
# Task checkout create and remove against real repositories and a real bare remote.
# Cases are invoked by name in the loop below.
# shellcheck disable=SC2329
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
helper="$repo_root/scripts/aranea-project-git"
store="$repo_root/scripts/aranea-project-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
result="$TMPDIR/result.json"
failures=0
# A bare "remote", a clone registered as the project, and a second clone that pushes.
setup() {
  rm -rf "$ARANEA_STATE_ROOT" "$ARANEA_TEST_SANDBOX/w" "${TMPDIR:?}/bin"
  mkdir -p "$ARANEA_TEST_SANDBOX/w" "${TMPDIR:?}/bin"
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
push_upstream() { git -C "$seed" -c user.name=T -c user.email=t@example.invalid commit -q --allow-empty -m "$1" && git -C "$seed" push -q origin HEAD:main; }
run() { "$helper" "$1" --project "$project_id" --checkout "$checkout_id" "${@:2}" --json >"$result"; }
expect_code() { ! run "${@:2}" && jq -e --arg c "$1" '.ok == false and .data == null and .error.code == $c and (.error.recovery|length > 0)' "$result" >/dev/null; }
action_store="$repo_root/scripts/aranea-project-action-store"
task_new() { "$helper" task-create --project "$project_id" --checkout "$checkout_id" --branch "$1" --json >"$result"; }
linked_id() { jq -r --arg p "$1" '.projects[0].checkouts[]|select(.path == $p)|.id' "$ARANEA_STATE_ROOT/projects.json"; }
registry_count() { jq '.projects[0].checkouts|length' "$ARANEA_STATE_ROOT/projects.json"; }
# Create a task checkout and leave its id in $task_id and path in $task_path.
make_task() {
  task_new "$1"
  jq -e '.ok' "$result" >/dev/null
  task_id=$(jq -r .data.checkoutId "$result")
  task_path=$(jq -r .data.path "$result")
}
task_run() { "$helper" "$1" --project "$project_id" --checkout "$task_id" "${@:2}" --json >"$result"; }
task_expect() { ! task_run "${@:2}" && jq -e --arg c "$1" '.ok == false and .data == null and .error.code == $c and (.error.recovery|length > 0)' "$result" >/dev/null; }
commit_in() { git -C "$1" -c user.name=T -c user.email=t@example.invalid commit -q --allow-empty -m "$2"; }

task_create_from_remote_default() {
  setup
  push_upstream two
  task_new feat/login
  jq -e --arg p "$ARANEA_TEST_SANDBOX/w/app-worktrees/feat-login" '.ok and .data.path == $p and .data.branch == "feat/login" and .data.base == "origin/main"' "$result" >/dev/null
  local new=$ARANEA_TEST_SANDBOX/w/app-worktrees/feat-login
  [[ $(git -C "$new" rev-parse HEAD) == "$(git -C "$seed" rev-parse HEAD)" ]]
  [[ $(registry_count) == 2 && $(jq '.projects|length' "$ARANEA_STATE_ROOT/projects.json") == 1 ]]
  [[ $(jq -r '.projects[0].lastCheckoutId' "$ARANEA_STATE_ROOT/projects.json") == "$(jq -r .data.checkoutId "$result")" ]]
  ! git -C "$new" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1
}
task_create_without_remote() {
  setup
  git -C "$repo" remote remove origin
  task_new x
  jq -e '.ok and .data.base == "main"' "$result" >/dev/null
}
task_create_no_default_branch() {
  setup
  git -C "$repo" remote remove origin
  git -C "$repo" branch -m main trunk
  expect_code NO_DEFAULT_BRANCH task-create --branch x
}
task_create_refusals() {
  setup
  expect_code INVALID_BRANCH task-create --branch 'bad name'
  git -C "$repo" branch taken
  expect_code BRANCH_EXISTS task-create --branch taken
  mkdir -p "$ARANEA_TEST_SANDBOX/w/app-worktrees/occupied"
  expect_code PATH_EXISTS task-create --branch occupied
  [[ $(registry_count) == 1 ]]
}
task_create_rejects_hostile_names() {
  setup
  local name folder
  cd "$TMPDIR"
  # shellcheck disable=SC2016
  for name in -x --force 'a..b' '$(touch PWNED)' 'a;b' 'x@{1}'; do
    folder=$ARANEA_TEST_SANDBOX/w/app-worktrees/${name//\//-}
    if git check-ref-format --branch "$name" >/dev/null 2>&1; then
      task_new "$name"
      jq -e '.ok' "$result" >/dev/null
      [[ -d $folder ]]
    else
      expect_code INVALID_BRANCH task-create --branch "$name"
      [[ ! -e $folder ]]
    fi
  done
  [[ ! -e PWNED && ! -e "$ARANEA_TEST_SANDBOX/w/app-worktrees/PWNED" ]]
}
task_create_from_linked_checkout_uses_primary_name() {
  setup
  make_task feat-a
  "$helper" task-create --project "$project_id" --checkout "$task_id" --branch feat-b --json >"$result"
  jq -e '.ok and (.data.path|endswith("/app-worktrees/feat-b"))' "$result" >/dev/null
}
task_remove_clean() {
  setup
  make_task t1
  task_run task-remove --check
  jq -e '.ok and .data.dirty == false and .data.untracked == false and .data.busy == false and .data.unpushed == 0 and .data.missing == false' "$result" >/dev/null
  [[ -d $task_path ]]
  task_run task-remove
  jq -e '.ok and .data.removed == true' "$result" >/dev/null
  [[ ! -e $task_path ]]
  git -C "$repo" show-ref --verify --quiet refs/heads/t1
  [[ $(registry_count) == 1 ]]
  [[ $(jq -r '.projects[0].lastCheckoutId' "$ARANEA_STATE_ROOT/projects.json") == "$checkout_id" ]]
}
task_remove_refusals() {
  setup
  expect_code PRIMARY_CHECKOUT task-remove
  make_task t2
  printf 'x\n' >"$task_path/new.txt"
  task_expect CHECKOUT_DIRTY task-remove
  rm "$task_path/new.txt"
  printf 'x\n' >"$task_path/tracked.txt"
  git -C "$task_path" add tracked.txt
  git -C "$task_path" -c user.name=T -c user.email=t@example.invalid commit -q -m tracked
  printf 'y\n' >"$task_path/tracked.txt"
  task_expect CHECKOUT_DIRTY task-remove
  git -C "$task_path" checkout -q -- tracked.txt
  task_expect UNPUSHED_COMMITS task-remove
  jq -e '.error.message | contains("1 commit")' "$result" >/dev/null
  task_run task-remove --confirm-unpushed
  jq -e '.ok and .data.removed' "$result" >/dev/null
  [[ ! -e $task_path ]]
  [[ $(git -C "$repo" rev-list --count main..t2) == 1 ]]
}
task_remove_busy() {
  setup
  make_task busy
  local definition hash
  jq -cn --arg p "$project_id" '{action:"configure",args:{projectId:$p,definition:{name:"Run",kind:"command",argv:["true"],cwdRelative:".",timeoutSeconds:300,previewUrl:null}}}' | "$action_store" mutate >"$TMPDIR/configured"
  definition=$(jq -r '.state.definitions[0].id' "$TMPDIR/configured")
  hash=$(jq -Sc '.state.definitions[0] | del(.createdAt,.updatedAt)' "$TMPDIR/configured" | sha256sum | cut -d' ' -f1)
  jq -cn --arg p "$project_id" --arg c "$task_id" --arg a "$definition" --arg h "$hash" --arg cwd "$task_path" --argjson rev "$(jq '.state.definitions[0].revision' "$TMPDIR/configured")" '{action:"reserve",args:{projectId:$p,checkoutId:$c,actionId:$a,requestId:"req-00000000-0000-0000-0000-000000000001",cwd:$cwd,definitionRevision:$rev,definitionHash:$h,bootId:"00000000-0000-0000-0000-000000000000"}}' | "$action_store" mutate >"$TMPDIR/reserved"
  jq -e '.ok' "$TMPDIR/reserved" >/dev/null
  task_run task-remove --check
  jq -e '.data.busy == true' "$result" >/dev/null
  task_expect CHECKOUT_BUSY task-remove
  [[ -d $task_path ]]
}
task_remove_missing_folder_unregisters() {
  setup
  make_task gone
  rm -rf "$task_path"
  task_run task-remove
  jq -e '.ok and .data.removed == true and .data.branch == "gone"' "$result" >/dev/null
  if git -C "$repo" worktree list --porcelain | grep -q "worktree $task_path"; then return 1; fi
  [[ $(registry_count) == 1 ]]
  git -C "$repo" show-ref --verify --quiet refs/heads/gone
}
missing_folder_check_changes_nothing() {
  setup
  make_task gone2
  rm -rf "$task_path"
  local registry_before worktrees_before
  registry_before=$(sha256sum "$ARANEA_STATE_ROOT/projects.json")
  worktrees_before=$(git -C "$repo" worktree list --porcelain)
  task_run task-remove --check
  jq -e --arg p "$task_path" '.ok and .data.missing == true and .data.path == $p and .data.branch == "gone2" and .data.dirty == false and .data.untracked == false and .data.busy == false and .data.unpushed == 0' "$result" >/dev/null
  [[ $(sha256sum "$ARANEA_STATE_ROOT/projects.json") == "$registry_before" ]]
  [[ $(git -C "$repo" worktree list --porcelain) == "$worktrees_before" ]]
}
broken_action_store_fails_closed() {
  setup
  make_task closed
  printf 'not json' >"$ARANEA_STATE_ROOT/project-actions.json"
  task_expect ACTIONS_UNAVAILABLE task-remove --check
  task_expect ACTIONS_UNAVAILABLE task-remove
  [[ -d $task_path ]]
  rm -rf "$task_path"
  task_expect ACTIONS_UNAVAILABLE task-remove --check
  task_expect ACTIONS_UNAVAILABLE task-remove
  [[ $(registry_count) == 2 ]]
}
missing_folder_never_prunes_other_worktrees() {
  setup
  make_task ours
  git -C "$repo" worktree add -q -b other "$ARANEA_TEST_SANDBOX/w/other-wt"
  git -C "$repo" worktree add -q -b healthy "$ARANEA_TEST_SANDBOX/w/healthy-wt"
  rm -rf "$task_path" "$ARANEA_TEST_SANDBOX/w/other-wt"
  # Git either removes just this record or refuses; the other stale record must survive.
  task_run task-remove
  if jq -e '.ok' "$result" >/dev/null; then
    [[ $(registry_count) == 1 ]]
  else
    jq -e '.error.code == "GIT_ERROR" and (.error.message | contains("Other stale worktrees"))' "$result" >/dev/null
    [[ $(registry_count) == 2 ]]
  fi
  grep -qx "$ARANEA_TEST_SANDBOX/w/other-wt/.git" "$repo"/.git/worktrees/*/gitdir
  [[ -d $ARANEA_TEST_SANDBOX/w/healthy-wt ]]
}
missing_folder_refuses_when_other_stale_records_exist() {
  setup
  make_task ours
  git -C "$repo" worktree add -q -b other "$ARANEA_TEST_SANDBOX/w/other-wt"
  rm -rf "$task_path" "$ARANEA_TEST_SANDBOX/w/other-wt"
  # Make plain removal refuse, as Git does for a vanished folder in some versions.
  cat >"$TMPDIR/bin/git" <<WRAP
#!/bin/bash
for argument in "\$@"; do
  if [[ \$argument == remove ]]; then echo "fatal: validation failed, cannot remove working tree" >&2; exit 128; fi
done
exec "$(command -v git)" "\$@"
WRAP
  chmod +x "$TMPDIR/bin/git"
  PATH="$TMPDIR/bin:$PATH" task_expect GIT_ERROR task-remove
  jq -e '.error.message | contains("Other stale worktrees exist")' "$result" >/dev/null
  [[ $(registry_count) == 2 ]]
  [[ $(find "$repo/.git/worktrees" -mindepth 1 -maxdepth 1 | wc -l) == 2 ]]
}
missing_folder_prunes_alone_when_removal_refuses() {
  setup
  make_task ours
  git -C "$repo" worktree add -q -b healthy "$ARANEA_TEST_SANDBOX/w/healthy-wt"
  rm -rf "$task_path"
  cat >"$TMPDIR/bin/git" <<WRAP
#!/bin/bash
for argument in "\$@"; do
  if [[ \$argument == remove ]]; then echo "fatal: validation failed, cannot remove working tree" >&2; exit 128; fi
done
exec "$(command -v git)" "\$@"
WRAP
  chmod +x "$TMPDIR/bin/git"
  PATH="$TMPDIR/bin:$PATH" task_run task-remove
  jq -e '.ok and .data.removed' "$result" >/dev/null
  [[ $(registry_count) == 1 ]]
  [[ $(find "$repo/.git/worktrees" -mindepth 1 -maxdepth 1 | wc -l) == 1 ]]
}
missing_folder_prunes_only_its_own_record() {
  setup
  make_task ours
  git -C "$repo" worktree add -q -b healthy "$ARANEA_TEST_SANDBOX/w/healthy-wt"
  rm -rf "$task_path"
  task_run task-remove
  jq -e '.ok and .data.removed' "$result" >/dev/null
  [[ $(find "$repo/.git/worktrees" -mindepth 1 -maxdepth 1 | wc -l) == 1 ]]
  [[ -d $ARANEA_TEST_SANDBOX/w/healthy-wt ]]
}
ignored_files_are_counted_not_blocking() {
  setup
  make_task ign
  printf '.env\n' >"$task_path/.gitignore"
  git -C "$task_path" add .gitignore
  git -C "$task_path" -c user.name=T -c user.email=t@example.invalid commit -q -m ignore
  printf 'S=1\n' >"$task_path/.env"
  task_run task-remove --check
  jq -e '.ok and .data.ignored == 1 and .data.dirty == false and .data.untracked == false' "$result" >/dev/null
  task_run task-remove --confirm-unpushed
  jq -e '.ok and .data.removed' "$result" >/dev/null
}
detached_head_commits_are_never_discarded() {
  setup
  make_task det
  git -C "$task_path" checkout -q --detach
  commit_in "$task_path" lost
  task_expect UNPUSHED_COMMITS task-remove --confirm-unpushed
  jq -e '.error.message | contains("1 commit on a detached HEAD would be lost")' "$result" >/dev/null
  [[ -d $task_path ]]
}
missing_folder_check_counts_unpushed() {
  setup
  make_task cnt
  commit_in "$task_path" one
  rm -rf "$task_path"
  task_run task-remove --check
  jq -e '.ok and .data.missing == true and .data.unpushed == 1 and .data.ignored == 0' "$result" >/dev/null
}
missing_primary_folder_is_still_refused() {
  setup
  mv "$repo" "$repo.moved"
  expect_code CHECKOUT_INVALID task-remove
}
unpushed_without_remote_counts_against_main() {
  setup
  git -C "$repo" remote remove origin
  make_task local
  commit_in "$task_path" one
  commit_in "$task_path" two
  task_run task-remove --check
  jq -e '.ok and .data.unpushed == 2' "$result" >/dev/null
}

cases=(task_create_from_remote_default task_create_without_remote task_create_no_default_branch task_create_refusals task_create_rejects_hostile_names task_create_from_linked_checkout_uses_primary_name task_remove_clean task_remove_refusals task_remove_busy task_remove_missing_folder_unregisters missing_folder_check_changes_nothing missing_primary_folder_is_still_refused broken_action_store_fails_closed missing_folder_never_prunes_other_worktrees missing_folder_refuses_when_other_stale_records_exist missing_folder_prunes_alone_when_removal_refuses missing_folder_prunes_only_its_own_record ignored_files_are_counted_not_blocking detached_head_commits_are_never_discarded missing_folder_check_counts_unpushed unpushed_without_remote_counts_against_main)
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
