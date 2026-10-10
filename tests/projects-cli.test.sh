#!/usr/bin/env bash
# Public projects protocol with a real registry and isolated owner IPC.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo ' ; \$(touch nope)"
checkout="$ARANEA_TEST_SANDBOX/repo ' ; \$(touch nope)"
git init -q "$checkout"
export CLI_MODE=partial CLI_CALLS="$ARANEA_TEST_SANDBOX/calls" CLI_COUNT="$ARANEA_TEST_SANDBOX/count" CLI_PAYLOAD="$ARANEA_TEST_SANDBOX/payload"
cat >"$ARANEA_TEST_SANDBOX/bin/omarchy-shell" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
jq -cn --args '$ARGS.positional' -- "$@" >> "$CLI_CALLS"
case "$1 $2" in
  'aranea.projects snapshot')
    session=s1
    [[ "$CLI_MODE" != lost || ! -f "$CLI_COUNT" ]] || session=s2
    compositor=true
    [[ "$CLI_MODE" != compositor ]] || compositor=false
    jq -cn --argjson compositor "$compositor" --arg session "$session" '{sessionId:$session,observedAt:123,availability:{ready:true,registry:true,compositor:$compositor},projects:[],bindings:[],operations:[]}' ;;
  'aranea.projects request')
    printf '%s\n' "$3" > "$CLI_PAYLOAD"
    case "$CLI_MODE" in
      empty) exit 0 ;;
      malformed) printf '{broken\n'; exit 0 ;;
      nonobject) echo '[]'; exit 0 ;;
      nonconforming) echo '{"ok":true,"operationId":null,"error":{"code":"OWNER_NOT_READY","message":"Wait","recovery":"Retry"}}'; exit 0 ;;
      badrefusal) echo '{"ok":false,"operationId":null,"error":{"code":"","message":"","recovery":""}}'; exit 0 ;;
    esac
    if [[ "$CLI_MODE" == choice ]]; then
      echo '{"ok":false,"operationId":null,"error":{"code":"TOOL_CHOICE_REQUIRED","message":"Choose tools","recovery":"Configure tools"}}'
    elif [[ "$CLI_MODE" == ready && ! -f "$CLI_COUNT" ]]; then
      touch "$CLI_COUNT"
      echo '{"ok":false,"operationId":null,"error":{"code":"OWNER_NOT_READY","message":"Preparing","recovery":"Wait"}}'
    else echo '{"ok":true,"operationId":"op-123-1","error":null}'; fi ;;
  'aranea.projects operation')
    touch "$CLI_COUNT"
    [[ "$CLI_MODE" != disconnected ]] || exit 1
    [[ "$3" == op-123-1 ]] || { echo '{"error":{"code":"OPERATION_LOST","message":"Unavailable"}}'; exit; }
    state=completed outcome=partial
    [[ "$CLI_MODE" != observed && "$CLI_MODE" != ready ]] || outcome=observed
    [[ "$CLI_MODE" != pending && "$CLI_MODE" != lost ]] || { state=observing; outcome=null; }
    project=$(jq -r .projectId "$CLI_PAYLOAD")
    checkout=$(jq -r .checkoutId "$CLI_PAYLOAD")
    [[ "$CLI_MODE" != wrongtarget ]] || checkout=another-checkout
    jq -cn --arg project "$project" --arg checkout "$checkout" --arg state "$state" --arg outcome "$outcome" '{id:"op-123-1",projectId:$project,checkoutId:$checkout,sessionId:"s1",generation:1,state:$state,outcome:(if $outcome=="null" then null else $outcome end),steps:[{id:"editor",status:"observed"},(if $outcome=="observed" then {id:"terminal",status:"observed"} else {id:"terminal",status:"failed",code:"TOOL_MISSING"} end)],error:null}' ;;
  'shell summon') echo ok ;;
  'aranea.projects.capture captureSnapshot')
    if [[ "$CLI_MODE" == details ]]; then
      jq -cn --arg id "$CLI_PROJECT" '{opened:true,projectId:$id,ui:null}'
    else echo '{"opened":true,"section":"appearance","ui":null}'; fi ;;
  *) echo 'unexpected IPC' >&2; exit 1 ;;
