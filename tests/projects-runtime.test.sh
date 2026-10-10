#!/usr/bin/env bash
# Detached launches and fresh process identity checks run only fake supported tools.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
launcher="$repo_root/scripts/aranea-project-launch"
identity="$repo_root/scripts/aranea-project-identity"
[[ -x "$launcher" && -x "$identity" ]] || {
  echo 'Expected detached launch and identity helpers'
  exit 1
}
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/checkout \$(touch hostile); space"
checkout="$ARANEA_TEST_SANDBOX/checkout \$(touch hostile); space"
cat >"$ARANEA_TEST_SANDBOX/bin/kitty" <<'APP'
#!/usr/bin/env bash
printf '%s\n' "$PWD" > "$ARANEA_TEST_SANDBOX/app-cwd"
printf '%s\n' "$@" > "$ARANEA_TEST_SANDBOX/app-args"
setsid sleep 15 &
printf '%s\n' "$!" > "$ARANEA_TEST_SANDBOX/isolated-child"
sleep 15
APP
chmod +x "$ARANEA_TEST_SANDBOX/bin/kitty"
cat >"$checkout/kitty" <<'HOSTILE'
#!/usr/bin/env bash
printf invoked > "$ARANEA_TEST_SANDBOX/repository-script-executed"
exec /usr/bin/sleep 15
HOSTILE
chmod +x "$checkout/kitty"
export PATH=".:$checkout:$ARANEA_TEST_SANDBOX/bin:$PATH"
cd -- "$checkout"
request=$(jq -cn --arg cwd "$checkout" '{cwd:$cwd,argv:["kitty","--class","dev.aranea.fixture","--directory",$cwd]}')
response=$(printf '%s\n' "$request" | "$launcher")
jq -e '.ok and .status == "accepted" and (.identity.pid > 0) and (.identity.startTime | test("^[0-9]+$"))' <<<"$response" >/dev/null
pid=$(jq -r .identity.pid <<<"$response")
[[ ! -e "$ARANEA_TEST_SANDBOX/repository-script-executed" ]] || {
  echo 'Ordinary Open executed a checkout-local application from PATH'
  kill -- "-$pid" 2>/dev/null || true
  exit 1
}
# Cleanup targets only the isolated new session whose leader the helper returned.
sandbox_on_exit "kill -- -$pid 2>/dev/null || true"
# Stop the fake child's independently detached session before removing scratch paths.
cleanup_child() {
  local isolated_child
  if [[ -f "$ARANEA_TEST_SANDBOX/isolated-child" ]]; then
    read -r isolated_child <"$ARANEA_TEST_SANDBOX/isolated-child"
    [[ "$isolated_child" =~ ^[1-9][0-9]*$ ]] && kill "$isolated_child" 2>/dev/null || true
  fi
}
sandbox_on_exit cleanup_child
for ((i = 0; i < 50; i++)); do
  [[ -f "$ARANEA_TEST_SANDBOX/app-cwd" ]] && break
  sleep 0.02
done
[[ $(<"$ARANEA_TEST_SANDBOX/app-cwd") == "$checkout" ]]
[[ $(sed -n '4p' "$ARANEA_TEST_SANDBOX/app-args") == "$checkout" ]]
[[ ! -e "$checkout/hostile" ]]
kill -0 "$pid" # survives helper exit; application is not owned by Quickshell
query=$(jq -cn --argjson launch "$(jq .identity <<<"$response")" --argjson pid "$pid" '{launch:$launch,pid:$pid}')
proof=$(printf '%s\n' "$query" | "$identity")
jq -e '.ok and .verified and (.processes | length >= 3) and (.closed | not)' <<<"$proof" >/dev/null || {
  echo 'Expected proof to retain every live descendant, including separate sessions'
  exit 1
}
child=$(jq -r --argjson pid "$pid" '[.processes[] | select(.pid != $pid)][0].pid' <<<"$proof")
child_query=$(jq --argjson pid "$child" '.pid=$pid' <<<"$query")
child_proof=$(printf '%s\n' "$child_query" | "$identity")
jq -e '.verified' <<<"$child_proof" >/dev/null
known=$(jq .processes <<<"$proof")
query=$(jq --argjson known "$known" '.known=$known' <<<"$query")
kill "$pid"
sleep 0.02
remaining=$(printf '%s\n' "$query" | "$identity")
jq -e '(.closed | not) and (.processes | length >= 1)' <<<"$remaining" >/dev/null
bad=$(jq '.launch.startTime = "0"' <<<"$query" | "$identity")
jq -e '.ok and (.verified | not)' <<<"$bad" >/dev/null
unrelated=$(jq --argjson pid "$$" '.pid = $pid' <<<"$query" | "$identity")
jq -e '.ok and (.verified | not)' <<<"$unrelated" >/dev/null
rc=0
invalid=$(jq '.argv[0] = "sh"' <<<"$request" | "$launcher") || rc=$?
[[ $rc != 0 ]]
jq -e '.ok == false and .code == "INVALID_LAUNCH"' <<<"$invalid" >/dev/null
while IFS= read -r owned_pid; do kill "$owned_pid" 2>/dev/null || true; done < <(jq -r '.[].pid' <<<"$known")
kill -- "-$pid" 2>/dev/null || true
for ((i = 0; i < 50; i++)); do
  proof=$(printf '%s\n' "$query" | "$identity")
  jq -e '.closed' <<<"$proof" >/dev/null && break
  sleep 0.02
done
jq -e '.closed and (.verified | not)' <<<"$proof" >/dev/null
# Absolute PATH directories cannot bypass canonical checkout-target rejection.
mv -- "$ARANEA_TEST_SANDBOX/bin/kitty" "$ARANEA_TEST_SANDBOX/bin/trusted-kitty"
ln -s "$checkout/kitty" "$ARANEA_TEST_SANDBOX/bin/kitty"
rc=0
rejected=$(printf '%s\n' "$request" | "$launcher") || rc=$?
[[ $rc != 0 ]]
jq -e '.code == "TOOL_MISSING" and (.ok | not)' <<<"$rejected" >/dev/null
[[ ! -e "$ARANEA_TEST_SANDBOX/repository-script-executed" ]]
rm -- "$ARANEA_TEST_SANDBOX/bin/kitty"
mv -- "$ARANEA_TEST_SANDBOX/bin/trusted-kitty" "$ARANEA_TEST_SANDBOX/bin/kitty"
cp -- "$checkout/kitty" "$checkout/nvim"
ln -s "$checkout/nvim" "$ARANEA_TEST_SANDBOX/bin/nvim"
editor_request=$(jq '.argv += ["nvim","--",.cwd]' <<<"$request")
rc=0
rejected=$(printf '%s\n' "$editor_request" | "$launcher") || rc=$?
[[ $rc != 0 ]]
jq -e '.code == "TOOL_MISSING" and (.ok | not)' <<<"$rejected" >/dev/null
[[ ! -e "$ARANEA_TEST_SANDBOX/repository-script-executed" ]]
echo 'detached process and identity contract passed'
