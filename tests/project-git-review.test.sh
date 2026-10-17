#!/usr/bin/env bash
# Review and push of a task checkout against real repositories and a real bare remote.
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
# Commit on the seed clone and push it to the remote, as another person would.
push_upstream() { git -C "$seed" -c user.name=T -c user.email=t@example.invalid commit -q --allow-empty -m "$1" && git -C "$seed" push -q origin HEAD:main; }
# Run the Git helper operation on the primary checkout and save its envelope.
run() { "$helper" "$1" --project "$project_id" --checkout "$checkout_id" "${@:2}" --json >"$result"; }
# Assert the helper fails with this error code, no data and a recovery hint.
expect_code() { ! run "${@:2}" && jq -e --arg c "$1" '.ok == false and .data == null and .error.code == $c and (.error.recovery|length > 0)' "$result" >/dev/null; }
# Run task-create on the primary checkout for the branch and save the envelope.
task_new() { "$helper" task-create --project "$project_id" --checkout "$checkout_id" --branch "$1" --json >"$result"; }
# Checkout id registered for this path.
linked_id() { jq -r --arg p "$1" '.projects[0].checkouts[]|select(.path == $p)|.id' "$ARANEA_STATE_ROOT/projects.json"; }
# Number of checkouts registered for the project.
registry_count() { jq '.projects[0].checkouts|length' "$ARANEA_STATE_ROOT/projects.json"; }
# Create a task checkout and leave its id in $task_id and path in $task_path.
make_task() {
  task_new "$1"
  jq -e '.ok' "$result" >/dev/null
  task_id=$(jq -r .data.checkoutId "$result")
  task_path=$(jq -r .data.path "$result")
}
# Run the Git helper operation on the task checkout and save its envelope.
task_run() { "$helper" "$1" --project "$project_id" --checkout "$task_id" "${@:2}" --json >"$result"; }
# Assert the helper fails on the task checkout with this error code and a recovery hint.
task_expect() { ! task_run "${@:2}" && jq -e --arg c "$1" '.ok == false and .data == null and .error.code == $c and (.error.recovery|length > 0)' "$result" >/dev/null; }
# Add an empty commit in the given checkout.
commit_in() { git -C "$1" -c user.name=T -c user.email=t@example.invalid commit -q --allow-empty -m "$2"; }

# Commit one file with the given content in a checkout.
commit_file() { printf '%b' "$3" >"$1/$2" && git -C "$1" add -- "$2" && git -C "$1" -c user.name=T -c user.email=t@example.invalid commit -q -m "${4:-add $2}"; }
# A fake ssh that fails; it sits in $TMPDIR/bin, which cases put first on PATH.
fake_ssh() { printf '#!/bin/sh\n%s\n' "$1" >"$TMPDIR/bin/ssh" && chmod +x "$TMPDIR/bin/ssh"; }