esac
FAKE
chmod +x "$ARANEA_TEST_SANDBOX/bin/omarchy-shell"
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
cli="$repo_root/scripts/aranea"
events="$ARANEA_TEST_SANDBOX/events"
# Assert authoritative exit status and every public envelope.
run_cli() {
  local expected=$1 actual=0
  shift
  "$cli" "$@" --json >"$events" 2>"$ARANEA_TEST_SANDBOX/diagnostics" || actual=$?
  [[ "$actual" == "$expected" ]] || {
    echo "Expected exit $expected, got $actual: $*"
    cat "$events" "$ARANEA_TEST_SANDBOX/diagnostics"
    exit 1
  }
  jq -se 'length>0 and all(.[]; .schema==1 and has("timestamp") and has("operation")) and last.event=="completed"' "$events" >/dev/null
}
# Missing entry point should fail this initial contract.
run_cli 0 capabilities
jq -se 'last.data.operations | any(.[]; .name=="projects.open" and .arguments.checkout.type=="string")' "$events" >/dev/null
run_cli 0 projects roots add "$ARANEA_TEST_SANDBOX"
run_cli 0 projects register --path "$checkout"
project=$(jq -r 'select(.event=="completed") | .data.state.projects[0].id' "$events")
checkout_id=$(jq -r 'select(.event=="completed") | .data.state.projects[0].lastCheckoutId' "$events")
export CLI_PROJECT="$project"
run_cli 1 projects register --path "$ARANEA_TEST_SANDBOX/vanished-candidate"
run_cli 0 projects list
jq -se 'last.data.projects|length==1' "$events" >/dev/null
run_cli 0 projects inspect "$project"
for reply in empty malformed nonobject nonconforming badrefusal; do
  before=$(jq -s 'map(select(.[1]=="request"))|length' "$CLI_CALLS" 2>/dev/null || echo 0)
  CLI_MODE="$reply" run_cli 1 projects open "$project"
  jq -se 'last.code=="OWNER_UNAVAILABLE" and (last.message|contains("may have been accepted")) and (last.data.recovery|contains("Inspect owner state before any new submission")) and any(.[];.event=="recovery" and .code=="OWNER_UNAVAILABLE" and (.message|length>0))' "$events" >/dev/null || {
    echo "Indeterminate $reply reply lost safe recovery"
    exit 1
  }
  [[ $(jq -s 'map(select(.[1]=="request"))|length' "$CLI_CALLS") == $((before + 1)) ]]
done
# Empty/nonobject error translation must preserve nonempty fallback fields.
for response in '' null '[]' '{"error":{"code":"","message":"","recovery":""}}'; do
  actual=0
  bash -c 'set -euo pipefail; source "$1/scripts/lib/json-events.sh"; source "$1/scripts/lib/projects-cli.sh"; cli_json=true; cli_operation=fixture; cli_operation_id=""; projects_cli_internal_error "$2"' bash "$repo_root" "$response" >"$events" 2>"$ARANEA_TEST_SANDBOX/diagnostics" || actual=$?
  [[ "$actual" == 1 ]]
  jq -se 'last.code=="OWNER_UNAVAILABLE" and (last.message|length>0) and (last.data.recovery|length>0)' "$events" >/dev/null
done
run_cli 1 projects open "$project"
jq -se 'last.data.outcome=="partial" and last.operationId=="op-123-1"' "$events" >/dev/null
jq -se --arg p "$project" --arg c "$checkout_id" 'map(select(.[1]=="request")) | (last[2]|fromjson)=={projectId:$p,checkoutId:$c,separate:false,useCurrentWorkspace:false}' "$CLI_CALLS" >/dev/null
for args in 'open missing' "open $project --checkout missing" "open $project --separate --use-current-workspace" "open $project --retry-role editor --new-window terminal" "open $project --retry-role editor --reobserve-role terminal" "open $project --new-window editor --reobserve-role terminal" "open $project --reobserve-role invalid" "configure $project --workspace weird" "configure $project --editor bash" "relocate $project --checkout missing --path /tmp" 'roots remove missing' 'discover --root missing' 'operation invalid' 'open'; do
  before=$(wc -l <"$CLI_CALLS")
  read -r -a words <<<"$args"
  run_cli 2 projects "${words[@]}"
  [[ $(wc -l <"$CLI_CALLS") == "$before" ]]
