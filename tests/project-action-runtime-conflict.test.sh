#!/usr/bin/env bash
# Concurrent configure cannot discard acceptance when readiness publication conflicts.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
backend="$repo_root/scripts/aranea-project-actions"
manager="$ARANEA_TEST_SANDBOX/manager"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo" "$manager"
for tool in systemd-run systemctl journalctl xdg-open; do ln -s "$repo_root/tests/fixtures/project-actions-manager.sh" "$ARANEA_TEST_SANDBOX/bin/$tool"; done
cat >"$ARANEA_TEST_SANDBOX/bin/curl" <<'CURL'
#!/bin/bash
touch "$ARANEA_TEST_SANDBOX/manager/probe-entered"
while [[ -e "$ARANEA_TEST_SANDBOX/manager/probe-hold" ]]; do sleep .01; done
exit 0
CURL
chmod +x "$ARANEA_TEST_SANDBOX/bin/curl"
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
git init -q "$ARANEA_TEST_SANDBOX/repo"
jq -cn --arg p "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
jq -cn --arg p "$project" '{projectId:$p,definition:{name:"Preview",kind:"service",argv:["printf","not executed"],cwdRelative:".",timeoutSeconds:null,previewUrl:"http://127.0.0.1:8181/"}}' >"$TMPDIR/config"
"$backend" configure <"$TMPDIR/config" >"$TMPDIR/configured"
action=$(jq -r '.state.definitions[0].id' "$TMPDIR/configured")
jq -cn --arg p "$project" --arg a "$action" '{projectId:$p,actionId:$a,requestId:"req-00000000-0000-4000-8000-000000000077"}' >"$TMPDIR/start"
touch "$manager/probe-hold"
"$backend" start <"$TMPDIR/start" >"$TMPDIR/response" &
started=$!
# shellcheck disable=SC2016
sandbox_on_exit 'rm -f "$manager/probe-hold"; wait "$started" 2>/dev/null || true'
for _ in {1..200}; do
  [[ ! -e "$manager/probe-entered" ]] || break
  sleep .01
done
[[ -e "$manager/probe-entered" ]]
jq --arg a "$action" '.definition.id=$a | .definition.name="Edited during probe"' "$TMPDIR/config" | "$backend" configure >"$TMPDIR/edited"
rm "$manager/probe-hold"
status=0
wait "$started" || status=$?
[[ $status == 1 ]]
jq -e '.ok==false and .error.code=="ACTION_CONFLICT" and .state.runs[0].processState=="running" and .state.requests[0].runId==.state.runs[0].id' "$TMPDIR/response" >/dev/null
jq --argjson status "$status" '{exit:$status,ok,error,hasRun:has("run"),runs:[.state.runs[]|{id,requestId,processState,submissionUnconfirmed}],requests:.state.requests}' "$TMPDIR/response"
[[ $(wc -l <"$manager/launches") == 1 ]]
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
jq -e '.run.id==.state.requests[0].runId and .run==.state.runs[0] and .run.definitionRevision==1 and .state.definitions[0].revision==2 and .run.readiness=="unknown"' "$TMPDIR/response" >/dev/null || {
  echo 'readiness conflict discarded accepted run evidence' >&2
  exit 1
}
# The original receipt still replays and does not launch again after configuration changed.
"$backend" start <"$TMPDIR/start" >"$TMPDIR/replayed"
jq -e --slurpfile original "$TMPDIR/response" '.run.id==$original[0].run.id and .run.definitionRevision==1' "$TMPDIR/replayed" >/dev/null
[[ $(wc -l <"$manager/launches") == 1 ]]
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
echo 'runtime readiness conflict: accepted evidence and exact replay retained'
