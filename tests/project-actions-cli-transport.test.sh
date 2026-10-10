#!/usr/bin/env bash
# Malformed postacceptance transport must retain real durable intent and its ID.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
mkdir -p "$ARANEA_TEST_SANDBOX/bin" "$ARANEA_TEST_SANDBOX/repo" "$ARANEA_TEST_SANDBOX/manager" "$TMPDIR/scripts"
for tool in systemd-run systemctl journalctl curl xdg-open; do ln -s "$repo_root/tests/fixtures/project-actions-manager.sh" "$ARANEA_TEST_SANDBOX/bin/$tool"; done
export PATH="$ARANEA_TEST_SANDBOX/bin:$PATH"
git init -q "$ARANEA_TEST_SANDBOX/repo"
jq -cn --arg p "$ARANEA_TEST_SANDBOX/repo" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
printf '%s\n' '{"name":"Transport","kind":"command","argv":["printf"],"cwdRelative":".","previewUrl":null}' | "$repo_root/scripts/aranea" projects actions configure "$project" --json-input --json >"$TMPDIR/configured"
action=$(jq -rs '.[-1].data.state.definitions[0].id' "$TMPDIR/configured")
cp "$repo_root/scripts/aranea" "$TMPDIR/scripts/aranea"
ln -s "$repo_root/scripts/lib" "$TMPDIR/scripts/lib"
ln -s "$repo_root/scripts/aranea-project-action-store" "$TMPDIR/scripts/aranea-project-action-store"
export REAL_ACTION_BACKEND="$repo_root/scripts/aranea-project-actions"
cat >"$TMPDIR/scripts/aranea-project-actions" <<'WRAPPER'
#!/usr/bin/bash
# Keep actual backend effects/stores; only damage its final transport response.
"$REAL_ACTION_BACKEND" "$@" >"$TMPDIR/accepted-backend" || exit
printf '{malformed\n'
WRAPPER
chmod +x "$TMPDIR/scripts/aranea-project-actions"
status=0
"$TMPDIR/scripts/aranea" projects actions run "$project" "$action" --json >"$TMPDIR/events" 2>"$TMPDIR/expected-error" || status=$?
[[ $status == 1 ]]
failures=0
jq -es 'any(.[];.status=="accepted") and .[-1].status=="partial" and .[-1].code=="SUBMISSION_UNCONFIRMED" and .[-1].data.runId!=null' "$TMPDIR/events" >/dev/null || {
  echo 'malformed response discarded the accepted retained run ID' >&2
  failures=$((failures + 1))
}
run=$(jq -rs '[.[]|select(.status=="accepted")][0].data.runId' "$TMPDIR/events")
jq -e --arg r "$run" 'any(.runs[];.id==$r and .processState=="running")' "$ARANEA_STATE_ROOT/project-actions.json" >/dev/null
[[ $(wc -l <"$ARANEA_TEST_SANDBOX/manager/launches") == 1 ]]
"$repo_root/scripts/aranea" projects runs stop "$run" --json >"$TMPDIR/stopped"
# Restart acceptance still projects its original tuple if retention removes old history.
jq --arg r "$run" '.runs|=map(if .id==$r then .createdAt=0 | .updatedAt=0 else . end)' "$ARANEA_STATE_ROOT/project-actions.json" >"$TMPDIR/expired"
mv "$TMPDIR/expired" "$ARANEA_STATE_ROOT/project-actions.json"
"$repo_root/scripts/aranea" projects runs restart "$run" --json >"$TMPDIR/restarted"
jq -es --arg old "$run" 'any(.[];.status=="accepted") and .[-1].status=="observed" and .[-1].data.runId!=$old' "$TMPDIR/restarted" >/dev/null || {
  echo 'restart lost original tuple when terminal history was pruned' >&2
  failures=$((failures + 1))
}
restarted=$(jq -rs '.[-1].data.runId' "$TMPDIR/restarted")
"$repo_root/scripts/aranea" projects runs stop "$restarted" --json >"$TMPDIR/restarted-stop"
jq -e --arg old "$run" 'all(.runs[];.id!=$old)' "$ARANEA_STATE_ROOT/project-actions.json" >/dev/null
# Worker scratch is independent and eventually released by its native lease.
for _ in {1..100}; do
  if ! compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null; then break; fi
  sleep .01
done
if compgen -G "$TMPDIR/aranea-action-observer.*" >/dev/null; then
  echo "detached observer artifacts were not released" >&2
  exit 1
fi
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]

((failures == 0))