done
# shellcheck disable=SC2016 # Literal injection-looking data must remain inert.
run_cli 0 projects configure "$project" --name 'Name " ; $(touch nope)' --editor code --terminal kitty --workspace current
run_cli 0 projects ignore --path "$checkout"
run_cli 0 projects ignored
run_cli 0 projects unignore --path "$checkout"
run_cli 0 projects discover
run_cli 0 desktop status
run_cli 1 projects details "$project"
jq -se 'last.code=="DETAILS_UNCONFIRMED" and last.data.accepted' "$events" >/dev/null
CLI_MODE=details run_cli 0 projects details "$project"
jq -se --arg id "$project" 'any(.[]; .[0:3]==["shell","summon","araneadev.projects"] and (.[3]|fromjson).projectId==$id)' "$CLI_CALLS" >/dev/null
CLI_MODE=compositor run_cli 1 projects open "$project"
jq -se 'last.code=="COMPOSITOR_UNAVAILABLE"' "$events" >/dev/null
CLI_MODE=choice run_cli 3 projects open "$project"
CLI_MODE=wrongtarget run_cli 1 projects open "$project"
jq -se 'last.code=="OPERATION_LOST"' "$events" >/dev/null
CLI_MODE=observed run_cli 0 projects operation op-123-1
rm -f "$CLI_COUNT"
ready_before=$(jq -s 'map(select(.[1]=="request"))|length' "$CLI_CALLS")
CLI_MODE=ready run_cli 0 projects open "$project" --checkout "$checkout_id" --new-window editor
jq -se 'last.data.outcome=="observed"' "$events" >/dev/null
[[ $(jq -s 'map(select(.[1]=="request"))|length' "$CLI_CALLS") == $((ready_before + 2)) ]]
rm -f "$CLI_COUNT"
CLI_MODE=lost run_cli 1 projects open "$project"
jq -se 'last.code=="OPERATION_LOST"' "$events" >/dev/null
CLI_MODE=lost run_cli 1 projects operation op-123-1
jq -se 'last.code=="OPERATION_LOST"' "$events" >/dev/null
# The owner's stale project selection cannot override the fresh registry default.
git -C "$checkout" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm initial
alternate="$ARANEA_TEST_SANDBOX/alternate"
git -C "$checkout" worktree add -q -b alternate "$alternate"
# An explicitly scanned anchor retains its unregistered external sibling for review.
run_cli 0 projects roots add "$checkout"
review_root=$(jq -r --arg path "$checkout" 'select(.event=="completed")|.data.state.roots[]|select(.path==$path)|.id' "$events")
run_cli 0 projects discover --root "$review_root"
jq -se --arg anchor "$checkout" --arg sibling "$alternate" 'any(.[];.event=="step" and .data.candidate.path==$anchor and any(.data.candidate.checkouts[];.path==$sibling))' "$events" >/dev/null || {
  echo 'Anchor registration hid its unregistered external sibling on refresh' >&2
  exit 1
}
run_cli 0 projects inspect "$project"
jq -se 'last.data.project.checkouts|length==1' "$events" >/dev/null
run_cli 0 projects register --path "$alternate"
alternate_id=$(jq -r --arg path "$alternate" 'select(.event=="completed") | .data.state.projects[0].checkouts[]|select(.path==$path)|.id' "$events")
run_cli 0 projects discover --root "$review_root"
jq -se 'all(.[];.event!="step" or .data.candidate==null)' "$events" >/dev/null
run_cli 0 projects roots remove "$review_root"
jq -cn --arg project "$project" --arg checkout "$alternate_id" '{action:"select-checkout",args:{projectId:$project,checkoutId:$checkout}}' | "$repo_root/scripts/aranea-project-store" mutate >/dev/null
CLI_MODE=observed run_cli 0 projects open "$project" --separate
jq -se --arg checkout "$alternate_id" 'map(select(.[1]=="request"))|last|.[2]|fromjson|.checkoutId==$checkout and .separate==true' "$CLI_CALLS" >/dev/null
jq -cn --arg project "$project" --arg checkout "$checkout_id" '{action:"select-checkout",args:{projectId:$project,checkoutId:$checkout}}' | "$repo_root/scripts/aranea-project-store" mutate >/dev/null
CLI_MODE=observed run_cli 0 projects open "$project" --use-current-workspace --retry-role terminal
jq -se 'map(select(.[1]=="request"))|last|.[2]|fromjson|.useCurrentWorkspace==true and .retryRole=="terminal" and .newWindowRole==null' "$CLI_CALLS" >/dev/null
run_cli 0 projects relocate "$project" --checkout "$checkout_id" --path "$checkout"
mv "$checkout" "${checkout}.gone"
run_cli 1 projects open "$project"
jq -se 'last.code=="CHECKOUT_MISSING"' "$events" >/dev/null
run_cli 0 projects remove "$project"
root=$("$repo_root/scripts/aranea-project-store" snapshot | jq -r '.state.roots[0].id')
run_cli 0 projects roots remove "$root"
"$cli" projects list >"$events"
[[ -s "$events" && $(head -c 1 "$events") != '{' ]]
# Accepted owner work is never resubmitted after transport loss or observer exit.
# Re-register after removal for independent observer scenarios.
run_cli 0 projects register --path "${checkout}.gone"
project=$(jq -r 'select(.event=="completed") | .data.state.projects[0].id' "$events")
CLI_MODE=disconnected run_cli 1 projects open "$project"
jq -se 'last.code=="OWNER_UNAVAILABLE" and last.operationId=="op-123-1"' "$events" >/dev/null
before=$(jq -s 'map(select(.[1]=="request"))|length' "$CLI_CALLS")
CLI_MODE=pending "$cli" projects open "$project" --json >"$events" 2>"$ARANEA_TEST_SANDBOX/diagnostics" &
observer=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  if jq -se 'any(.[];.event=="step" and .id=="editor" and .status=="observed")' "$events" >/dev/null 2>&1; then break; fi
  sleep 0.05
