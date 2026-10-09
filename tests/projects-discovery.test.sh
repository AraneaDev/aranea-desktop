#!/usr/bin/env bash
# Discovery uses disposable repositories and bounded trees; no desktop is reachable.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
discover="$repo_root/scripts/aranea-project-discover"
store="$repo_root/scripts/aranea-project-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
failures=0
# Run isolated assertions with errexit enabled even after a failed case.
run_case() {
  set +e
  (
    set -e
    "$@"
  )
  local status=$?
  set -e
  if ((status == 0)); then printf 'PASS %s\n' "$1"; else
    printf 'FAIL %s\n' "$1"
    failures=$((failures + 1))
  fi
}
# Create a committed real repository for worktree fixtures.
make_repo() {
  git init -q "$1"
  git -C "$1" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m initial
}
# Missing discovery, duplicate groups, symlink traversal, and implicit registration fail here.
related_worktrees_and_explicit_registration() {
  [[ -x "$discover" ]] || {
    echo 'Expected bounded project discovery executable'
    return 1
  }
  local root="$ARANEA_TEST_SANDBOX/dev" main external output
  main="$root/space \$(touch NEVER) ; repo"
  external="$ARANEA_TEST_SANDBOX/external"
  output="$TMPDIR/scan"
  make_repo "$main"
  git -C "$main" worktree add -q "$external" -b external
  make_repo "$root/node_modules/hidden"
  ln -s "$root" "$root/loop"
  ln -s "$external" "$root/linked-symlink"
  "$discover" --root "$root" --root "$main" --json >"$output"
  jq -se --arg main "$main" --arg external "$external" '
    map(select(.event == "candidate")) as $c |
    ($c|length) == 1 and $c[0].candidate.path == $main and
    ($c[0].candidate.checkouts|length) == 2 and
    any($c[0].candidate.checkouts[]; .path == $external and .branch == "external" and (.primary|not)) and
    any($c[0].candidate.checkouts[]; .path == $main and .primary)' "$output"
  jq -se '.[-1] | .event == "completed" and .outcome == "observed" and .errors == [] and .visited == 2' "$output"
  jq -cn --arg p "$external" '{action:"register",args:{paths:[$p]}}' | "$store" mutate >"$TMPDIR/registered"
  jq -e --arg external "$external" '.ok and (.state.projects|length == 1) and .state.projects[0].checkouts == [{id:.state.projects[0].checkouts[0].id,path:$external,branch:"external",primary:false}]' "$TMPDIR/registered"
  [[ ! -e NEVER ]]
}
# An ignored common directory hides the whole related group without writing scan state.
ignored_groups_and_corrupt_state() {
  local root="$ARANEA_TEST_SANDBOX/dev"
  jq -cn --arg p "$ARANEA_TEST_SANDBOX/external" '{action:"ignore",args:{path:$p}}' | "$store" mutate >/dev/null
  cp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/original"
  "$discover" --root "$root" --json >"$TMPDIR/ignored"
  jq -se 'all(.[]; .event != "candidate") and .[-1].outcome == "observed"' "$TMPDIR/ignored"
  cmp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/original"
  printf '{broken' >"$ARANEA_STATE_ROOT/projects.json"
  if "$discover" --root "$root" --json >"$TMPDIR/broken"; then return 1; fi
  jq -se '.[-1].outcome == "partial" and any(.[-1].errors[]; .code == "REGISTRY_INVALID")' "$TMPDIR/broken"
  cp "$TMPDIR/original" "$ARANEA_STATE_ROOT/projects.json"
}
# Multiple JSON objects must not bypass schema validation or alter saved bytes.
multiple_registry_objects_are_rejected() {
  cp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/valid-registry"
  cat "$TMPDIR/valid-registry" "$TMPDIR/valid-registry" >"$ARANEA_STATE_ROOT/projects.json"
  cp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/multiple-registry"
  local status=0
  "$discover" --root "$ARANEA_TEST_SANDBOX/dev" --json >"$TMPDIR/multiple" || status=$?
  cmp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/multiple-registry"
  cp "$TMPDIR/valid-registry" "$ARANEA_STATE_ROOT/projects.json"
  [[ "$status" != 0 ]]
  jq -se '.[-1] | .outcome == "partial" and any(.errors[]; .code == "REGISTRY_INVALID")' "$TMPDIR/multiple"
}
# A stale unselected worktree must not make valid explicit registration fail.
missing_related_checkout_retains_valid_candidates() {
  local root="$ARANEA_TEST_SANDBOX/stale-main" linked="$ARANEA_TEST_SANDBOX/stale-linked"
  make_repo "$root"
  git -C "$root" worktree add -q "$linked" -b stale
  rm -rf "$linked"
  if "$discover" --root "$root" --json >"$TMPDIR/stale"; then return 1; fi
  jq -se --arg p "$root" 'any(.[]; .event == "candidate" and .candidate.path == $p and (.candidate.checkouts|length == 1)) and any(.[-1].errors[]; .code == "CHECKOUT_UNAVAILABLE")' "$TMPDIR/stale"
  jq -cn --arg p "$root" '{action:"register",args:{paths:[$p]}}' | "$store" mutate | jq -e '.ok'
}
# A stale record pointing at a replacement repo must not spoof group membership.
replaced_related_checkout_cannot_join_a_group() {
  local root="$ARANEA_TEST_SANDBOX/replaced-main" linked="$ARANEA_TEST_SANDBOX/replaced-linked"
  make_repo "$root"
  git -C "$root" worktree add -q "$linked" -b replacement
  rm -rf "$linked"
  make_repo "$linked"
  if "$discover" --root "$root" --json >"$TMPDIR/replaced"; then return 1; fi
  jq -se --arg p "$root" 'any(.[]; .event == "candidate" and .candidate.path == $p and (.candidate.checkouts|length == 1)) and any(.[-1].errors[]; .code == "CHECKOUT_UNAVAILABLE")' "$TMPDIR/replaced"
  jq -cn --arg p "$root" '{action:"register",args:{paths:[$p]}}' | "$store" mutate | jq -e '.ok'
}
# .git files for separate git dirs must report primary roots and detached branches.
separate_git_dir_and_read_only_context() {
  local root="$ARANEA_TEST_SANDBOX/separate" external="$ARANEA_TEST_SANDBOX/separate-linked"
  git init -q --separate-git-dir "$ARANEA_TEST_SANDBOX/separate-metadata" "$root"
  git -C "$root" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m initial
  git -C "$root" worktree add -q --detach "$external"
  git -C "$root" config core.fsmonitor "touch '$ARANEA_TEST_SANDBOX/EXECUTED'"
  GIT_DIR=/nonexistent GIT_WORK_TREE=/nonexistent GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.bare GIT_CONFIG_VALUE_0=true "$discover" --root "$root" --json >"$TMPDIR/separate"
  jq -se --arg p "$root" --arg linked "$external" 'any(.[]; .candidate.checkouts? | any(.[]; .path == $p and .primary)) and any(.[]; .candidate.checkouts? | any(.[]; .path == $linked and .branch == null and (.primary|not)))' "$TMPDIR/separate"
  jq -cn --arg p "$root" '{action:"register",args:{paths:[$p]}}' | "$store" mutate | jq -e '.ok and .state.projects[-1].checkouts[0].primary'
  [[ ! -e "$ARANEA_TEST_SANDBOX/EXECUTED" ]]
}
# A linked checkout cannot invent the primary path for separate Git directories.
linked_separate_git_dir_reports_unavailable_primary() {
  local linked="$ARANEA_TEST_SANDBOX/separate-linked"
  if "$discover" --root "$linked" --json >"$TMPDIR/unavailable-primary"; then return 1; fi
  jq -se --arg p "$linked" 'map(select(.event == "candidate")) | length == 1 and .[0].candidate.path == $p and (.[0].candidate.checkouts|length == 1) and .[0].candidate.checkouts[0].path == $p' "$TMPDIR/unavailable-primary"
  jq -se '.[-1] | .outcome == "partial" and any(.errors[]; .code == "PRIMARY_UNAVAILABLE" and (.message|length > 0))' "$TMPDIR/unavailable-primary"
  jq -cn --arg p "$linked" '{action:"register",args:{paths:[$p]}}' | "$store" mutate | jq -e '.ok'
}
# Live activation reads the same identity boundary without a traversal or write.
metadata_adapter_validates_exact_root_read_only() {
  local root="$ARANEA_TEST_SANDBOX/separate"
  cp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/metadata-original"
  "$discover" --metadata "$root" --json >"$TMPDIR/metadata"
  jq -e --arg p "$root" '.ok and .error == null and .metadata.path == $p and (.metadata.checkouts|length == 2) and any(.metadata.checkouts[]; .path == $p and .primary)' "$TMPDIR/metadata"
  mkdir -p "$root/subdirectory"
  if "$discover" --metadata "$root/subdirectory" --json >"$TMPDIR/invalid-metadata"; then return 1; fi
  jq -e '.ok == false and .metadata == null and .error.code == "CHECKOUT_INVALID"' "$TMPDIR/invalid-metadata"
  "$discover" --metadata "$ARANEA_TEST_SANDBOX/separate-linked" --json | jq -e '.ok and any(.metadata.metadataErrors[]; .code == "PRIMARY_UNAVAILABLE")'
  cmp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/metadata-original"
}
# Bare roots, invalid paths, and inaccessible areas produce partial reasons.
unsupported_and_inaccessible_paths() {
  local root="$ARANEA_TEST_SANDBOX/errors"
  mkdir -p "$root/no-access" "$root/control"$'\n'
  git init -q --bare "$root/bare"
  make_repo "$root/bare/objects/embedded"
  git init -q "$root/control"$'\n'
  chmod 000 "$root/no-access"
  if "$discover" --root "$root" --json >"$TMPDIR/errors"; then return 1; fi
  jq -se '.[-1] | .outcome == "partial" and any(.errors[]; .code == "BARE_UNSUPPORTED") and any(.errors[]; .code == "INVALID_PATH")' "$TMPDIR/errors"
  jq -se 'all(.[]; .event != "candidate")' "$TMPDIR/errors"
  if [[ ! -r "$root/no-access" ]]; then jq -se 'any(.[-1].errors[]; .code == "DIRECTORY_UNREADABLE")' "$TMPDIR/errors"; fi
  chmod 700 "$root/no-access"
  if "$discover" --root "$root/missing" --json >"$TMPDIR/missing"; then return 1; fi
  jq -se '.[-1].outcome == "partial" and any(.[-1].errors[]; .code == "ROOT_INVALID")' "$TMPDIR/missing"
}
# Even an explicitly selected .git path must not traverse repository internals.
selected_git_internals_are_not_traversed() {
  local root="$ARANEA_TEST_SANDBOX/internals"
  make_repo "$root"
  make_repo "$root/.git/embedded"
  if "$discover" --root "$root/.git" --json >"$TMPDIR/internals"; then return 1; fi
  jq -se 'all(.[]; .event != "candidate") and (.[-1] | .visited == 0 and .outcome == "partial" and any(.errors[]; .code == "ROOT_INVALID"))' "$TMPDIR/internals"
}
# Unsafe/unresolvable unrelated metadata cannot discard a valid explicit choice.
invalid_unselected_relatives_preserve_selected_identity() {
  local root="$ARANEA_TEST_SANDBOX/relative-errors/main" raw="$ARANEA_TEST_SANDBOX/relative-errors/raw"$'\n' broken="$ARANEA_TEST_SANDBOX/relative-errors/broken"
  make_repo "$root"
  git -C "$root" worktree add -q "$raw" -b unsafe
  git -C "$root" worktree add -q "$broken" -b broken
  git -C "$root" config extensions.worktreeConfig true
  git -C "$broken" config --worktree core.worktree "$ARANEA_TEST_SANDBOX/absent-related-top"
  if "$discover" --root "$root" --json >"$TMPDIR/relative-errors"; then return 1; fi
  jq -se --arg p "$root" --arg raw "$raw" --arg broken "$broken" '
    any(.[]; .candidate.path? == $p and (.candidate.checkouts|length == 1)) and
    (.[-1] | .outcome == "partial" and any(.errors[]; .code == "INVALID_PATH" and .path == $raw) and any(.errors[]; .code == "CHECKOUT_UNAVAILABLE" and .path == $broken))' "$TMPDIR/relative-errors"
  "$discover" --metadata "$root" --json >"$TMPDIR/relative-metadata"
  jq -e --arg p "$root" '.ok and .metadata.path == $p and (.metadata.checkouts|length == 1) and (.metadata.metadataErrors|length == 2)' "$TMPDIR/relative-metadata"
  jq -cn --arg p "$root" '{action:"register",args:{paths:[$p]}}' | "$store" mutate >"$TMPDIR/relative-registered"
  jq -e --arg p "$root" '.ok and any(.state.projects[]; .commonDir == ($p+"/.git") and (.checkouts|length == 1) and .checkouts[0].path == $p)' "$TMPDIR/relative-registered"
  cp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/relative-original"
  for selected in "$raw" "$broken"; do
    if "$discover" --metadata "$selected" --json >"$TMPDIR/invalid-selected"; then return 1; fi
    jq -e '.ok == false and .metadata == null' "$TMPDIR/invalid-selected"
    if jq -cn --arg p "$selected" '{action:"register",args:{paths:[$p]}}' | "$store" mutate >"$TMPDIR/invalid-selected-registry"; then return 1; fi
    jq -e '.ok == false' "$TMPDIR/invalid-selected-registry"
    cmp "$ARANEA_STATE_ROOT/projects.json" "$TMPDIR/relative-original"
  done
}
# Both explicit roots and discovered roots merge proven primary evidence.
separate_primary_evidence_is_independent_of_scan_order() {
  local parent="$ARANEA_TEST_SANDBOX/order" primary linked common order
  primary="$parent/z-primary"
  linked="$parent/a-linked"
  common="$ARANEA_TEST_SANDBOX/order-metadata"
  git init -q --separate-git-dir "$common" "$primary"
  git -C "$primary" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m initial
  git -C "$primary" worktree add -q "$linked" -b ordered
  for order in linked-first primary-first parent; do
    case "$order" in
      linked-first) "$discover" --root "$linked" --root "$primary" --json >"$TMPDIR/$order" ;;
      primary-first) "$discover" --root "$primary" --root "$linked" --json >"$TMPDIR/$order" ;;
      parent) "$discover" --root "$parent" --json >"$TMPDIR/$order" ;;
    esac
    jq -se --arg p "$primary" --arg linked "$linked" '
      map(select(.event == "candidate")) as $c | ($c|length) == 1 and
      $c[0].candidate.path == $p and ($c[0].candidate.checkouts|length == 2) and
      any($c[0].candidate.checkouts[]; .path == $p and .primary) and
      any($c[0].candidate.checkouts[]; .path == $linked and (.primary|not)) and
      (.[-1] | .outcome == "observed" and .errors == [])' "$TMPDIR/$order"
  done
  "$discover" --metadata "$primary" --json | jq -e '.ok and any(.metadata.checkouts[]; .primary)'
  "$discover" --metadata "$linked" --json | jq -e '.ok and any(.metadata.metadataErrors[]; .code == "PRIMARY_UNAVAILABLE")'
  local raw="$ARANEA_TEST_SANDBOX/order-invalid"$'\n'
  git -C "$primary" worktree add -q "$raw" -b order-invalid
  if "$discover" --root "$linked" --root "$primary" --json >"$TMPDIR/resolved-primary-partial"; then return 1; fi
  jq -se --arg p "$primary" --arg raw "$raw" '
    any(.[]; .candidate.path? == $p and (.candidate.checkouts|length == 2)) and
    (.[-1] | .outcome == "partial" and (.errors|length == 1) and .errors[0].code == "INVALID_PATH" and .errors[0].path == $raw)' "$TMPDIR/resolved-primary-partial"
  jq -cn --arg p "$linked" '{action:"register",args:{paths:[$p]}}' | "$store" mutate | jq -e --arg p "$linked" 'any(.state.projects[]; .commonDir == $common and (.checkouts|length == 1) and .checkouts[0].path == $p)' --arg common "$common"
}
# A separate metadata root is never traversed, even though core.bare is false.
separate_git_metadata_internals_are_not_traversed() {
  local parent="$ARANEA_TEST_SANDBOX/metadata-traversal" metadata primary location mode
  metadata="$parent/metadata"
  primary="$parent/main"
  git init -q --separate-git-dir "$metadata" "$primary"
  git -C "$primary" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m initial
  for location in objects/embedded refs/embedded worktrees/embedded; do make_repo "$metadata/$location"; done
  for mode in direct parent; do
    if [[ "$mode" == direct ]]; then location=$metadata; else location=$parent; fi
    if "$discover" --root "$location" --json >"$TMPDIR/metadata-$mode"; then return 1; fi
    jq -se --arg metadata "$metadata" 'all(.[]; ((.candidate.path? // "") | startswith($metadata+"/")) | not) and any(.[-1].errors[]; .code == "GIT_METADATA_UNSUPPORTED" and .path == $metadata)' "$TMPDIR/metadata-$mode"
  done
  jq -se '.[-1].visited == 1 and all(.[]; .event != "candidate")' "$TMPDIR/metadata-direct"
  jq -se --arg p "$primary" 'any(.[]; .candidate.path? == $p) and .[-1].visited == 3' "$TMPDIR/metadata-parent"
  if "$discover" --metadata "$metadata" --json >"$TMPDIR/metadata-root"; then return 1; fi
  jq -e '.ok == false and .error.code == "CHECKOUT_INVALID"' "$TMPDIR/metadata-root"
}
# Depth clipping preserves depth-eight results while excluding depth-nine repos.
depth_limit_keeps_partial_candidates() {
  local root="$ARANEA_TEST_SANDBOX/depth" current="$ARANEA_TEST_SANDBOX/depth" i
  mkdir -p "$root"
  for ((i = 1; i <= 8; i++)); do
    current+="/d"
    mkdir "$current"
  done
  make_repo "$current"
  make_repo "$current/ninth"
  if "$discover" --root "$root" --json >"$TMPDIR/depth"; then return 1; fi
  jq -se --arg p "$current" 'map(select(.event == "candidate")) | length == 1 and .[0].candidate.path == $p' "$TMPDIR/depth"
  jq -se '.[-1] | .visited == 9 and .outcome == "partial" and any(.errors[]; .code == "DEPTH_LIMIT")' "$TMPDIR/depth"
}
# Removing the directory ceiling would scan and report the final repository.
count_limit_is_bounded() {
  local root="$ARANEA_TEST_SANDBOX/count" i
  mkdir -p "$root"
  local -a folders=()
  for ((i = 0; i < 20000; i++)); do
    printf -v name '%05d' "$i"
    folders+=("$root/$name")
  done
  mkdir -- "${folders[@]}"
  make_repo "$root/19999"
  if "$discover" --root "$root" --json >"$TMPDIR/count"; then return 1; fi
  jq -se '.[-1] | .visited == 20000 and .outcome == "partial" and any(.errors[]; .code == "DIRECTORY_LIMIT")' "$TMPDIR/count"
  jq -se 'all(.[]; .event != "candidate")' "$TMPDIR/count"
}
# Termination must stop a deliberately slow real Git query and its descendants.
cancellation_stops_git_children() {
  local root="$ARANEA_TEST_SANDBOX/cancel" real_git pid child status=0 i
  make_repo "$root"
  real_git=$(command -v git)
  mkdir -p "$TMPDIR/slow-bin"
  cat >"$TMPDIR/slow-bin/git" <<'SLOW'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$ARANEA_TEST_SANDBOX/git-child"
sleep 30 &
printf '%s\n' "$!" >"$ARANEA_TEST_SANDBOX/git-grandchild"
wait
exec "$REAL_GIT" "$@"
SLOW
  chmod +x "$TMPDIR/slow-bin/git"
  REAL_GIT="$real_git" PATH="$TMPDIR/slow-bin:$PATH" "$discover" --root "$root" --json >"$TMPDIR/cancel" &
  pid=$!
  for ((i = 0; i < 100; i++)); do
    [[ -s "$ARANEA_TEST_SANDBOX/git-grandchild" ]] && break
    sleep 0.02
  done
  [[ -s "$ARANEA_TEST_SANDBOX/git-grandchild" ]] || {
    kill "$pid"
    wait "$pid" || true
    return 1
  }
  kill -TERM "$pid"
  wait "$pid" || status=$?
  [[ "$status" != 0 ]]
  jq -se '.[-1] | .event == "completed" and .outcome == "partial" and any(.errors[]; .code == "CANCELLED")' "$TMPDIR/cancel"
  for child in "$(cat "$ARANEA_TEST_SANDBOX/git-child")" "$(cat "$ARANEA_TEST_SANDBOX/git-grandchild")"; do
    if kill -0 "$child" 2>/dev/null; then [[ "$(ps -o stat= -p "$child")" == Z* ]]; fi
  done
}
for case_name in related_worktrees_and_explicit_registration ignored_groups_and_corrupt_state multiple_registry_objects_are_rejected missing_related_checkout_retains_valid_candidates replaced_related_checkout_cannot_join_a_group separate_git_dir_and_read_only_context linked_separate_git_dir_reports_unavailable_primary metadata_adapter_validates_exact_root_read_only unsupported_and_inaccessible_paths selected_git_internals_are_not_traversed invalid_unselected_relatives_preserve_selected_identity separate_primary_evidence_is_independent_of_scan_order separate_git_metadata_internals_are_not_traversed depth_limit_keeps_partial_candidates count_limit_is_bounded cancellation_stops_git_children; do run_case "$case_name"; done
((failures == 0))
