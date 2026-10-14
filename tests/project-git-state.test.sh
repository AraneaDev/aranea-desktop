#!/usr/bin/env bash
# Real repositories catch identity substitution, lossy parsing, mutations, and
# misleading counts. Git doubles only supply otherwise slow/oversized failures.
# Cases are invoked by name in the loop below.
# shellcheck disable=SC2329
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
helper="$repo_root/scripts/aranea-project-git-state"
store="$repo_root/scripts/aranea-project-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
registry="$ARANEA_STATE_ROOT/projects.json"
result="$TMPDIR/result.json"
real_git=$(command -v git)
export real_git
failures=0
# Create an independent registered checkout for every case.
setup() {
  rm -rf "$ARANEA_STATE_ROOT"
  repo="$ARANEA_TEST_SANDBOX/$1"
  git init -q -b main "$repo"
  git -C "$repo" config user.name Tests
  git -C "$repo" config user.email tests@example.invalid
  printf 'initial\n' >"$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -qm initial
  jq -cn --arg path "$repo" '{action:"register",args:{paths:[$path]}}' | "$store" mutate >"$result"
  project_id=$(jq -r '.state.projects[0].id' "$result")
  checkout_id=$(jq -r '.state.projects[0].checkouts[0].id' "$result")
}
# Use the public selected-identity interface, never a raw path interface.
observe() { "$helper" --project "$project_id" --checkout "$checkout_id" --json >"$result"; }
# Require one actionable JSON failure, with no partial state.
expect_error() {
  if observe 2>"$TMPDIR/error-stderr"; then
    echo "Expected $1 error"
    return 1
  fi
  jq -e --arg code "$1" '(.ok == false) and .data == null and .error.code == $code and (.error.recovery|length > 0)' "$result" >/dev/null
  [[ $(jq -s length "$result") == 1 && ! -s "$TMPDIR/error-stderr" ]]
}
# Catch omitted overlap counts or an unexpected repository/state write.
clean_and_mixed_are_read_only() {
  setup clean
  find "$repo" "$ARANEA_STATE_ROOT" -type f -exec sha256sum {} + | sort >"$TMPDIR/before"
  observe
  jq -e '.ok and .error == null and .data.branch == "main" and .data.detached == false and .data.upstream == null and .data.ahead == null and .data.behind == null and .data.counts == {staged:0,unstaged:0,untracked:0,conflicts:0} and .data.files == [] and .data.truncated == false and (.data.observedAt|type == "number")' "$result" >/dev/null
  find "$repo" "$ARANEA_STATE_ROOT" -type f -exec sha256sum {} + | sort >"$TMPDIR/after"
  cmp "$TMPDIR/before" "$TMPDIR/after"
  printf 'one\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  printf 'two\n' >>"$repo/file.txt"
  mkdir "$repo/new"
  printf x >"$repo/new/a"
  printf y >"$repo/new/b"
  observe
  jq -e '.data.counts == {staged:1,unstaged:1,untracked:2,conflicts:0} and any(.data.files[]; .path == "file.txt" and .indexStatus == "M" and .worktreeStatus == "M" and .originalPath == null and .conflict == false)' "$result" >/dev/null
}
# Catch line/whitespace splitting and swapped rename source/destination records.
rename_and_unusual_filenames() {
  setup filenames
  original=$'original \t\n name\n'
  renamed=$'renamed \r\n name\n'
  printf x >"$repo/$original"
  git -C "$repo" add .
  git -C "$repo" commit -qm filenames
  git -C "$repo" mv "$original" "$renamed"
  unusual=$'untracked \t\n $(touch NEVER) \"\n'
  printf y >"$repo/$unusual"
  observe
  jq -e --arg source "$original" --arg destination "$renamed" --arg unusual "$unusual" '.data.counts.staged == 1 and .data.counts.untracked == 1 and any(.data.files[]; .path == $destination and .originalPath == $source and .indexStatus == "R") and any(.data.files[]; .path == $unusual and .indexStatus == "?" and .worktreeStatus == "?")' "$result" >/dev/null
  [[ ! -e NEVER ]]
}
# Catch jq silently replacing an unrepresentable filename or rename source.
invalid_utf8_is_rejected() {
  setup invalid-utf8
  invalid=$'invalid-\xff'
  printf x >"$repo/$invalid"
  expect_error GIT_ERROR
  git -C "$repo" add .
  git -C "$repo" commit -qm invalid-name
  git -C "$repo" mv "$invalid" valid-name
  expect_error GIT_ERROR
}
# Catch ignored unmerged records or treating detached/unborn branches as main.
conflict_detached_and_unborn() {
  setup conflicts
  git -C "$repo" checkout -qb side
  printf side >"$repo/file.txt"
  git -C "$repo" commit -qam side
  git -C "$repo" checkout -q main
  printf main >"$repo/file.txt"
  git -C "$repo" commit -qam main
  if git -C "$repo" merge side >/dev/null 2>&1; then return 1; fi
  observe
  jq -e '.data.counts.conflicts == 1 and any(.data.files[]; .path == "file.txt" and .conflict and .indexStatus == "U" and .worktreeStatus == "U")' "$result" >/dev/null
  git -C "$repo" merge --abort
  git -C "$repo" checkout -q --detach
  observe
  jq -e '.data.detached and .data.branch == null and .data.upstream == null and .data.ahead == null' "$result" >/dev/null
  rm -rf "$ARANEA_STATE_ROOT"
  repo="$ARANEA_TEST_SANDBOX/unborn"
  git init -q -b fresh "$repo"
  jq -cn --arg path "$repo" '{action:"register",args:{paths:[$path]}}' | "$store" mutate >"$result"
  project_id=$(jq -r '.state.projects[0].id' "$result")
  checkout_id=$(jq -r '.state.projects[0].checkouts[0].id' "$result")
  observe
  jq -e '.data.branch == "fresh" and .data.detached == false and .data.ahead == null and .data.behind == null' "$result" >/dev/null
}
# Catch manufacturing zero divergence for absent or unresolved upstream refs.
local_upstream_divergence() {
  setup upstream
  git -C "$repo" branch base
  git -C "$repo" branch --set-upstream-to=base >/dev/null
  git -C "$repo" commit -q --allow-empty -m ahead
  git -C "$repo" checkout -q base
  git -C "$repo" commit -q --allow-empty -m behind
  git -C "$repo" checkout -q main
  observe
  jq -e '.data.upstream == "base" and .data.ahead == 1 and .data.behind == 1' "$result" >/dev/null
  git -C "$repo" branch -D base >/dev/null
  observe
  jq -e '.data.ahead == null and .data.behind == null' "$result" >/dev/null
}
# Catch repository-config command execution or inherited context substitution.
fsmonitor_and_inherited_context_are_inert() {
  setup inert
  printf '#!/usr/bin/env bash\ntouch "%s"\n' "$TMPDIR/fsmonitor-ran" >"$TMPDIR/monitor"
  chmod +x "$TMPDIR/monitor"
  git -C "$repo" config core.fsmonitor "$TMPDIR/monitor"
  git -C "$repo" config core.hooksPath "$TMPDIR"
  git init -q "$ARANEA_TEST_SANDBOX/foreign"
  GIT_DIR="$ARANEA_TEST_SANDBOX/foreign/.git" GIT_WORK_TREE="$ARANEA_TEST_SANDBOX/foreign" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0="$TMPDIR/monitor" observe
  jq -e --arg path "$repo" '.ok and .data.path == $path and .data.branch == "main"' "$result" >/dev/null
  [[ ! -e "$TMPDIR/fsmonitor-ran" ]]
}
# Catch fallback to another checkout, missing identity checks, or registry writes.
identity_and_registry_refusals() {
  setup identity
  checkout_id=c-missing
  expect_error CHECKOUT_INVALID
  checkout_id=$(jq -r '.projects[0].checkouts[0].id' "$registry")
  mv "$repo" "$repo-moved"
  expect_error CHECKOUT_INVALID
  mkdir -p "$repo"
  expect_error CHECKOUT_INVALID
  git init -q --separate-git-dir="$TMPDIR/replacement-git" "$repo"
  expect_error CHECKOUT_INVALID
  rm -rf "$repo"
  mv "$repo-moved" "$repo"
  cp "$registry" "$TMPDIR/registry-before"
  printf '{broken' >"$registry"
  expect_error REGISTRY_INVALID
  [[ $(cat "$registry") == '{broken' ]]
  rm -rf "$ARANEA_STATE_ROOT"
  expect_error REGISTRY_INVALID
  [[ ! -e "$ARANEA_STATE_ROOT" ]]
}
# Catch reading a checkout under another project ID or falling back from a
# vanished registered worktree to its surviving primary checkout.
linked_checkout_identity() {
  setup linked-main
  linked="$ARANEA_TEST_SANDBOX/linked-worktree"
  git -C "$repo" worktree add -qb linked "$linked"
  jq -cn --arg path "$linked" '{action:"register",args:{paths:[$path]}}' | "$store" mutate >"$result"
  checkout_id=$(jq -r --arg path "$linked" '.state.projects[].checkouts[]|select(.path == $path)|.id' "$result")
  printf changed >"$linked/file.txt"
  observe
  jq -e --arg path "$linked" '.ok and .data.path == $path and .data.branch == "linked" and .data.counts.unstaged == 1' "$result" >/dev/null
  foreign="$ARANEA_TEST_SANDBOX/registered-foreign"
  git init -q "$foreign"
  jq -cn --arg path "$foreign" '{action:"register",args:{paths:[$path]}}' | "$store" mutate >"$result"
  original_project=$project_id
  project_id=$(jq -r --arg path "$foreign" '.state.projects[]|select(any(.checkouts[]; .path == $path))|.id' "$result")
  expect_error CHECKOUT_INVALID
  project_id=$original_project
  rm -rf "$linked"
  expect_error CHECKOUT_INVALID
}
# Catch capping counts together with details or directory-summary counting.
detail_cap_retains_complete_counts() {
  setup cap
  mkdir "$repo/new"
  for ((i = 0; i < 510; i++)); do printf x >"$repo/new/$i"; done
  observe
  jq -e '.data.counts.untracked == 510 and (.data.files|length) == 500 and .data.truncated' "$result" >/dev/null
}
# Catch bounding only status, parsing an oversized/partial stream, or Git errors
# misclassified as successful observations. Real Git handles ordinary calls.
bounded_failures() {
  setup bounded
  mkdir "$TMPDIR/git-bin"
  cat >"$TMPDIR/git-bin/git" <<'GIT'
#!/usr/bin/env bash
case "$TEST_GIT_MODE" in
  slow-identity) sleep 12 ;;
  oversized-identity) head -c 2097153 /dev/zero; exit 0 ;;
