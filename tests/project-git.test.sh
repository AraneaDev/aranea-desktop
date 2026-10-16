#!/usr/bin/env bash
# Real repositories and a real bare remote; only ssh and git wrappers are
# doubled, to produce slow or failing network behaviour.
# Cases are invoked by name in the loop below.
# shellcheck disable=SC2329
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
helper="$repo_root/scripts/aranea-project-git"
store="$repo_root/scripts/aranea-project-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
result="$TMPDIR/result.json"
real_git=$(command -v git)
export real_git
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
# A fake ssh that fails or stalls; it sits in $TMPDIR/bin, which cases put first on PATH.
fake_ssh() { printf '#!/bin/sh\n%s\n' "$1" >"$TMPDIR/bin/ssh" && chmod +x "$TMPDIR/bin/ssh"; }

fetch_updates_remote_refs() {
  setup
  local head_before
  head_before=$(git -C "$repo" rev-parse HEAD)
  push_upstream two
  run fetch
  jq -e '.ok and .data.remote == "origin"' "$result" >/dev/null
  [[ $(git -C "$repo" rev-parse origin/main) == "$(git -C "$seed" rev-parse HEAD)" ]]
  [[ $(git -C "$repo" rev-parse HEAD) == "$head_before" ]]
}
pull_fast_forwards() {
  setup
  push_upstream two
  run pull
  jq -e --arg to "$(git -C "$seed" rev-parse HEAD)" '.ok and .data.updated == true and .data.to == $to' "$result" >/dev/null
  run pull
  jq -e '.ok and .data.updated == false and .data.from == .data.to' "$result" >/dev/null
}
pull_refuses_divergence() {
  setup
  git -C "$repo" commit -q --allow-empty -m local
  push_upstream two
  local before
  before=$(git -C "$repo" rev-parse HEAD)
  expect_code NOT_FAST_FORWARD pull
  [[ $(git -C "$repo" rev-parse HEAD) == "$before" ]]
  [[ -z $(git -C "$repo" rev-list --merges HEAD) ]]
}
pull_refuses_overwriting_local_changes() {
  setup
  printf 'a\n' >"$seed/file.txt"
  git -C "$seed" add file.txt
  git -C "$seed" -c user.name=T -c user.email=t@example.invalid commit -q -m a
  git -C "$seed" push -q origin HEAD:main
  run pull
  jq -e '.ok' "$result" >/dev/null
  printf 'b\n' >"$seed/file.txt"
  git -C "$seed" -c user.name=T -c user.email=t@example.invalid commit -q -am b
  git -C "$seed" push -q origin HEAD:main
  printf 'local\n' >"$repo/file.txt"
  expect_code LOCAL_CHANGES pull
  [[ $(<"$repo/file.txt") == local ]]
}
pull_without_upstream() {
  setup
  git -C "$repo" switch -q -c lonely
  expect_code NO_UPSTREAM pull
}
fetch_without_remote() {
  setup
  git -C "$repo" remote remove origin
  expect_code NO_REMOTE fetch
}
fetch_auth_required() {
  setup
  fake_ssh 'echo "Permission denied (publickey)." >&2; exit 255'
  git -C "$repo" remote set-url origin ssh://example.invalid/repo.git
  PATH="$TMPDIR/bin:$PATH" expect_code AUTH_REQUIRED fetch
}
fetch_timeout_releases_lock() {
  setup
  fake_ssh 'sleep 30'
  git -C "$repo" remote set-url origin ssh://example.invalid/repo.git
  local start=$SECONDS
  ARANEA_GIT_NETWORK_SECONDS=2 PATH="$TMPDIR/bin:$PATH" expect_code GIT_TIMEOUT fetch
  ((SECONDS - start <= 6))
  git -C "$repo" remote set-url origin "$remote"
  start=$SECONDS
  run fetch
  jq -e '.ok' "$result" >/dev/null
  ((SECONDS - start <= 5))
}
identity_is_proved() {
  setup
  mv "$repo" "$repo.moved"
  expect_code CHECKOUT_INVALID fetch
}
usage_is_validated() {
  setup
  if "$helper" fetch --json >"$result"; then return 1; fi
  jq -e '.error.code == "INVALID_REQUEST"' "$result" >/dev/null
  if "$helper" bogus --project x --checkout y --json >"$result"; then return 1; fi
  jq -e '.error.code == "INVALID_REQUEST"' "$result" >/dev/null
}
concurrent_operations_serialise() {
  setup
  local log="$TMPDIR/git.log"
  : >"$log"
  cat >"$TMPDIR/bin/git" <<WRAP
#!/bin/bash
for argument in "\$@"; do
  if [[ \$argument == fetch ]]; then
    echo start >>"$log"
    sleep 1
    "$real_git" "\$@"
    status=\$?
    echo end >>"$log"
    exit \$status
  fi
done
exec "$real_git" "\$@"
WRAP
  chmod +x "$TMPDIR/bin/git"
  local first="$TMPDIR/first.json" second="$TMPDIR/second.json" a b
  PATH="$TMPDIR/bin:$PATH" "$helper" fetch --project "$project_id" --checkout "$checkout_id" --json >"$first" &
  a=$!
  PATH="$TMPDIR/bin:$PATH" "$helper" fetch --project "$project_id" --checkout "$checkout_id" --json >"$second" &
  b=$!
  wait "$a"
  wait "$b"
  jq -e '.ok' "$first" >/dev/null
  jq -e '.ok' "$second" >/dev/null
  [[ $(paste -sd, "$log") == start,end,start,end ]]
}
batchmode_reaches_ssh() {
  setup
  fake_ssh "printf '%s\\n' \"\$*\" >\"$TMPDIR/ssh.args\"; echo \"Permission denied (publickey).\" >&2; exit 255"
  git -C "$repo" remote set-url origin ssh://example.invalid/repo.git
  PATH="$TMPDIR/bin:$PATH" expect_code AUTH_REQUIRED fetch
  grep -q -- '-o BatchMode=yes' "$TMPDIR/ssh.args"
}
core_ssh_command_is_honoured() {
  setup
  printf '#!/bin/sh\necho "$*" >"%s"\necho "Permission denied (publickey)." >&2\nexit 255\n' "$TMPDIR/myssh.args" >"$TMPDIR/bin/myssh"
  chmod +x "$TMPDIR/bin/myssh"
  fake_ssh "echo wrong >\"$TMPDIR/wrong\"; exit 255"
  git -C "$repo" config core.sshCommand "$TMPDIR/bin/myssh"
  git -C "$repo" remote set-url origin ssh://example.invalid/repo.git
  PATH="$TMPDIR/bin:$PATH" expect_code AUTH_REQUIRED fetch
  grep -q -- '-o BatchMode=yes' "$TMPDIR/myssh.args"
  [[ ! -e "$TMPDIR/wrong" ]]
}
lock_fd_does_not_reach_git() {
  setup
  local fds="$TMPDIR/git.fds"
  cat >"$TMPDIR/bin/git" <<WRAP
#!/bin/bash
for argument in "\$@"; do
  if [[ \$argument == fetch ]]; then ls -l /proc/\$\$/fd >"$fds" 2>&1; fi
done
exec "$real_git" "\$@"
WRAP
  chmod +x "$TMPDIR/bin/git"
  PATH="$TMPDIR/bin:$PATH" run fetch
  jq -e '.ok' "$result" >/dev/null
  [[ -s $fds ]]
  if grep -q git-locks "$fds"; then return 1; fi
}
inherited_git_context_is_ignored() {
  setup
  GIT_DIR=/nonexistent GIT_WORK_TREE=/nonexistent run fetch
  jq -e '.ok' "$result" >/dev/null
}

cases=(fetch_updates_remote_refs pull_fast_forwards pull_refuses_divergence pull_refuses_overwriting_local_changes pull_without_upstream fetch_without_remote fetch_auth_required fetch_timeout_releases_lock identity_is_proved usage_is_validated concurrent_operations_serialise inherited_git_context_is_ignored batchmode_reaches_ssh core_ssh_command_is_honoured lock_fd_does_not_reach_git)
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
