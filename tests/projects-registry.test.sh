#!/usr/bin/env bash
# Real registry transactions: omitting a write, lock, validation, or identity
# preservation must fail these assertions. All repositories are disposable.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
store="$repo_root/scripts/aranea-project-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
registry="$ARANEA_STATE_ROOT/projects.json"
mkdir -p "$ARANEA_TEST_SANDBOX/dev" "$ARANEA_TEST_SANDBOX/other"
for path in "$ARANEA_TEST_SANDBOX/dev" "$ARANEA_TEST_SANDBOX/other"; do
  git init -q "$path"
done
# Submit one JSON mutation to the actual sandboxed store.
mutate() { jq -cn --arg action "$1" --argjson args "$2" '{action:$action,args:$args}' | "$store" mutate; }
failures=0
# Reset registry state and run a case with effective errexit isolation.
run_case() {
  rm -rf "$ARANEA_STATE_ROOT"
  set +e
  (
    set -e
    "$@"
  )
  case_status=$?
  set -e
  if ((case_status == 0)); then printf 'PASS %s\n' "$1"; else
    printf 'FAIL %s\n' "$1"
    failures=$((failures + 1))
  fi
}
# Catch missing initialization or a changed initial snapshot contract.
snapshot_initializes_only_absent() {
  [[ -x "$store" ]] || {
    echo 'Registry store is not implemented'
    return 1
  }
  "$store" snapshot | jq -e '.ok and .error == null and .state == {schemaVersion:1,revision:0,roots:[],ignored:[],projects:[]}'
  [[ -f "$registry" ]]
}
# Catch lost root mutations, missing revision guards, and canonical duplicates.
roots_conflicts_and_concurrency() {
  jq -cn --arg path "$ARANEA_TEST_SANDBOX/dev" '{action:"root-add",args:{path:$path},expectedRevision:0}' | "$store" mutate | jq -e '.ok and .state.revision == 1'
  if jq -cn --arg path "$ARANEA_TEST_SANDBOX/other" '{action:"root-add",args:{path:$path},expectedRevision:0}' | "$store" mutate >"$TMPDIR/conflict"; then return 1; fi
  jq -e '.error.code == "REGISTRY_CONFLICT" and .state.revision == 1' "$TMPDIR/conflict"
  mutate root-add "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev/." '{path:$p}')" | jq -e '.state.roots|length == 1'
  rm -rf "$ARANEA_STATE_ROOT"
  mutate root-add "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{path:$p}')" >"$TMPDIR/one" &
  pid_one=$!
  mutate root-add "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/other" '{path:$p}')" >"$TMPDIR/two" &
  pid_two=$!
  wait "$pid_one"
  wait "$pid_two"
  "$store" snapshot | jq -e '.state.revision == 2 and (.state.roots|length == 2) and all(.state.roots[]; .id|test("^r-[0-9a-f-]{36}$"))'
  id=$(jq -r '.roots[0].id' "$registry")
  mutate root-remove "$(jq -cn --arg id "$id" '{rootId:$id}')" | jq -e '.state.roots|length == 1'
}
# Catch any mutation or initialization that overwrites invalid existing bytes.
corrupt_state_is_preserved() {
  mkdir -p "$ARANEA_STATE_ROOT"
  for text in '{broken' '{"schemaVersion":2,"revision":0,"roots":[],"ignored":[],"projects":[]}' '{"schemaVersion":1,"revision":0,"roots":[],"ignored":[],"projects":[{}]}'; do
    printf '%s' "$text" >"$registry"
    cp "$registry" "$TMPDIR/original"
    if "$store" snapshot >"$TMPDIR/error"; then return 1; fi
    jq -e '.ok == false and .state == null and (.error.recovery|length > 0)' "$TMPDIR/error"
    if mutate root-add "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{path:$p}')" >"$TMPDIR/error"; then return 1; fi
    cmp "$registry" "$TMPDIR/original"
    [[ $(find "$ARANEA_STATE_ROOT" -name 'projects.json.*' ! -name '*.lock' | wc -l) == 0 ]]
  done
}
# Catch unstable IDs, unsupported preferences, or deletion of repository files.
registration_configuration_and_removal() {
  mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{paths:[$p]}')" >"$TMPDIR/registered"
  jq -e '.ok and (.state.projects|length == 1) and (.state.projects[0]|.id|test("^p-[0-9a-f-]{36}$")) and (.state.projects[0]| .workspaceMode == "dedicated" and .tools == {editorId:null,terminalId:null} and .lastCheckoutId == .checkouts[0].id)' "$TMPDIR/registered"
  id=$(jq -r '.state.projects[0].id' "$TMPDIR/registered")
  checkout=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/registered")
  mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev/." '{paths:[$p]}')" | jq -e --arg id "$id" --arg c "$checkout" '.state.projects|length == 1 and .[0].id == $id and .[0].checkouts[0].id == $c'
  mutate configure "$(jq -cn --arg id "$id" '{projectId:$id,name:"A $(touch NEVER) ; project",editorId:"code",terminalId:"kitty",workspaceMode:"current"}')" | jq -e '.state.projects[0] | .name == "A $(touch NEVER) ; project" and .tools == {editorId:"code",terminalId:"kitty"} and .workspaceMode == "current"'
  cp "$registry" "$TMPDIR/original"
  for args in "$(jq -cn --arg id "$id" '{projectId:$id,editorId:"sh -c evil"}')" "$(jq -cn --arg id "$id" '{projectId:$id,workspaceMode:"other"}')" '{"projectId":"p-missing","name":"missing"}'; do
    if mutate configure "$args" >"$TMPDIR/error"; then return 1; fi
    jq -e '.ok == false' "$TMPDIR/error"
    cmp "$registry" "$TMPDIR/original"
  done
  mutate root-add "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{path:$p}')" >"$TMPDIR/root"
  root_id=$(jq -r '.state.roots[0].id' "$TMPDIR/root")
  mutate root-remove "$(jq -cn --arg id "$root_id" '{rootId:$id}')" | jq -e '.state.projects|length == 1'
  mutate remove "$(jq -cn --arg id "$id" '{projectId:$id}')" | jq -e '.state.projects|length == 0'
  [[ -d "$ARANEA_TEST_SANDBOX/dev/.git" && ! -e NEVER ]]
}
# Catch incorrect ignores or shell interpretation of literal folder/name bytes.
ignore_unignore_and_safe_paths() {
  path="$ARANEA_TEST_SANDBOX/space \$(touch NEVER) ; ' repo"
  mkdir -p "$path"
  git init -q "$path"
  mutate ignore "$(jq -cn --arg p "$path" '{path:$p}')" | jq -e --arg p "$path" '.state.ignored == [{path:$p,commonDir:($p+"/.git")}]'
  mutate ignore "$(jq -cn --arg p "$path/." '{path:$p}')" | jq -e '.state.ignored|length == 1'
  mutate unignore "$(jq -cn --arg p "$path" '{path:$p}')" | jq -e '.state.ignored == []'
  mutate register "$(jq -cn --arg p "$path" '{paths:[$p]}')" | jq -e --arg p "$path" '.state.projects[0].checkouts[0].path == $p'
  [[ ! -e NEVER ]]
}
# Catch changed relocation IDs and interference between association modes.
relocate_and_association_isolation() {
  mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{paths:[$p]}')" >"$TMPDIR/registered"
  id=$(jq -r '.state.projects[0].id' "$TMPDIR/registered")
  checkout=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/registered")
  mutate associate "$(jq -cn --arg id "$id" --arg c "$checkout" '{projectId:$id,checkoutId:$c,mode:"dedicated",workspaceId:4,separate:false}')" | jq -e '.state.projects[0].associations == [{checkoutId:.state.projects[0].checkouts[0].id,mode:"dedicated",workspaceId:4,separate:false}]'
  mutate associate "$(jq -cn --arg id "$id" --arg c "$checkout" '{projectId:$id,checkoutId:$c,mode:"current",workspaceId:8,separate:true}')" | jq -e '.state.projects[0].associations|length == 2'
  mutate associate "$(jq -cn --arg id "$id" --arg c "$checkout" '{projectId:$id,checkoutId:$c,mode:"dedicated",workspaceId:9,separate:false}')" | jq -e '.state.projects[0].associations|length == 2 and any(.[]; .separate and .workspaceId == 8) and any(.[]; (.separate|not) and .workspaceId == 9)'
  moved="$ARANEA_TEST_SANDBOX/moved"
  mv "$ARANEA_TEST_SANDBOX/dev" "$moved"
  mutate relocate "$(jq -cn --arg id "$id" --arg c "$checkout" --arg p "$moved" '{projectId:$id,checkoutId:$c,path:$p}')" | jq -e --arg id "$id" --arg c "$checkout" --arg p "$moved" '.state.projects[0] | .id == $id and .checkouts[0].id == $c and .checkouts[0].path == $p and (.associations|length == 2)'
  mutate select-checkout "$(jq -cn --arg id "$id" --arg c "$checkout" '{projectId:$id,checkoutId:$c}')" | jq -e --arg c "$checkout" '.state.projects[0].lastCheckoutId == $c'
  mv "$moved" "$ARANEA_TEST_SANDBOX/dev"
}
# Catch accepted malformed requests or side effects from rejected actions.
invalid_requests_preserve_state() {
  "$store" snapshot >/dev/null
  cp "$registry" "$TMPDIR/original"
  for request in '{}' '[]' '{"action":"unknown","args":{}}' '{"action":"root-add","args":{"path":"/nonexistent"}}' '{"action":"root-add","args":{"path":1}}' '{"action":"register","args":{"paths":[]}}' '{"action":"root-add","args":{"path":"/tmp"},"expectedRevision":-1}' '{"action":"associate","args":{"projectId":"p-missing","checkoutId":"c-missing","mode":"dedicated","workspaceId":0,"separate":false}}' '{"action":"root-remove","args":{"rootId":"r-missing"}}'; do
    if printf '%s\n' "$request" | "$store" mutate >"$TMPDIR/error"; then return 1; fi
    jq -e '.ok == false and (.error.code|length > 0)' "$TMPDIR/error"
    cmp "$registry" "$TMPDIR/original"
  done
  if printf '{}\n{}\n' | "$store" mutate >"$TMPDIR/error"; then return 1; fi
  jq -e '.ok == false' "$TMPDIR/error"
}
# Catch wrong worktree grouping, initial selection, or association ownership.
grouped_checkouts_preserve_normal_and_separate_associations() {
  git -C "$ARANEA_TEST_SANDBOX/dev" -c user.name=Tests -c user.email=tests@example.invalid commit -q --allow-empty -m initial
  linked="$ARANEA_TEST_SANDBOX/a-linked"
  git -C "$ARANEA_TEST_SANDBOX/dev" worktree add -q "$linked" -b linked
  mutate register "$(jq -cn --arg main "$ARANEA_TEST_SANDBOX/dev" --arg linked "$linked" '{paths:[$linked,$main]}')" >"$TMPDIR/grouped"
  jq -e '.state.projects|length == 1 and (.[0].checkouts|length == 2) and (.[0] | .lastCheckoutId as $selected | any(.checkouts[]; .primary and .id == $selected))' "$TMPDIR/grouped"
  id=$(jq -r '.state.projects[0].id' "$TMPDIR/grouped")
  main_id=$(jq -r '.state.projects[0].checkouts[]|select(.primary)|.id' "$TMPDIR/grouped")
  linked_id=$(jq -r '.state.projects[0].checkouts[]|select(.primary|not)|.id' "$TMPDIR/grouped")
  mutate associate "$(jq -cn --arg p "$id" --arg c "$main_id" '{projectId:$p,checkoutId:$c,mode:"dedicated",workspaceId:2,separate:false}')" >/dev/null
  mutate associate "$(jq -cn --arg p "$id" --arg c "$main_id" '{projectId:$p,checkoutId:$c,mode:"dedicated",workspaceId:3,separate:true}')" >/dev/null
  mutate associate "$(jq -cn --arg p "$id" --arg c "$linked_id" '{projectId:$p,checkoutId:$c,mode:"dedicated",workspaceId:5,separate:false}')" | jq -e --arg main "$main_id" --arg linked "$linked_id" '.state.projects[0].associations|length == 2 and any(.[]; .checkoutId == $main and .separate and .workspaceId == 3) and any(.[]; .checkoutId == $linked and (.separate|not) and .workspaceId == 5)'
  mutate select-checkout "$(jq -cn --arg p "$id" --arg c "$linked_id" '{projectId:$p,checkoutId:$c}')" | jq -e --arg c "$linked_id" '.state.projects[0].lastCheckoutId == $c'
  mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/other" '{paths:[$p]}')" | jq -e '.state.projects|length == 2 and (.[0].associations|length == 2) and .[1].associations == []'
  git -C "$ARANEA_TEST_SANDBOX/dev" worktree remove "$linked"
}
# Catch write success claims, damaged prior bytes, or leftover temporary files.
atomic_write_failure_preserves_previous_state() {
  "$store" snapshot >/dev/null
  cp "$registry" "$TMPDIR/original"
  mkdir -p "$TMPDIR/failing-bin"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$TMPDIR/failing-bin/mv"
  chmod +x "$TMPDIR/failing-bin/mv"
  if PATH="$TMPDIR/failing-bin:$PATH" mutate root-add "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{path:$p}')" >"$TMPDIR/error"; then return 1; fi
  jq -e '.ok == false and .error.code == "REGISTRY_WRITE_FAILED" and .state.revision == 0' "$TMPDIR/error"
  cmp "$registry" "$TMPDIR/original"
  [[ $(find "$ARANEA_STATE_ROOT" -name 'projects.json.*' ! -name '*.lock' | wc -l) == 0 ]]
}
# Catch misleading missing-Git errors or unnecessary root/snapshot dependencies.
missing_git_keeps_registration_unavailable_without_affecting_roots() {
  "$store" snapshot >/dev/null
  cp "$registry" "$TMPDIR/original"
  mkdir -p "$TMPDIR/without-git"
  for dependency in bash jq flock realpath dirname mkdir cat mktemp mv rm sed; do
    ln -s "$(command -v "$dependency")" "$TMPDIR/without-git/$dependency"
  done
  if PATH="$TMPDIR/without-git" mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{paths:[$p]}')" >"$TMPDIR/error"; then return 1; fi
  jq -e '.ok == false and .error.code == "DEPENDENCY_MISSING"' "$TMPDIR/error"
  cmp "$registry" "$TMPDIR/original"
  PATH="$TMPDIR/without-git" mutate root-add "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{path:$p}')" | jq -e '.ok and (.state.roots|length == 1)'
}
# Catch serialized-registration failures and duplicate generated checkout IDs.
competing_registrations_are_both_retained() {
  mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{paths:[$p]}')" >"$TMPDIR/register-one" &
  pid_one=$!
  mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/other" '{paths:[$p]}')" >"$TMPDIR/register-two" &
  pid_two=$!
  wait "$pid_one"
  wait "$pid_two"
  "$store" snapshot | jq -e '.state.revision == 2 and (.state.projects|length == 2) and ([.state.projects[].checkouts[].id]|unique|length == 2)'
}
# Catch inherited repository/config environment manufacturing checkout identity.
inherited_git_context_cannot_register_an_ordinary_directory() {
  ordinary="$ARANEA_TEST_SANDBOX/not-a-repository"
  mkdir -p "$ordinary"
  "$store" snapshot >/dev/null
  cp "$registry" "$TMPDIR/original"
  if GIT_DIR="$ARANEA_TEST_SANDBOX/dev/.git" GIT_WORK_TREE="$ordinary" mutate register "$(jq -cn --arg p "$ordinary" '{paths:[$p]}')" >"$TMPDIR/error"; then return 1; fi
  jq -e '.ok == false and .error.code == "CHECKOUT_INVALID"' "$TMPDIR/error"
  cmp "$registry" "$TMPDIR/original"
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.bare GIT_CONFIG_VALUE_0=true mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{paths:[$p]}')" | jq -e '.ok and .state.projects[0].checkouts[0].primary'
}
# Catch relocation silently combining distinct repositories into one project.
relocation_rejects_an_unrelated_group_without_changing_bytes() {
  linked="$ARANEA_TEST_SANDBOX/relocation-linked"
  git -C "$ARANEA_TEST_SANDBOX/dev" worktree add -q "$linked" -b relocation-linked
  mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" --arg linked "$linked" '{paths:[$p,$linked]}')" >"$TMPDIR/registered"
  project_id=$(jq -r '.state.projects[0].id' "$TMPDIR/registered")
  checkout_id=$(jq -r '.state.projects[0].checkouts[]|select(.primary|not)|.id' "$TMPDIR/registered")
  cp "$registry" "$TMPDIR/original"
  if mutate relocate "$(jq -cn --arg p "$project_id" --arg c "$checkout_id" --arg path "$ARANEA_TEST_SANDBOX/other" '{projectId:$p,checkoutId:$c,path:$path}')" >"$TMPDIR/error"; then return 1; fi
  jq -e '.ok == false and .error.code == "CHECKOUT_CONFLICT"' "$TMPDIR/error"
  cmp "$registry" "$TMPDIR/original"
  git -C "$ARANEA_TEST_SANDBOX/dev" worktree remove "$linked"
}
# Catch over-restrictive relocation preventing an explicitly located group move.
relocation_allows_a_whole_group_move_when_old_paths_are_absent() {
  group="$ARANEA_TEST_SANDBOX/old-group"
  mkdir -p "$group"
  git init -q "$group/main"
  git -C "$group/main" -c user.name=Tests -c user.email=tests@example.invalid commit -q --allow-empty -m initial
  git -C "$group/main" worktree add -q "$group/linked" -b linked
  mutate register "$(jq -cn --arg main "$group/main" --arg linked "$group/linked" '{paths:[$main,$linked]}')" >"$TMPDIR/registered"
  project_id=$(jq -r '.state.projects[0].id' "$TMPDIR/registered")
  main_id=$(jq -r '.state.projects[0].checkouts[]|select(.primary)|.id' "$TMPDIR/registered")
  linked_id=$(jq -r '.state.projects[0].checkouts[]|select(.primary|not)|.id' "$TMPDIR/registered")
  mv "$group" "$ARANEA_TEST_SANDBOX/new-group"
  group="$ARANEA_TEST_SANDBOX/new-group"
  git -C "$group/main" worktree repair "$group/linked" 2>/dev/null
  mutate relocate "$(jq -cn --arg p "$project_id" --arg c "$main_id" --arg path "$group/main" '{projectId:$p,checkoutId:$c,path:$path}')" | jq -e --arg p "$project_id" --arg common "$group/main/.git" '.state.projects[0] | .id == $p and .commonDir == $common'
  mutate relocate "$(jq -cn --arg p "$project_id" --arg c "$linked_id" --arg path "$group/linked" '{projectId:$p,checkoutId:$c,path:$path}')" | jq -e --arg p "$project_id" --arg main "$main_id" --arg linked "$linked_id" '.state.projects[0] | .id == $p and ([.checkouts[].id]|sort) == ([$main,$linked]|sort)'
}
# Catch lossy decoding/canonicalization selecting a different existing sibling.
control_paths_never_silently_select_a_sibling() {
  sibling="$ARANEA_TEST_SANDBOX/control-path"
  raw="$sibling"$'\n'
  mkdir -p "$sibling" "$raw"
  git init -q "$sibling"
  git init -q "$raw"
  mutate register "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/dev" '{paths:[$p]}')" >"$TMPDIR/registered"
  project_id=$(jq -r '.state.projects[0].id' "$TMPDIR/registered")
  checkout_id=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/registered")
  cp "$registry" "$TMPDIR/original"
  for action in root-add ignore unignore register relocate; do
    args=$(jq -cn --arg p "$raw" --arg project "$project_id" --arg checkout "$checkout_id" --arg action "$action" 'if $action == "register" then {paths:[$p]} elif $action == "relocate" then {projectId:$project,checkoutId:$checkout,path:$p} else {path:$p} end')
    if mutate "$action" "$args" >"$TMPDIR/error"; then return 1; fi
    jq -e '.ok == false and .error.code == "INVALID_PATH"' "$TMPDIR/error"
    cmp "$registry" "$TMPDIR/original"
  done
  for control in $'\t' $'\r' $'\x1f' $'\x7f'; do
    if mutate root-add "$(jq -cn --arg p "$sibling$control" '{path:$p}')" >"$TMPDIR/error"; then return 1; fi
    jq -e '.ok == false and .error.code == "INVALID_PATH"' "$TMPDIR/error"
    cmp "$registry" "$TMPDIR/original"
  done
  if mutate root-add '{"path":"/tmp/nul\u0000path"}' >"$TMPDIR/error"; then return 1; fi
  jq -e '.ok == false and .error.code == "INVALID_PATH"' "$TMPDIR/error"
  cmp "$registry" "$TMPDIR/original"
  ln -s "$raw" "$ARANEA_TEST_SANDBOX/control-alias"
  if mutate root-add "$(jq -cn --arg p "$ARANEA_TEST_SANDBOX/control-alias" '{path:$p}')" >"$TMPDIR/error"; then return 1; fi
  jq -e '.ok == false and .error.code == "INVALID_PATH"' "$TMPDIR/error"
  cmp "$registry" "$TMPDIR/original"
}
for case_name in snapshot_initializes_only_absent roots_conflicts_and_concurrency corrupt_state_is_preserved registration_configuration_and_removal ignore_unignore_and_safe_paths relocate_and_association_isolation invalid_requests_preserve_state grouped_checkouts_preserve_normal_and_separate_associations atomic_write_failure_preserves_previous_state missing_git_keeps_registration_unavailable_without_affecting_roots competing_registrations_are_both_retained inherited_git_context_cannot_register_an_ordinary_directory relocation_rejects_an_unrelated_group_without_changing_bytes relocation_allows_a_whole_group_move_when_old_paths_are_absent control_paths_never_silently_select_a_sibling; do run_case "$case_name"; done
((failures == 0))