# Catch wrong base, counts, ordering, binary handling or uncommitted state in a review.
review_reports_changes() {
  setup
  make_task feat/r
  commit_file "$task_path" a.txt 'one\ntwo\nthree\n' 'add a'
  commit_file "$task_path" b.bin '\0\1' 'add b'
  : >"$task_path/untracked.txt"
  task_run review
  jq -e '.ok and .data.base == "origin/main" and .data.ahead == 2 and .data.behind == 0 and .data.branch == "feat/r"' "$result" >/dev/null
  jq -e '(.data.commits|length) == 2 and .data.commits[0].subject == "add b" and .data.commits[1].subject == "add a"' "$result" >/dev/null
  jq -e '(.data.files|map(select(.path == "a.txt"))[0]) == {path:"a.txt",added:3,removed:0}' "$result" >/dev/null
  jq -e '(.data.files|map(select(.path == "b.bin"))[0]) == {path:"b.bin",added:null,removed:null}' "$result" >/dev/null
  jq -e '.data.uncommitted == {dirty:false,untracked:true} and .data.truncated == false' "$result" >/dev/null
  jq -e '(.data.head|test("^[0-9a-f]{40}$")) and (.data.mergeBase|test("^[0-9a-f]{40}$")) and .data.head == .data.commits[0].sha' "$result" >/dev/null
}
# Catch a review being produced for the primary checkout.
review_refuses_primary() {
  setup
  expect_code PRIMARY_CHECKOUT review
}
# Catch a review guessing a base when there is no default branch.
review_no_default_branch() {
  setup
  make_task x
  git -C "$repo" remote remove origin
  git -C "$repo" branch -m main trunk
  task_expect NO_DEFAULT_BRANCH review
}
# Catch missing or wrong caps on commits and files.
review_caps() {
  setup
  make_task cap
  local i
  for i in $(seq 1 55); do commit_in "$task_path" "c$i"; done
  task_run review
  jq -e '(.data.commits|length) == 50 and .data.truncated == true and .data.ahead == 55 and .data.commits[0].subject == "c55"' "$result" >/dev/null
  git -C "$task_path" reset -q --hard origin/main
  for i in $(seq 1 205); do : >"$task_path/f$i"; done
  git -C "$task_path" add -A
  git -C "$task_path" -c user.name=T -c user.email=t@example.invalid commit -q -m many
  task_run review
  jq -e '(.data.files|length) == 200 and .data.truncated == true' "$result" >/dev/null
}
# Catch subjects or file names being run or altered.
review_hostile_names_inert() {
  setup
  make_task h
  cd "$TMPDIR"
  # shellcheck disable=SC2016
  commit_file "$task_path" 'x;rm -rf ~' hi '$(touch PWNED)'
  task_run review
  # shellcheck disable=SC2016
  jq -e '.data.commits[0].subject == "$(touch PWNED)" and (.data.files|map(.path)|index("x;rm -rf ~")) != null' "$result" >/dev/null
  [[ ! -e PWNED && ! -e "$task_path/PWNED" ]]
}
# Catch a rebased branch showing the base's commits as its own.
rebased_branch_reviews_cleanly() {
  setup
  make_task reb
  commit_in "$task_path" mine1
  commit_in "$task_path" mine2
  push_upstream up1
  push_upstream up2
  git -C "$task_path" fetch -q origin
  git -C "$task_path" -c user.name=T -c user.email=t@example.invalid rebase -q origin/main
  task_run review
  jq -e '.data.ahead == 2 and .data.behind == 0 and (.data.commits|map(.subject)) == ["mine2","mine1"]' "$result" >/dev/null
}
# Catch a push that does not publish the branch or set its upstream.
push_sets_upstream() {
  setup
  make_task feat/p
  commit_in "$task_path" work
  task_run push
  jq -e '.ok and .data.upstream == "origin/feat/p" and .data.remote == "origin" and .data.branch == "feat/p" and .data.pushed == true' "$result" >/dev/null
  git -C "$remote" rev-parse --verify -q refs/heads/feat/p >/dev/null
  [[ $(git -C "$task_path" rev-parse --abbrev-ref '@{upstream}') == origin/feat/p ]]
}
# Catch a rejected push being forced or reported with another code.
push_rejected() {
  setup
  make_task rej
  commit_in "$task_path" one
  task_run push
  local other=$ARANEA_TEST_SANDBOX/w/other
  git clone -q "$remote" "$other"
  git -C "$other" checkout -q rej
  commit_in "$other" theirs
  git -C "$other" push -q origin rej
  commit_in "$task_path" two
  task_expect PUSH_REJECTED push
  jq -e '.error.message == "The remote has newer commits; fetch and update first."' "$result" >/dev/null
}
# Catch a push from a detached HEAD.
push_detached() {
  setup
  make_task det
  git -C "$task_path" switch -q --detach
  task_expect NO_BRANCH push
}
# Catch missing credentials not reported as AUTH_REQUIRED.
push_auth_required() {
  setup
  make_task auth
  commit_in "$task_path" work
  fake_ssh 'echo "Permission denied (publickey)." >&2; exit 255'
  git -C "$repo" remote set-url origin ssh://example.invalid/repo.git
  PATH="$TMPDIR/bin:$PATH" task_expect AUTH_REQUIRED push
}
# Catch any force flag or forced refspec reaching Git.
push_never_forces() {
  setup
  make_task nf
  commit_in "$task_path" work
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/git.log"\nexec %s "$@"\n' "$TMPDIR" "$(command -v git)" >"$TMPDIR/bin/git"
  chmod +x "$TMPDIR/bin/git"
  PATH="$TMPDIR/bin:$PATH" task_run push
  jq -e '.ok' "$result" >/dev/null
  grep -q ' push ' "$TMPDIR/git.log"
  if grep -qE -- '--force|(^| )-f( |$)|\+refs' "$TMPDIR/git.log"; then exit 1; fi
  grep ' push ' "$TMPDIR/git.log" | grep -q -- '--no-follow-tags --recurse-submodules=no'
}
# Catch a server-side refusal being reported as the remote being ahead.
push_hook_decline_is_not_rejected() {
  setup
  make_task hook
  commit_in "$task_path" work
  printf '#!/bin/sh\necho "remote: policy says no" >&2\nexit 1\n' >"$remote/hooks/pre-receive"
  chmod +x "$remote/hooks/pre-receive"
  task_expect GIT_ERROR push
  jq -e '.error.message | contains("pre-receive hook declined")' "$result" >/dev/null
}
# Catch a tag named like the branch changing the branch name or breaking the push.
tag_named_like_branch() {
  setup
  make_task foo
  commit_in "$task_path" work
  git -C "$task_path" tag foo
  task_run review
  jq -e '.data.branch == "foo"' "$result" >/dev/null
  task_run push
  jq -e '.ok and .data.branch == "foo" and .data.upstream == "origin/foo"' "$result" >/dev/null
}

