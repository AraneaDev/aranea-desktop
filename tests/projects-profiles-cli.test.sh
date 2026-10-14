#!/usr/bin/env bash
# Public profiles use the real store; only the unavailable desktop IPC is replaced.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/project with spaces"
checkout="$ARANEA_TEST_SANDBOX/project with spaces"
git init -qb main "$checkout"
cli="$repo_root/scripts/aranea"
events="$ARANEA_TEST_SANDBOX/events"
export PROFILE_MODE=absent PROFILE_CALLS="$ARANEA_TEST_SANDBOX/calls" PROFILE_TARGET="$ARANEA_TEST_SANDBOX/target" PROFILE_READY="$ARANEA_TEST_SANDBOX/ready"
export PROFILE_ENV=e-11111111-1111-4111-8111-111111111111
cat >"$ARANEA_TEST_SANDBOX/bin/omarchy-shell" <<'OWNER'
#!/usr/bin/env bash
set -euo pipefail
jq -cn --args '$ARGS.positional' -- "$@" >> "$PROFILE_CALLS"
[[ "$PROFILE_MODE" != absent ]] || exit 1
operation() {
  jq -cn --argjson target "$(cat "$PROFILE_TARGET")" --arg env "$PROFILE_ENV" --arg mode "$PROFILE_MODE" '{id:"op-123-1",sessionId:"profile-owner",generation:1,projectId:$target.projectId,checkoutId:$target.checkoutId,activationId:$target.activationId,environmentId:$env,startTarget:$target,state:"completed",outcome:(if $mode=="failed" then "failed" else "observed" end),steps:[{role:"workspace",status:"observed",workspaceId:9}],error:(if $mode=="failed" then {code:"LAUNCH_FAILED"} else null end)}'
}
case "$2" in
  snapshot) echo '{"sessionId":"profile-owner","availability":{"ready":true,"compositor":true},"operations":[]}' ;;
  prepareEnvironment)
    printf '%s\n' "$3" > "$PROFILE_TARGET"
    jq -cn --argjson p "$3" '{ok:true,ready:true,sessionId:"profile-owner",activationId:$p.activationId}' ;;
  startEnvironment)
    printf '%s\n' "$3" > "$PROFILE_TARGET"
    if [[ "$PROFILE_MODE" == readiness && ! -e "$PROFILE_READY" ]]; then
      touch "$PROFILE_READY"
      echo '{"ok":false,"operationId":null,"error":{"code":"OWNER_NOT_READY","message":"Preparing","recovery":"Wait"}}'
    elif [[ "$PROFILE_MODE" == unknown ]]; then exit 1
    elif [[ "$PROFILE_MODE" == contradictory ]]; then jq -cn --arg env "$PROFILE_ENV" '{ok:true,operationId:"op-123-1",environmentId:$env,error:{code:"OWNER_NOT_READY"}}'
    elif [[ "$PROFILE_MODE" == multi ]]; then printf '%s\n' '{"ok":false,"operationId":null}' '{"ok":true}'
    elif [[ "$PROFILE_MODE" == malformed ]]; then echo '{"ok":true}'
    else jq -cn --arg env "$PROFILE_ENV" '{ok:true,operationId:"op-123-1",environmentId:$env}'; fi ;;
  returnEnvironment)
    touch "$PROFILE_TARGET.return"
    jq -e --arg env "$PROFILE_ENV" 'keys==["environmentId","projectId"] and .environmentId==$env' <<< "$3" >/dev/null
    jq -cn --arg env "$PROFILE_ENV" '{ok:true,operationId:"op-123-1",environmentId:$env}' ;;
  operation)
    if [[ -e "$PROFILE_TARGET.return" ]]; then operation | jq '.+{environmentReturn:true,workspaceId:9}';
    elif [[ "$PROFILE_MODE" == wrongtarget ]]; then operation | jq '.environmentId="e-22222222-2222-4222-8222-222222222222"'; else operation; fi ;;
  environmentActivation)
    if [[ "$PROFILE_MODE" == notfound ]]; then
      jq -cn --argjson p "$3" '{ok:true,sessionId:"profile-owner",activationId:$p.activationId,found:false}'
    else
      operation | jq --argjson p "$3" --arg mode "$PROFILE_MODE" '{ok:true,sessionId:"profile-owner",activationId:$p.activationId,found:true,operationId:.id,environmentId:.environmentId,operation:.} | if $mode=="mismatch" then .operation.activationId="a-22222222-2222-4222-8222-222222222222" else . end'
    fi ;;
  *) exit 99 ;;
