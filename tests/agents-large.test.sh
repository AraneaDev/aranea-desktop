#!/usr/bin/env bash
# Public activity JSON must stream beyond Linux's per-argument limit end to end.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
cli="$repo_root/scripts/aranea"
# 35 ordinary tasks exceed argv limits; public registration must still succeed.
jq -cn --arg cwd "$HOME" '{provider:"claude",providerSessionId:"large",producerEpoch:"epoch",tasks:[range(35)|{taskId:("t"+tostring),cwd:$cwd,reportedState:"finished",description:("x"*4000)}]}' >"$TMPDIR/register"
"$cli" agents register --json-input --json <"$TMPDIR/register" >"$TMPDIR/events"
jq -es 'last.schema==1 and last.data.outcome=="observed" and (last.data.state.tasks|length)==35' "$TMPDIR/events" >/dev/null
for command in list status; do
  "$cli" agents "$command" --json >"$TMPDIR/events"
  jq -es 'last.schema==1 and last.data.tasks==last.data.state.tasks and (last.data.tasks|length)==35' "$TMPDIR/events" >/dev/null
done
# One valid snapshot's blocker text alone can exceed a single OS argument.
jq -cn --arg cwd "$HOME" '{schemaVersion:1,eventId:"large-report",provider:"claude",providerSessionId:"large",producerEpoch:"epoch",sequence:1,taskId:"large-task",kind:"snapshot",payload:{cwd:$cwd,reportedState:"finished",description:("d"*4096),blockers:[range(32)|{blockerId:tostring,question:("q"*4096)}]}}' >"$TMPDIR/report"
"$cli" agents report --json-input --json <"$TMPDIR/report" >"$TMPDIR/events"
jq -es 'last.data.outcome=="observed" and (last.data.state.tasks|length)==36' "$TMPDIR/events" >/dev/null
"$cli" agents inspect large-task --json >"$TMPDIR/events"
jq -es 'last.schema==1 and (last.data.task.blockers|length)==32 and last.data.task.blockers[31].question==("q"*4096)' "$TMPDIR/events" >/dev/null
# A tiny committed mutation must emit its authoritative large success response.
"$cli" agents dismiss t0 --json >"$TMPDIR/events"
jq -es 'last.data.outcome=="observed" and (last.data.state.tasks|length)==35 and all(last.data.state.tasks[];.taskId!="t0")' "$TMPDIR/events" >/dev/null
"$cli" agents list --json >"$TMPDIR/events"
jq -es 'all(last.data.tasks[];.taskId!="t0")' "$TMPDIR/events" >/dev/null
echo 'PASS large public register/report/status/list/inspect and committed dismissal envelopes'
