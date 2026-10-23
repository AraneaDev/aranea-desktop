#!/usr/bin/env bash
# Profile contracts exercise the real locked store and immutable saved records.
# shellcheck disable=SC2329
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
store="$repo_root/scripts/aranea-project-store"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
registry="$ARANEA_STATE_ROOT/projects.json"
result="$TMPDIR/result.json"
repo="$ARANEA_TEST_SANDBOX/repo"
git init -q -b main "$repo"
# Submit the public mutation format to the actual store.
mutate() { jq -cn --arg action "$1" --argjson args "$2" --argjson revision "$(if [[ -f "$registry" ]]; then jq .revision "$registry"; else printf 0; fi)" '{action:$action,args:$args} + (if $action == "environment-associate" then {expectedRevision:$revision} else {} end)' | "$store" mutate >"$result"; }
# Register with the sandbox's stub tools; registration seeds detected presets.
register_seeded() {
  rm -rf "$ARANEA_STATE_ROOT"
  mutate register "$(jq -cn --arg path "$repo" '{paths:[$path]}')"
  project_id=$(jq -r '.state.projects[0].id' "$result")
  checkout_id=$(jq -r '.state.projects[0].checkouts[0].id' "$result")
}
# Profile contracts start from a project with no profiles: drop the seeded presets.
setup() {
  local profile
  register_seeded
  while IFS= read -r profile; do
    mutate profile-remove "$(jq -cn --arg p "$project_id" --argjson f "$profile" '{projectId:$p,profileId:$f.id,expectedProfileRevision:$f.revision}')"
  done < <(jq -c '.state.projects[0].profiles[]|{id,revision}' "$result")
  jq -e '.state.projects[0].profiles == []' "$result" >/dev/null
}
# Build a real legacy registry, retaining every legacy field and navigation.
legacy() {
  setup
  mutate configure "$(jq -cn --arg p "$project_id" '{projectId:$p,editorId:"nvim",terminalId:"kitty",openRoles:["editor","terminal"],agentId:"codex"}')"
  mutate associate "$(jq -cn --arg p "$project_id" --arg c "$checkout_id" '{projectId:$p,checkoutId:$c,mode:"dedicated",workspaceId:7,separate:false}')"
  mutate navigation-set "$(jq -cn --arg p "$project_id" '{projectId:$p,pinned:true}')"
  mutate navigation-set "$(jq -cn --arg p "$project_id" '{projectId:$p,visit:true}')"
  jq '.schemaVersion=1 | .projects |= map(del(.profiles,.lastProfileId,.environments))' "$registry" >"$TMPDIR/v1"
  cp "$TMPDIR/v1" "$registry"
}
# Catch remigration, guessed tools, changed IDs, and lost legacy/navigation state.
migration_is_atomic_once() {
  legacy
  "$store" snapshot >"$result"
  jq -e --slurpfile old "$TMPDIR/v1" '.ok and .state.schemaVersion == 2 and .state.revision == ($old[0].revision + 1)
    and .state.navigation == $old[0].navigation and .state.roots == $old[0].roots and .state.ignored == $old[0].ignored
    and (.state.projects[0] | del(.profiles,.lastProfileId,.environments)) == $old[0].projects[0]
    and (.state.projects[0] as $p | $p.profiles == [{id:$p.lastProfileId,name:"Default",revision:1,roles:$p.openRoles,tools:$p.tools}]
      and ($p.lastProfileId|test("^f-[0-9a-f-]{36}$")) and $p.environments == [])' "$result" >/dev/null
  cp "$registry" "$TMPDIR/migrated"
  "$store" snapshot >"$result"
  cmp "$registry" "$TMPDIR/migrated"
  # Competing snapshots must migrate once and observe identical generated IDs.
  cp "$TMPDIR/v1" "$registry"
  "$store" snapshot >"$TMPDIR/migrate-one" &
  one=$!
  "$store" snapshot >"$TMPDIR/migrate-two" &
  two=$!
  wait "$one"
  wait "$two"
  cmp "$TMPDIR/migrate-one" "$TMPDIR/migrate-two"
  jq -e --slurpfile old "$TMPDIR/v1" '.state.revision == ($old[0].revision + 1)' "$TMPDIR/migrate-one" >/dev/null
  # Null choices remain unresolved, and absent legacy roles preserve normal Open.
  jq '.schemaVersion=1 | .projects |= map(del(.profiles,.lastProfileId,.environments,.openRoles) | .tools={editorId:null,terminalId:null})' "$registry" >"$TMPDIR/unresolved"
  cp "$TMPDIR/unresolved" "$registry"
  "$store" snapshot | jq -e '.state.projects[0].profiles[0] | .roles == ["editor","terminal"] and .tools == {editorId:null,terminalId:null,agentId:null}' >/dev/null
}
# Invalid source or failed migration must never replace original bytes.
migration_failure_preserves_bytes() {
  legacy
  jq '.projects[0].openRoles=["unsupported"]' "$registry" >"$TMPDIR/invalid"
  cp "$TMPDIR/invalid" "$registry"
  if "$store" snapshot >"$result"; then return 1; fi
  jq -e '.error.code == "REGISTRY_INVALID"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/invalid"
  legacy
  cp "$registry" "$TMPDIR/original"
  # Force an invalid shell-generated UUID while keeping all other reads real.
  mkdir -p "$TMPDIR/bad-id"
  real_cat=$(command -v cat)
  export real_cat
  cat >"$TMPDIR/bad-id/cat" <<'CAT'
#!/usr/bin/env bash
if [[ "$1" == /proc/sys/kernel/random/uuid ]]; then printf 'invalid\n'; else exec "$real_cat" "$@"; fi
CAT
  chmod +x "$TMPDIR/bad-id/cat"
  if PATH="$TMPDIR/bad-id:$PATH" "$store" snapshot >"$result"; then return 1; fi
  jq -e '.error.code == "REGISTRY_INVALID"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
}
# New registration seeds detected presets without remembering any as last used.
new_projects_seed_detected_presets() {
  register_seeded
  jq -e '.state.schemaVersion == 2 and (.state.projects[0] | (.profiles|length) > 0 and all(.profiles[];.revision == 1) and .lastProfileId == null and .environments == [])' "$result" >/dev/null
}
# Git refresh accepts old/new registry schemas while never initializing/migrating.
git_reads_both_schemas_without_writes() {
  legacy
  cp "$registry" "$TMPDIR/original"
  "$repo_root/scripts/aranea-project-git-state" --project "$project_id" --checkout "$checkout_id" --json | jq -e .ok >/dev/null
  cmp "$registry" "$TMPDIR/original"
  "$store" snapshot >"$result"
  cp "$registry" "$TMPDIR/migrated"
  "$repo_root/scripts/aranea-project-git-state" --project "$project_id" --checkout "$checkout_id" --json | jq -e .ok >/dev/null
  cmp "$registry" "$TMPDIR/migrated"
}
# Save a supported draft; IDs and revisions are assigned by the store.
save_profile() {
  mutate profile-save "$(jq -cn --arg p "$project_id" --arg name "$1" '{projectId:$p,profile:{name:$name,roles:["editor","terminal"],tools:{editorId:"code",terminalId:"kitty",agentId:null}}}')"
  profile_id=$(jq -r '.state.projects[0].profiles[-1].id' "$result")
}
# Stale profile/global revisions must leave bytes intact; legacy choices independent.
profiles_revisions_and_legacy_isolation() {
  setup
  name=$'Odd " name\n ; $(touch NEVER) 🕷'
  save_profile "$name"
  jq -e --arg name "$name" '.state.projects[0].profiles[0] | .name == $name and .revision == 1 and (.id|test("^f-[0-9a-f-]{36}$"))' "$result" >/dev/null
  # An explicit revision 1 is accepted on create.
  mutate profile-save "$(jq -cn --arg p "$project_id" '{projectId:$p,profile:{name:"Other",revision:1,roles:["terminal"],tools:{editorId:null,terminalId:"foot",agentId:null}}}')"
  draft=$(jq -c '.state.projects[0].profiles[0] | .name="Edited"' "$result")
  mutate profile-save "$(jq -cn --arg p "$project_id" --argjson profile "$draft" '{projectId:$p,profile:$profile,expectedProfileRevision:1}')"
  jq -e '.state.projects[0].profiles[0].revision == 2' "$result" >/dev/null
  cp "$registry" "$TMPDIR/original"
  for args in "$(jq -cn --arg p "$project_id" --argjson profile "$draft" '{projectId:$p,profile:$profile,expectedProfileRevision:1}')" "$(jq -cn --arg p "$project_id" --argjson profile "$draft" '{projectId:$p,profile:$profile}')"; do
    if mutate profile-save "$args"; then return 1; fi
    jq -e '.error.code == "PROFILE_CONFLICT"' "$result" >/dev/null
    cmp "$registry" "$TMPDIR/original"
  done
  if jq -cn --arg p "$project_id" '{action:"profile-save",expectedRevision:0,args:{projectId:$p,profile:{name:"Other",roles:["terminal"],tools:{editorId:null,terminalId:"foot",agentId:null}}}}' | "$store" mutate >"$result"; then return 1; fi
  jq -e '.error.code == "REGISTRY_CONFLICT"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  # Removing a stale revision must not erase an independently edited profile.
  if mutate profile-remove "$(jq -cn --arg p "$project_id" --arg f "$profile_id" '{projectId:$p,profileId:$f,expectedProfileRevision:1}')"; then return 1; fi
  jq -e '.error.code == "PROFILE_CONFLICT"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  # Optional draft revision can be omitted while the expected edit revision is required.
  draft=$(jq -c '.projects[0].profiles[0] | del(.revision) | .name="Revision-free edit"' "$registry")
  mutate profile-save "$(jq -cn --arg p "$project_id" --argjson profile "$draft" '{projectId:$p,profile:$profile,expectedProfileRevision:2}')"
  jq -e '.state.projects[0].profiles[0].revision == 3' "$result" >/dev/null
  cp "$registry" "$TMPDIR/original"
  mutate configure "$(jq -cn --arg p "$project_id" '{projectId:$p,editorId:"nvim",terminalId:"foot",openRoles:["agent"],agentId:"claude"}')"
  jq -e --slurpfile old "$TMPDIR/original" '.state.projects[0].profiles == $old[0].projects[0].profiles and .state.projects[0].openRoles == ["agent"]' "$result" >/dev/null
  [[ ! -e NEVER ]]
}
# Strict shapes reject overrides, unsupported tools, noncanonical roles and IDs.
invalid_profiles_preserve_bytes() {
  setup
  cp "$registry" "$TMPDIR/original"
  for patch in '{"roles":[]}' '{"roles":["terminal","editor"]}' '{"roles":["editor","editor"]}' '{"roles":["browser"]}' '{"name":""}' '{"name":"bad\u0000name"}' '{"tools":{"editorId":"vim","terminalId":null,"agentId":null}}' '{"checkoutId":"c-any"}' '{"workspaceId":4}' '{"workspaceMode":"current"}' '{"commands":[]}' '{"actions":[]}' '{"id":"f-bad"}' '{"revision":0}' '{"revision":2}'; do
    args=$(jq -cn --arg p "$project_id" --argjson patch "$patch" '{projectId:$p,profile:({name:"Bad",roles:["terminal"],tools:{editorId:null,terminalId:"kitty",agentId:null}} + $patch)}')
    if mutate profile-save "$args"; then return 1; fi
    cmp "$registry" "$TMPDIR/original"
  done
}
# Produce a launch snapshot using exact selected identities, with owner UUIDs.
environment_args() {
  jq -cn --slurpfile state "$registry" --arg p "$project_id" --arg f "$profile_id" '$state[0].projects[0] as $p | ($p.profiles[]|select(.id==$f)) as $profile | {projectId:$p.id,environment:{id:"e-11111111-1111-4111-8111-111111111111",projectId:$p.id,checkoutId:$p.lastCheckoutId,activationId:"a-11111111-1111-4111-8111-111111111111",workspaceId:9,sessionId:"shell-session",createdAt:123,checkoutSnapshot:($p.checkouts[]|select(.id==$p.lastCheckoutId)),profileSnapshot:$profile,resolvedTools:$profile.tools}}'
}
# Edits/removal cannot rewrite retained profile/tool/checkout launch snapshots.
environment_snapshots_and_last_used() {
  setup
  save_profile First
  first=$profile_id
  save_profile Second
  second=$profile_id
  profile_id=$first
  args=$(environment_args)
  mutate environment-register "$args"
  jq -e --arg f "$first" '.state.projects[0].lastProfileId == $f and (.state.projects[0].environments|length)==1' "$result" >/dev/null
  jq '.projects[0].environments' "$registry" >"$TMPDIR/environments"
  draft=$(jq -c '.projects[0].profiles[0] | .name="Changed" | .tools.editorId="nvim"' "$registry")
  mutate profile-save "$(jq -cn --arg p "$project_id" --argjson profile "$draft" '{projectId:$p,profile:$profile,expectedProfileRevision:1}')"
  mutate profile-remove "$(jq -cn --arg p "$project_id" --arg f "$first" '{projectId:$p,profileId:$f,expectedProfileRevision:2}')"
  jq -e --arg f "$second" --slurpfile env "$TMPDIR/environments" '.state.projects[0].lastProfileId == $f and .state.projects[0].environments == $env[0]' "$result" >/dev/null
  mutate profile-remove "$(jq -cn --arg p "$project_id" --arg f "$second" '{projectId:$p,profileId:$f,expectedProfileRevision:1}')"
  jq -e --slurpfile env "$TMPDIR/environments" '.state.projects[0].lastProfileId == null and .state.projects[0].profiles == [] and .state.projects[0].environments == $env[0]' "$result" >/dev/null
  # An already accepted snapshot can outlive its deleted profile, without remembering it.
  args=$(jq -c '.environment.id="e-22222222-2222-4222-8222-222222222222" | .environment.activationId="a-22222222-2222-4222-8222-222222222222"' <<<"$args")
  mutate environment-register "$args"
  jq -e '.state.projects[0].lastProfileId == null and (.state.projects[0].environments|length)==2' "$result" >/dev/null
  mutate environment-associate "$(jq -cn --arg p "$project_id" '{projectId:$p,environmentId:"e-11111111-1111-4111-8111-111111111111",previousWorkspaceId:9,workspaceId:12}')"
  jq -e --slurpfile env "$TMPDIR/environments" '.state.projects[0].environments[0] == ($env[0][0]+{workspaceId:12})' "$result" >/dev/null
  # A relocation stamps when the environment took its new workspace.
  mutate environment-associate "$(jq -cn --arg p "$project_id" '{projectId:$p,environmentId:"e-11111111-1111-4111-8111-111111111111",previousWorkspaceId:12,workspaceId:14,placedAt:5000}')"
  jq -e '.state.projects[0].environments[0] | .workspaceId == 14 and .placedAt == 5000' "$result" >/dev/null
  # Launched windows are recorded per compositor instance; a new instance replaces them.
  windows() { jq -cn --arg p "$project_id" --arg i "$1" --argjson rows "$2" '{projectId:$p,environmentId:"e-11111111-1111-4111-8111-111111111111",windows:{instance:$i,rows:$rows}}'; }
  mutate environment-windows "$(windows hypr-a '[{"address":"0xa1","pid":11}]')"
  mutate environment-windows "$(windows hypr-a '[{"address":"0xa1","pid":11},{"address":"0xb2","pid":12}]')"
  jq -e '.state.projects[0].environments[0].windows == {instance:"hypr-a",rows:[{address:"0xa1",pid:11},{address:"0xb2",pid:12}]}' "$result" >/dev/null
  mutate environment-windows "$(windows hypr-b '[{"address":"0xc3","pid":13}]')"
  jq -e '.state.projects[0].environments[0].windows == {instance:"hypr-b",rows:[{address:"0xc3",pid:13}]} and .state.projects[0].environments[1].windows == null' "$result" >/dev/null
  cp "$registry" "$TMPDIR/original"
  for rows in '[]' '[{"address":"0x0","pid":1}]' '[{"address":"0xa","pid":0}]' '[{"address":"0xa","pid":1,"extra":1}]'; do
    if mutate environment-windows "$(windows hypr-b "$rows")"; then return 1; fi
    cmp "$registry" "$TMPDIR/original"
  done
  mutate environment-associate "$(jq -cn --arg p "$project_id" '{projectId:$p,environmentId:"e-11111111-1111-4111-8111-111111111111",previousWorkspaceId:14,workspaceId:15}')"
  # A workspace move invalidates recorded windows; they belonged to the old placement.
  jq -e '.state.projects[0].environments[0] | .workspaceId == 15 and (has("windows")|not)' "$result" >/dev/null
  mutate environment-associate "$(jq -cn --arg p "$project_id" '{projectId:$p,environmentId:"e-11111111-1111-4111-8111-111111111111",previousWorkspaceId:15,workspaceId:14,placedAt:5000}')"
  cp "$registry" "$TMPDIR/original"
  if mutate environment-associate "$(jq -cn --arg p "$project_id" '{projectId:$p,environmentId:"e-11111111-1111-4111-8111-111111111111",previousWorkspaceId:9,workspaceId:13}')"; then return 1; fi
  jq -e '.error.code == "ENVIRONMENT_CONFLICT"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  mutate environment-forget "$(jq -cn --arg p "$project_id" '{projectId:$p,environmentId:"e-11111111-1111-4111-8111-111111111111"}')"
  jq -e '(.state.projects[0].environments|length)==1' "$result" >/dev/null
  mutate remove "$(jq -cn --arg p "$project_id" '{projectId:$p}')"
  jq -e '.state.projects == []' "$result" >/dev/null
  [[ -d "$repo/.git" ]]
}
# Wrong identities, snapshot substitutions and arbitrary launch data cannot persist.
invalid_environments_preserve_bytes() {
  setup
  save_profile Work
  args=$(environment_args)
  cp "$registry" "$TMPDIR/original"
  for filter in '.environment.id="bad"' '.environment.projectId="p-22222222-2222-4222-8222-222222222222"' '.environment.checkoutId="c-22222222-2222-4222-8222-222222222222"' '.environment.checkoutSnapshot.path="/substituted"' '.environment.checkoutSnapshot.id="c-22222222-2222-4222-8222-222222222222"' '.environment.checkoutSnapshot.primary=false' '.environment.checkoutSnapshot.branch=42' '.environment.activationId="bad"' '.environment.workspaceId=0' '.environment.createdAt=-1' '.environment.profileSnapshot.tools.editorId="bash"' '.environment.resolvedTools.agentId="gemini"' '.environment.commands=[]'; do
    if mutate environment-register "$(jq -c "$filter" <<<"$args")"; then return 1; fi
    cmp "$registry" "$TMPDIR/original"
  done
  mutate environment-register "$args"
  cp "$registry" "$TMPDIR/original"
  if mutate environment-register "$args"; then return 1; fi
  jq -e '.error.code == "ENVIRONMENT_CONFLICT"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  # Existing snapshots remain valid after checkout branch metadata changes.
  jq '.projects[0].checkouts[0].branch="later-branch"' "$registry" >"$TMPDIR/changed"
  cp "$TMPDIR/changed" "$registry"
  "$store" snapshot >"$result"
  jq -e '.ok and .state.projects[0].environments[0].checkoutSnapshot.branch == "main"' "$result" >/dev/null
}
# Loading corrupt schema-2 metadata must preserve bytes instead of repairing it.
invalid_saved_profiles_and_environments() {
  setup
  save_profile Work
  mutate environment-register "$(environment_args)"
  cp "$registry" "$TMPDIR/original"
  for filter in '.projects[0].profiles[0].roles=["unsupported"]' '.projects[0].profiles[0].revision=0' '.projects[0].profiles[0].commands=[]' '.projects[0].lastProfileId="f-22222222-2222-4222-8222-222222222222"' '.projects[0].environments[0].projectId="p-22222222-2222-4222-8222-222222222222"' '.projects[0].environments[0].resolvedTools.editorId="bash"' '.projects[0].environments[0].workspaceId=null'; do
    jq "$filter" "$TMPDIR/original" >"$registry"
    cp "$registry" "$TMPDIR/invalid-registry"
    if "$store" snapshot >"$result"; then return 1; fi
    jq -e '.error.code == "REGISTRY_INVALID"' "$result" >/dev/null
    cmp "$registry" "$TMPDIR/invalid-registry"
  done
}
# Store-assigned environment IDs and session/activation uniqueness are atomic.
environment_identity_conflicts() {
  setup
  save_profile Work
  args=$(environment_args | jq 'del(.environment.id)')
  mutate environment-register "$args"
  jq -e '.state.projects[0].environments[0].id | test("^e-[0-9a-f-]{36}$")' "$result" >/dev/null
  cp "$registry" "$TMPDIR/original"
  if mutate environment-register "$args"; then return 1; fi
  jq -e '.error.code == "ENVIRONMENT_CONFLICT"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  # A different ID cannot evade the duplicate activation guard.
  if mutate environment-register "$(jq '.environment.id="e-22222222-2222-4222-8222-222222222222"' <<<"$args")"; then return 1; fi
  cmp "$registry" "$TMPDIR/original"
  mutate environment-register "$(jq '.environment.sessionId="new-session"' <<<"$args")"
  jq -e '.state.projects[0].environments | length == 2 and (map(.id)|unique|length)==2' "$result" >/dev/null
  # IDs and activation identities are global, even across different projects.
  other_repo="$ARANEA_TEST_SANDBOX/other-repo"
  git init -q -b main "$other_repo"
  mutate register "$(jq -cn --arg path "$other_repo" '{paths:[$path]}')"
  original_id=$(jq -r '.projects[0].environments[0].id' "$registry")
  other_args=$(jq -c --slurpfile state "$registry" --arg id "$original_id" '$state[0].projects[1] as $p | .projectId=$p.id | .environment.projectId=$p.id | .environment.checkoutId=$p.lastCheckoutId | .environment.checkoutSnapshot=$p.checkouts[0] | .environment.id=$id | .environment.activationId="a-33333333-3333-4333-8333-333333333333"' <<<"$args")
  cp "$registry" "$TMPDIR/original"
  if mutate environment-register "$other_args"; then return 1; fi
  jq -e '.error.code == "ENVIRONMENT_CONFLICT"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  if mutate environment-register "$(jq 'del(.environment.id) | .environment.activationId="a-11111111-1111-4111-8111-111111111111"' <<<"$other_args")"; then return 1; fi
  jq -e '.error.code == "ENVIRONMENT_CONFLICT"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  # Workspace reassociation requires the global revision and preserves every snapshot.
  association=$(jq -c '.projects[0] | {projectId:.id,environmentId:.environments[0].id,previousWorkspaceId:9,workspaceId:12}' "$registry")
  cp "$registry" "$TMPDIR/original"
  if jq -cn --argjson args "$association" '{action:"environment-associate",args:$args}' | "$store" mutate >"$result"; then return 1; fi
  jq -e '.error.code == "INVALID_REQUEST"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  if jq -cn --argjson args "$association" '{action:"environment-associate",args:$args,expectedRevision:0}' | "$store" mutate >"$result"; then return 1; fi
  jq -e '.error.code == "REGISTRY_CONFLICT"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/original"
  # Corrupt duplicate activation metadata is rejected on load as well.
  jq '.projects[0].environments[1].sessionId="shell-session"' "$registry" >"$TMPDIR/duplicate"
  cp "$TMPDIR/duplicate" "$registry"
  if "$store" snapshot >"$result"; then return 1; fi
  jq -e '.error.code == "REGISTRY_INVALID"' "$result" >/dev/null
  cmp "$registry" "$TMPDIR/duplicate"
}
failures=0
cases=(environment_identity_conflicts migration_is_atomic_once migration_failure_preserves_bytes new_projects_seed_detected_presets git_reads_both_schemas_without_writes profiles_revisions_and_legacy_isolation invalid_profiles_preserve_bytes environment_snapshots_and_last_used invalid_environments_preserve_bytes invalid_saved_profiles_and_environments)
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