done
jq -se 'any(.[];.event=="step" and .id=="editor" and .status=="observed")' "$events" >/dev/null
sleep 0.5
kill -TERM "$observer"
actual=0
wait "$observer" || actual=$?
[[ "$actual" == 1 ]]
jq -se 'last.code=="OBSERVER_CANCELLED" and ([.[]|select(.event=="step" and .id=="editor")]|length)==1' "$events" >/dev/null
[[ $(jq -s 'map(select(.[1]=="request"))|length' "$CLI_CALLS") == $((before + 1)) ]]
# Host dependency absence remains discoverable and unrelated reads still work.
full_path=$PATH
mkdir -p "$ARANEA_TEST_SANDBOX/deps"
for program in bash dirname mkdir touch jq date timeout flock realpath mktemp mv cat rm setsid sleep head tail wc git; do
  ln -s "$(command -v "$program")" "$ARANEA_TEST_SANDBOX/deps/$program"
done
ln -s "$ARANEA_TEST_SANDBOX/bin/omarchy-shell" "$ARANEA_TEST_SANDBOX/deps/omarchy-shell"
rm "$ARANEA_TEST_SANDBOX/deps/git"
PATH="$ARANEA_TEST_SANDBOX/deps" run_cli 0 projects list
PATH="$ARANEA_TEST_SANDBOX/deps" run_cli 4 projects open "$project"
PATH="$ARANEA_TEST_SANDBOX/deps" run_cli 0 capabilities
jq -se 'last.data.availability.dependencies.git==false' "$events" >/dev/null
rm "$ARANEA_TEST_SANDBOX/deps/flock"
PATH="$ARANEA_TEST_SANDBOX/deps" run_cli 4 projects list
CLI_MODE=observed PATH="$ARANEA_TEST_SANDBOX/deps" run_cli 0 projects operation op-123-1
rm "$ARANEA_TEST_SANDBOX/deps/jq"
actual=0
PATH="$ARANEA_TEST_SANDBOX/deps" "$cli" capabilities --json >"$events" 2>"$ARANEA_TEST_SANDBOX/diagnostics" || actual=$?
[[ "$actual" == 4 ]]
jq -se 'last.schema==1 and last.code=="DEPENDENCY_MISSING" and last.data.dependency=="jq"' "$events" >/dev/null
jq -se 'last.timestamp|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") and .!="1970-01-01T00:00:00Z"' "$events" >/dev/null || {
  echo 'Missing jq discarded a functioning UTC clock'
  exit 1
}
rm "$ARANEA_TEST_SANDBOX/deps/date"
cat >"$ARANEA_TEST_SANDBOX/deps/date" <<'DATE'
#!/usr/bin/env bash
printf 'invalid " timestamp\n'
DATE
chmod +x "$ARANEA_TEST_SANDBOX/deps/date"
actual=0
PATH="$ARANEA_TEST_SANDBOX/deps" "$cli" capabilities --json >"$events" 2>"$ARANEA_TEST_SANDBOX/diagnostics" || actual=$?
[[ "$actual" == 4 ]]
jq -se 'last.timestamp==null and last.data.timestampAvailable==false and last.code=="DEPENDENCY_MISSING"' "$events" >/dev/null
rm "$ARANEA_TEST_SANDBOX/deps/date"
actual=0
PATH="$ARANEA_TEST_SANDBOX/deps" "$cli" capabilities --json >"$events" 2>"$ARANEA_TEST_SANDBOX/diagnostics" || actual=$?
[[ "$actual" == 4 ]]
jq -se 'last.timestamp==null and last.data.timestampAvailable==false' "$events" >/dev/null
export PATH="$full_path"
# A pending accepted operation times out locally, without another submission.
before=$(jq -s 'map(select(.[1]=="request"))|length' "$CLI_CALLS")
CLI_MODE=pending run_cli 1 projects open "$project"
jq -se 'last.code=="OBSERVATION_TIMEOUT" and last.operationId=="op-123-1" and last.data.outcome=="partial"' "$events" >/dev/null
[[ $(jq -s 'map(select(.[1]=="request"))|length' "$CLI_CALLS") == $((before + 1)) ]]
[[ ! -e "$repo_root/nope" ]]
echo 'projects CLI contract passed'