esac
OWNER
cat >"$ARANEA_TEST_SANDBOX/bin/systemctl" <<'MANAGER'
#!/usr/bin/env bash
if [[ $# -eq 4 && $1 == --user && $2 == --no-ask-password && $3 == show && $4 == --property=Version ]]; then exit 0; fi
printf 'unexpected manager call\n' >> "$ARANEA_TEST_SANDBOX/guard.log"
exit 99
MANAGER
chmod +x "$ARANEA_TEST_SANDBOX/bin/omarchy-shell" "$ARANEA_TEST_SANDBOX/bin/systemctl"
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
# Wrong exit status or a missing public completion is a protocol regression.
run_cli() {
  local expected=$1 actual=0
  shift
  "$cli" "$@" --json >"$events" 2>"$ARANEA_TEST_SANDBOX/diagnostics" || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected exit %s, got %s: %s\n' "$expected" "$actual" "$*"
    cat "$events" "$ARANEA_TEST_SANDBOX/diagnostics"
    exit 1
  fi
  jq -se 'length>0 and all(.[];.schema==1 and has("timestamp")) and last.event=="completed"' "$events" >/dev/null
}
run_cli 0 projects register --path "$checkout"
project=$(jq -r 'select(.event=="completed")|.data.state.projects[0].id' "$events")
run_cli 0 projects profiles list "$project"
jq -se 'last.operation=="projects.profiles.list" and last.data.profiles==[]' "$events" >/dev/null
# Shell-looking names stay literal, and headless profile reads/writes never use IPC.
# shellcheck disable=SC2016
name='Focus " ; $(touch nope)'
definition=$(jq -cn --arg name "$name" '{name:$name,roles:["terminal"],tools:{editorId:null,terminalId:"kitty",agentId:null}}')
run_cli 0 projects profiles save "$project" --definition "$definition"
run_cli 0 projects profiles list "$project"
profile=$(jq -r 'select(.event=="completed")|.data.profiles[0].id' "$events")
jq -se --arg name "$name" 'last.data.profiles[0].name==$name and last.data.profiles[0].revision==1' "$events" >/dev/null
[[ ! -e "$PROFILE_CALLS" ]]
draft=$(jq -c --arg id "$profile" '.+{id:$id}' <<<"$definition")
run_cli 0 projects profiles save "$project" --definition "$draft" --expected-profile-revision 1
run_cli 1 projects profiles save "$project" --definition "$draft" --expected-profile-revision 1
jq -se 'last.code=="PROFILE_CONFLICT"' "$events" >/dev/null
run_cli 2 projects profiles save "$project" --definition '{bad'
run_cli 2 projects profiles remove "$project" "$profile"
run_cli 2 projects profiles remove "$project" "$profile" --expected-profile-revision 0
run_cli 2 projects start "$project" --profile "$profile" --checkout forbidden
run_cli 1 projects start "$project" --profile "$profile"
jq -se 'last.code=="OWNER_UNAVAILABLE" and all(.[];.status!="accepted")' "$events" >/dev/null
PROFILE_MODE=readiness run_cli 0 projects start "$project" --profile "$profile"
jq -se 'last.data.outcome=="observed"' "$events" >/dev/null
jq -se --arg p "$project" --arg f "$profile" '[.[]|select(.[1]=="startEnvironment")|.[2]|fromjson] as $sent | ($sent|length)==2 and $sent[0]==$sent[1] and $sent[0].projectId==$p and $sent[0].profileId==$f and $sent[0].profileRevision==2 and ($sent[0].activationId|test("^a-[0-9a-f-]{36}$"))' "$PROFILE_CALLS" >/dev/null
for mode in unknown malformed contradictory multi; do
  before=$(jq -s '[.[]|select(.[1]=="startEnvironment")]|length' "$PROFILE_CALLS")
  PROFILE_MODE="$mode" run_cli 1 projects start "$project" --profile "$profile"
  jq -se 'last.code=="ACCEPTANCE_UNKNOWN" and last.data.acceptanceUnknown==true and last.data.activationId==last.data.target.activationId and last.data.sessionId=="profile-owner" and (last.data.recovery|contains("projects activation a-"))' "$events" >/dev/null
  [[ $(jq -s '[.[]|select(.[1]=="startEnvironment")]|length' "$PROFILE_CALLS") == $((before + 1)) ]]
done
activation=$(jq -r .activationId "$PROFILE_TARGET")
PROFILE_MODE=failed run_cli 1 projects start "$project" --profile "$profile"
activation=$(jq -r .activationId "$PROFILE_TARGET")
PROFILE_MODE=wrongtarget run_cli 1 projects start "$project" --profile "$profile"
jq -se 'last.code=="OPERATION_LOST"' "$events" >/dev/null
activation=$(jq -r .activationId "$PROFILE_TARGET")
# Retained lookup is read-only even for completed/evicted operations and not-found.
before=$(wc -l <"$PROFILE_CALLS")
PROFILE_MODE=normal run_cli 0 projects activation "$activation"
jq -se 'last.data.found and last.data.operation.state=="completed" and last.data.operationId==last.data.operation.id' "$events" >/dev/null
PROFILE_MODE=notfound run_cli 1 projects activation "$activation"
jq -se 'last.data.found==false and last.data.outcome=="partial"' "$events" >/dev/null
PROFILE_MODE=mismatch run_cli 1 projects activation "$activation"
jq -se 'last.code=="ACTIVATION_UNCONFIRMED"' "$events" >/dev/null
PROFILE_MODE=absent run_cli 1 projects activation "$activation"
run_cli 2 projects activation a-invalid
jq -se --argjson before "$before" '.[ $before: ] | all(.[];.[1]=="environmentActivation")' "$PROFILE_CALLS" >/dev/null
# Exact environment resolution uses immutable store identity, never current selection.
state=$("$repo_root/scripts/aranea-project-store" snapshot)
jq -cn --argjson state "$state" --arg env "$PROFILE_ENV" --arg activation "$activation" '$state.state.projects[0] as $p | {action:"environment-register",args:{projectId:$p.id,environment:{id:$env,projectId:$p.id,checkoutId:$p.lastCheckoutId,activationId:$activation,workspaceId:9,sessionId:"profile-owner",createdAt:1,checkoutSnapshot:$p.checkouts[0],profileSnapshot:$p.profiles[0],resolvedTools:$p.profiles[0].tools}}}' | "$repo_root/scripts/aranea-project-store" mutate >/dev/null
run_cli 0 projects environments list --project "$project"
jq -se --arg env "$PROFILE_ENV" 'last.data.environments|length==1 and .[0].id==$env' "$events" >/dev/null
run_cli 1 projects environments return "$PROFILE_ENV"
jq -se 'last.code=="OWNER_UNAVAILABLE"' "$events" >/dev/null
PROFILE_MODE=normal run_cli 0 projects environments return "$PROFILE_ENV"
run_cli 1 projects environments return e-22222222-2222-4222-8222-222222222222
run_cli 0 projects profiles remove "$project" "$profile" --expected-profile-revision 2
run_cli 0 projects environments list --project "$project"
jq -se 'last.data.environments[0].profileSnapshot.revision==2' "$events" >/dev/null
run_cli 0 projects environments forget "$PROFILE_ENV"
run_cli 0 projects environments list --project "$project"
jq -se 'last.data.environments==[]' "$events" >/dev/null
run_cli 0 capabilities
jq -se 'last.data.operations as $ops | all(["projects.profiles.list","projects.profiles.save","projects.profiles.remove","projects.start","projects.environments.list","projects.environments.return","projects.environments.forget","projects.activation"][]; . as $name | any($ops[];.name==$name)) and any($ops[];.name=="projects.start" and .arguments.profile.required and (.arguments|has("checkout")|not)) and any($ops[];.name=="projects.activation" and .readOnly==true)' "$events" >/dev/null
[[ ! -e nope && ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
echo 'profiles CLI: headless configuration, exact Start/Return, retained lookup and no uncertain replay passed'
