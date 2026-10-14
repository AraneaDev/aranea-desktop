#!/usr/bin/env bash
# Actual public collector observations from a private mixed/conflicted checkout.
set -euo pipefail
repo_root="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
repo="$ARANEA_TEST_SANDBOX/repo"
git init -q -b main "$repo"
git -C "$repo" config user.name Tests
git -C "$repo" config user.email tests@example.invalid
printf 'initial\n' >"$repo/conflict.txt"
printf 'initial\n' >"$repo/mixed.txt"
git -C "$repo" add .
git -C "$repo" commit -qm initial
git -C "$repo" checkout -qb side
printf 'side\n' >"$repo/conflict.txt"
git -C "$repo" commit -qam side
git -C "$repo" checkout -q main
printf 'main\n' >"$repo/conflict.txt"
git -C "$repo" commit -qam main
if git -C "$repo" merge side >/dev/null 2>&1; then exit 1; fi
printf 'staged\n' >>"$repo/mixed.txt"
git -C "$repo" add mixed.txt
printf 'unstaged\n' >>"$repo/mixed.txt"
unusual=$'untracked \t\n <>&" $(touch NEVER)'
printf 'new\n' >"$repo/$unusual"
git -C "$repo" branch local-base
git -C "$repo" branch --set-upstream-to=local-base >/dev/null
git -C "$repo" branch -D local-base >/dev/null
jq -cn --arg path "$repo" '{action:"register",args:{paths:[$path]}}' | "$repo_root/scripts/aranea-project-store" mutate >"$TMPDIR/registration.json"
project=$(jq -r '.state.projects[0].id' "$TMPDIR/registration.json")
checkout=$(jq -r '.state.projects[0].checkouts[0].id' "$TMPDIR/registration.json")
"$repo_root/scripts/aranea-project-git-state" --project "$project" --checkout "$checkout" --json >"$TMPDIR/observation.json"
jq -e '.ok and .data.counts == {staged:2,unstaged:2,untracked:1,conflicts:1} and .data.upstream == "local-base" and .data.ahead == null and .data.behind == null' "$TMPDIR/observation.json" >/dev/null
jq -n --slurpfile registration "$TMPDIR/registration.json" --slurpfile response "$TMPDIR/observation.json" '{project:$registration[0].state.projects[0],response:$response[0]}'
[[ ! -e "$repo/NEVER" && ! -e NEVER ]]
