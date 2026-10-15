#!/usr/bin/env bash
# Public detect resolves the exact checkout, reads only, and emits configure-ready drafts.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
cli="$repo_root/scripts/aranea"
backend="$repo_root/scripts/aranea-project-actions"
checkout="$ARANEA_TEST_SANDBOX/repo"
mkdir -p "$checkout"
git init -q "$checkout"
printf '{"scripts":{"test":"node --test","dev":"vite"}}\n' >"$checkout/package.json"
printf 'build:\n' >"$checkout/Makefile"
jq -cn --arg p "$checkout" '{action:"register",args:{paths:[$p]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/project"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/project")
checkout_id=$(jq -r '.state.projects[0].lastCheckoutId' "$TMPDIR/project")
# Run a public projects subcommand and capture its JSON stream.
call() { "$cli" projects "$@" --json >"$TMPDIR/result"; }

# Backend envelope with the default checkout resolved.
printf '{"projectId":"%s"}' "$project" | "$backend" detect >"$TMPDIR/backend"
jq -e --arg c "$checkout_id" '.ok and .state==null and .error==null and .checkoutId==$c and (.suggestions|length)==3' "$TMPDIR/backend" >/dev/null
# Unknown fields and malformed IDs are refused before any read.
status=0
printf '{"projectId":"%s","path":"/"}' "$project" | "$backend" detect >"$TMPDIR/refused" || status=$?
[[ $status == 1 ]] && jq -e '.error.code=="INVALID_REQUEST"' "$TMPDIR/refused" >/dev/null

# Public CLI, exact checkout.
call actions detect "$project" --checkout "$checkout_id"
jq -es '.[-1].status=="observed" and (.[-1].data.suggestions|map(.key)|sort)==["makefile:.:build","package.json:.:dev","package.json:.:test"]' "$TMPDIR/result" >/dev/null
# Every emitted definition is accepted unchanged by configure, and nothing ran.
jq -cs '.[-1].data.suggestions[].definition' "$TMPDIR/result" >"$TMPDIR/definitions"
while IFS= read -r definition; do
  printf '%s\n' "$definition" | "$cli" projects actions configure "$project" --json-input --json >"$TMPDIR/saved"
  jq -es '.[-1].status=="observed"' "$TMPDIR/saved" >/dev/null
done <"$TMPDIR/definitions"
call actions detect "$project"
jq -es '.[-1].data.suggestions|all(.alreadySaved)' "$TMPDIR/result" >/dev/null
[[ ! -e $ARANEA_TEST_SANDBOX/guard.log ]] || ! grep -q systemd-run "$ARANEA_TEST_SANDBOX/guard.log"

# Unknown project and changed checkout fail without fallback.
status=0
call actions detect p-00000000-0000-4000-8000-000000000099 2>/dev/null || status=$?
[[ $status == 1 ]] && jq -es '.[-1].code=="PROJECT_NOT_FOUND"' "$TMPDIR/result" >/dev/null
status=0
call actions detect "$project" --checkout c-00000000-0000-4000-8000-000000000099 2>/dev/null || status=$?
[[ $status == 1 ]] && jq -es '.[-1].code=="CHECKOUT_INVALID"' "$TMPDIR/result" >/dev/null
mv "$checkout" "$checkout.moved"
status=0
call actions detect "$project" 2>/dev/null || status=$?
[[ $status == 1 ]] && jq -es '.[-1].code=="CHECKOUT_INVALID"' "$TMPDIR/result" >/dev/null
mv "$checkout.moved" "$checkout"
# Usage errors.
status=0
call actions detect 2>/dev/null || status=$?
[[ $status == 2 ]]
status=0
call actions detect "$project" --request-id x 2>/dev/null || status=$?
[[ $status == 2 ]]

# Capabilities advertise the read-only contract and helper availability.
"$cli" capabilities --json >"$TMPDIR/caps"
jq -es '.[-1].data | (.projectActions.detect.readOnly==true) and (.projectActions.detect.limits.suggestions==100) and any(.operations[];.name=="projects.actions.detect") and (.availability.projectActions|has("detectJust") and has("detectToml"))' "$TMPDIR/caps" >/dev/null
echo 'project-actions-detect-cli: ok'