# Catch a review fetching a missing blob on demand: a planted uploadpack command must never run.
review_never_lazy_fetches() {
  rm -rf "$ARANEA_STATE_ROOT" "$ARANEA_TEST_SANDBOX/w"
  mkdir -p "$ARANEA_TEST_SANDBOX/w"
  local remote="$ARANEA_TEST_SANDBOX/w/remote.git" seed="$ARANEA_TEST_SANDBOX/w/seed" primary="$ARANEA_TEST_SANDBOX/w/pc" linked="$ARANEA_TEST_SANDBOX/w/pc-linked"
  local marker="$ARANEA_TEST_SANDBOX/w/uploadpack-ran" blob base
  git init -q --bare -b main "$remote"
  git -C "$remote" config uploadpack.allowFilter true
  git -C "$remote" config uploadpack.allowAnySHA1InWant true
  git clone -q "$remote" "$seed" 2>/dev/null
  commit_file "$seed" f 'old\n' 'add f'
  git -C "$seed" push -q origin HEAD:main
  git clone -q --no-checkout --filter=blob:none "file://$remote" "$primary" 2>/dev/null
  git -C "$primary" worktree add -q --no-checkout -b feat "$linked"
  blob=$(printf 'new\n' | git -C "$linked" hash-object -w --stdin)
  git -C "$linked" read-tree HEAD
  git -C "$linked" update-index --cacheinfo "100644,$blob,f"
  git -C "$linked" -c user.name=T -c user.email=t@example.invalid commit -q -m 'change f'
  base=$(git -C "$linked" rev-parse HEAD~1)
  git -C "$primary" config remote.origin.uploadpack "/usr/bin/touch $marker; git-upload-pack"
  jq -cn --arg a "$primary" --arg b "$linked" '{action:"register",args:{paths:[$a,$b]}}' | "$store" mutate >"$result"
  project_id=$(jq -r '.state.projects[0].id' "$result")
  task_id=$(jq -r '.state.projects[0].checkouts[]|select(.primary|not)|.id' "$result")
  task_run review || true
  [[ ! -f "$marker" ]] || {
    echo "review ran the planted uploadpack"
    return 1
  }
  # git refuses the missing blob; the helper reports that as a plain error, never a crash.
  jq -e '.ok == false and .data == null and .error.code == "GIT_ERROR" and (.error.recovery|length > 0)' "$result" >/dev/null
  # Control: without the guard the same read fetches the missing blob and runs the planted command.
  git -C "$linked" diff --numstat "$base...HEAD" >/dev/null 2>&1 || true
  [[ -f "$marker" ]] || {
    echo "Control failed: the planted uploadpack should run on a lazy fetch"
    return 1
  }
  rm -f "$marker"
}
# Catch a read-only review queueing behind a held repository lock, and a fetch skipping the lock.
review_ignores_repository_lock() {
  setup
  make_task locked
  local key start
  key=$(printf '%s' "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)" | sha256sum | cut -c1-32)
  mkdir -p "$ARANEA_STATE_ROOT/git-locks"
  flock "$ARANEA_STATE_ROOT/git-locks/$key.lock" sleep 12 &
  local holder=$!
  sleep 0.5
  start=$SECONDS
  ARANEA_GIT_LOCK_SECONDS=2 timeout 8 "$helper" review --project "$project_id" --checkout "$task_id" --json >"$result" || true
  ((SECONDS - start <= 4)) || {
    echo "review waited for the lock"
    kill "$holder" 2>/dev/null || true
    return 1
  }
  jq -e '.ok and .data.checkoutId != null' "$result" >/dev/null
  start=$SECONDS
  ARANEA_GIT_LOCK_SECONDS=2 timeout 8 "$helper" fetch --project "$project_id" --checkout "$task_id" --json >"$result" || true
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  jq -e '.ok == false and .error.code == "GIT_BUSY"' "$result" >/dev/null
  ((SECONDS - start >= 2 && SECONDS - start <= 6))
}
cases=(review_ignores_repository_lock review_reports_changes review_refuses_primary review_no_default_branch review_caps review_hostile_names_inert rebased_branch_reviews_cleanly review_never_lazy_fetches push_sets_upstream push_rejected push_detached push_auth_required push_never_forces push_hook_decline_is_not_rejected tag_named_like_branch)
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