esac
for arg in "$@"; do
  [[ "$arg" == status ]] || continue
  case "$TEST_GIT_MODE" in
    oversized) head -c 2097153 /dev/zero; exit 0 ;;
    oversized-slow) head -c 2097153 /dev/zero; sleep 12; exit 0 ;;
    empty) exit 0 ;;
    incomplete) printf '? incomplete'; exit 0 ;;
    git-error) exit 3 ;;
  esac
done
exec "$real_git" "$@"
GIT
  chmod +x "$TMPDIR/git-bin/git"
  for mode in oversized oversized-slow oversized-identity incomplete empty git-error slow-identity; do
    case "$mode" in
      oversized*) code=GIT_OUTPUT_LIMIT ;;
      slow-identity) code=GIT_TIMEOUT ;;
      *) code=GIT_ERROR ;;
    esac
    start=$SECONDS
    PATH="$TMPDIR/git-bin:$PATH" TEST_GIT_MODE="$mode" expect_error "$code"
    ((SECONDS - start < 11))
    if [[ "$mode" == oversized-slow ]]; then ((SECONDS - start < 3)); fi
  done
}
# Catch missing dependencies escaping as non-JSON shell errors.
missing_dependency() {
  setup dependencies
  mkdir "$TMPDIR/without-git"
  for dependency in bash jq realpath dirname mktemp rm timeout head wc date; do
    ln -s "$(command -v "$dependency")" "$TMPDIR/without-git/$dependency"
  done
  PATH="$TMPDIR/without-git" expect_error DEPENDENCY_MISSING
}
cases=(clean_and_mixed_are_read_only rename_and_unusual_filenames invalid_utf8_is_rejected conflict_detached_and_unborn local_upstream_divergence fsmonitor_and_inherited_context_are_inert identity_and_registry_refusals linked_checkout_identity detail_cap_retains_complete_counts bounded_failures missing_dependency)
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
