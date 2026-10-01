#!/usr/bin/env bash
# Contract for tools/upstream-drift against an offline fake upstream: newest
# stable tag resolution, fork and platform statuses, the JSON and Markdown
# reports, --diff and --to, exit codes, cache reuse, offline behaviour and a
# pin that upstream does not have.
# shellcheck disable=SC2016 # expected Markdown and subjects hold literal backticks
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

upstream="$ARANEA_TEST_SANDBOX/upstream"
aranea="$ARANEA_TEST_SANDBOX/aranea"
cache="$XDG_CACHE_HOME/aranea/upstream-omarchy"
drift="$aranea/tools/upstream-drift"

# Runs git in the fake upstream with a fixed identity and no signing.
upstream_git() {
  git -C "$upstream" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c tag.gpgsign=false "$@"
}

# Appends LINE to upstream FILE and commits it with SUBJECT.
upstream_commit() {
  printf '%s\n' "$2" >>"$upstream/$1"
  upstream_git add -A
  upstream_git commit -q -m "$3"
}

# Prints the exit status of the given command, discarding its output.
exit_code() {
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  printf '%s\n' "$status"
}

# --- fake upstream: v1.0.0, then bar/Commons/unwatched changes, v1.1.0, then a
# pre-release that must never be picked as the newest target.
mkdir -p "$upstream"/shell/{plugins/bar,plugins/lock,plugins/panels/audio,Commons,Ui,services} "$upstream/docs"
printf 'bar\n' >"$upstream/shell/plugins/bar/Bar.qml"
printf 'audio\n' >"$upstream/shell/plugins/panels/audio/Panel.qml"
printf 'lock\n' >"$upstream/shell/plugins/lock/Lock.qml"
printf 'util\n' >"$upstream/shell/Commons/Util.js"
printf 'ui\n' >"$upstream/shell/Ui/Panel.qml"
printf 'svc\n' >"$upstream/shell/services/Registry.qml"
printf 'shell\n' >"$upstream/shell/shell.qml"
printf 'docs\n' >"$upstream/docs/README.md"
upstream_git init -q -b master
upstream_git add -A
upstream_git commit -q -m 'Initial shell'
upstream_git tag v1.0.0
upstream_commit shell/plugins/bar/Bar.qml spacing 'Fix "bar" `spacing`'
head -c 300000 /dev/zero | tr '\0' x | fold -w 100 >"$upstream/shell/plugins/bar/big.txt"
upstream_git add -A
upstream_git commit -q -m 'Add a large bar asset'
upstream_commit shell/Commons/Util.js rework 'Rework commons util'
upstream_commit docs/README.md more 'Unrelated docs change'
upstream_git tag v1.1.0
upstream_commit shell/plugins/lock/Lock.qml beta 'Beta lock change'
upstream_git tag v1.2.0-beta1
# A release cut on a side branch from v1.0.0 that backports the bar fix, the
# way Omarchy tags releases: v1.0.1 is not an ancestor of v1.1.0.
upstream_git switch -q -c v1-0-1 v1.0.0
upstream_git cherry-pick -x "$(upstream_git log --format=%H --grep='Fix "bar"' master)" >/dev/null
upstream_git tag v1.0.1
upstream_git switch -q master

# --- fake Aranea checkout: bar and lock forks, a fork with no upstream, and a
# plugin that is not a fork.
mkdir -p "$aranea/tools"
cp "$repo_root/tools/upstream-drift" "$drift"
printf 'v1.0.0\n' >"$aranea/.omarchy-version"
for plugin in bar lock ghost; do
  mkdir -p "$aranea/plugins/araneadev.$plugin"
  printf '{"id":"araneadev.%s","omarchy":{"clonedFrom":"omarchy.%s"}}\n' "$plugin" "$plugin" \
    >"$aranea/plugins/araneadev.$plugin/manifest.json"
done
mkdir -p "$aranea/plugins/araneadev.health"
printf '{"id":"araneadev.health"}\n' >"$aranea/plugins/araneadev.health/manifest.json"
export ARANEA_UPSTREAM_REPO="file://$upstream"

# --- usage
[[ "$(exit_code "$drift" --bogus)" == 2 ]]
[[ "$(exit_code "$drift" --to)" == 2 ]]

# --- JSON report against the newest stable tag
json="$("$drift" --json)"
jq -e '.schema == 1 and .base == "v1.0.0" and .target == "v1.1.0" and .drift == true' <<<"$json" >/dev/null
jq -e '[.paths[] | .plugin // .upstream] == ["araneadev.bar", "araneadev.ghost", "araneadev.lock",
  "shell/Commons", "shell/Ui", "shell/services", "shell/shell.qml"]' <<<"$json" >/dev/null
jq -e '[.paths[].kind] == ["fork", "fork", "fork", "platform", "platform", "platform", "platform"]' <<<"$json" >/dev/null
jq -e '.paths[] | select(.plugin == "araneadev.bar")
  | .status == "changed" and .upstream == "shell/plugins/bar" and (.commits | length) == 2
    and .stat.files == 2 and .stat.insertions > 3000 and (has("diff") | not)' <<<"$json" >/dev/null
jq -e '.paths[] | select(.plugin == "araneadev.bar") | any(.commits[]; .subject == "Fix \"bar\" `spacing`")' <<<"$json" >/dev/null
jq -e '.paths[] | select(.plugin == "araneadev.bar") | all(.commits[]; (.hash | length) >= 7 and (.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")))' <<<"$json" >/dev/null
jq -e '.paths[] | select(.plugin == "araneadev.lock") | .status == "unchanged" and .commits == [] and .stat == null' <<<"$json" >/dev/null
jq -e '.paths[] | select(.plugin == "araneadev.ghost") | .status == "missing-upstream" and .upstream == "shell/plugins/ghost"' <<<"$json" >/dev/null
jq -e '.paths[] | select(.upstream == "shell/Commons")
  | .kind == "platform" and (has("plugin") | not) and .status == "changed" and [.commits[].subject] == ["Rework commons util"]' <<<"$json" >/dev/null
jq -e '[.paths[] | select(.kind == "platform" and .upstream != "shell/Commons") | .status] | all(. == "unchanged")' <<<"$json" >/dev/null
jq -e '[.paths[].commits[].subject] | index("Unrelated docs change") == null' <<<"$json" >/dev/null
jq -e 'all(.paths[]; .plugin != "araneadev.health")' <<<"$json" >/dev/null

# --- --diff: full diff only on changed paths, larger than one argument allows
json="$("$drift" --json --diff)"
jq -e '.paths[] | select(.plugin == "araneadev.bar") | (.diff | contains("+spacing")) and (.diff | length) > 300000' <<<"$json" >/dev/null
jq -e '.paths[] | select(.plugin == "araneadev.lock") | has("diff") | not' <<<"$json" >/dev/null

# --- Markdown report
md="$("$drift")"
[[ "$(head -n1 <<<"$md")" == '# Upstream Omarchy drift: v1.0.0 → v1.1.0' ]]
grep -Fxq 'Changed: 1 of 3 forks, 1 of 4 platform paths.' <<<"$md"
grep -Fxq '## araneadev.bar (`shell/plugins/bar`)' <<<"$md"
grep -Fxq '## Platform: `shell/Commons`' <<<"$md"
grep -Fxq '2 files, +3001 -0' <<<"$md"
grep -Eq '^- `[0-9a-f]{7,}` [0-9-]{10} Fix "bar" `spacing`$' <<<"$md"
grep -Fxq 'Missing upstream: araneadev.ghost' <<<"$md"
grep -Fxq 'No upstream changes: araneadev.lock, shell/Ui, shell/services, shell/shell.qml' <<<"$md"
bar_line="$(grep -nF '## araneadev.bar' <<<"$md" | cut -d: -f1)"
commons_line="$(grep -nF '## Platform: `shell/Commons`' <<<"$md" | cut -d: -f1)"
((bar_line < commons_line))
if grep -Fq 'Unrelated' <<<"$md" || grep -Fq '````diff' <<<"$md"; then
  echo "Markdown lists an unwatched commit or a diff without --diff" >&2
  exit 1
fi
grep -Fxq '````diff' <<<"$("$drift" --diff)"

# --- --to: the pin itself is a drift-free report; an unknown ref is usage
json="$("$drift" --json --to v1.0.0)"
jq -e '.target == "v1.0.0" and .drift == false and all(.paths[]; .status != "changed")' <<<"$json" >/dev/null
grep -Fxq 'No upstream changes since v1.0.0.' <<<"$("$drift" --to v1.0.0)"
[[ "$(exit_code "$drift" --to nope)" == 2 ]]

# --- the cache is reused, and kept when upstream is unreachable
touch "$cache/aranea-test-marker"
"$drift" --json >/dev/null
test -f "$cache/aranea-test-marker"
mv "$upstream" "$upstream.away"
[[ "$(exit_code "$drift" --json)" == 1 ]]
test -f "$cache/aranea-test-marker"
mv "$upstream.away" "$upstream"

# --- a pin upstream does not have
printf 'v0.9.0\n' >"$aranea/.omarchy-version"
if "$drift" --json >/dev/null 2>"$ARANEA_TEST_SANDBOX/pin-error"; then
  echo "unknown pin unexpectedly succeeded" >&2
  exit 1
fi
[[ "$(exit_code "$drift" --json)" == 1 ]]
grep -Fq 'v0.9.0' "$ARANEA_TEST_SANDBOX/pin-error"
printf 'v1.0.0\n' >"$aranea/.omarchy-version"

# --- a cache pointing at another remote is replaced; an unreachable one fails
ARANEA_UPSTREAM_REPO="file://$ARANEA_TEST_SANDBOX/nowhere"
[[ "$(exit_code "$drift" --json)" == 1 ]]
test ! -e "$cache"
ARANEA_UPSTREAM_REPO="file://$upstream"
"$drift" --json >/dev/null
test -d "$cache"

# --- a backport already in the pin is not listed again; the stat agrees
printf 'v1.0.1\n' >"$aranea/.omarchy-version"
json="$("$drift" --json --to v1.1.0)"
jq -e '.paths[] | select(.plugin == "araneadev.bar")
  | [.commits[].subject] == ["Add a large bar asset"] and .stat.files == 1' <<<"$json" >/dev/null
printf 'v1.0.0\n' >"$aranea/.omarchy-version"

# --- parallel runs on a cold cache all succeed
rm -rf "$cache"
pids=()
for _ in 1 2 3 4 5; do
  "$drift" --json >/dev/null 2>&1 &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

# --- upstream issue references in Markdown point at the upstream repository,
# so a GitHub issue in this repository does not link them to its own issues.
upstream_commit shell/Commons/Util.js linked 'Keep overlays sharp (#13419)'
upstream_git tag v1.1.1
git config --global url."file://$upstream".insteadOf https://github.com/basecamp/omarchy
md="$(ARANEA_UPSTREAM_REPO=https://github.com/basecamp/omarchy "$drift")"
grep -Eq '^- `[0-9a-f]{7,}` [0-9-]{10} Keep overlays sharp \(basecamp/omarchy#13419\)$' <<<"$md"
json="$(ARANEA_UPSTREAM_REPO=https://github.com/basecamp/omarchy "$drift" --json)"
jq -e 'any(.paths[].commits[]; .subject == "Keep overlays sharp (#13419)")' <<<"$json" >/dev/null

# --- a panel plugin (omarchy.audio) lives under shell/plugins/panels upstream
mkdir -p "$aranea/plugins/araneadev.audio"
printf '{"id":"araneadev.audio","omarchy":{"clonedFrom":"omarchy.audio"}}\n' \
  >"$aranea/plugins/araneadev.audio/manifest.json"
json="$("$drift" --json)"
jq -e '.paths[] | select(.plugin == "araneadev.audio")
  | .upstream == "shell/plugins/panels/audio" and .status == "unchanged"' <<<"$json" >/dev/null
jq -e '.paths[] | select(.plugin == "araneadev.bar") | .upstream == "shell/plugins/bar"' <<<"$json" >/dev/null
jq -e '.paths[] | select(.plugin == "araneadev.ghost") | .upstream == "shell/plugins/ghost" and .status == "missing-upstream"' <<<"$json" >/dev/null
rm -rf "$aranea/plugins/araneadev.audio"

# --- the weekly workflow: least privilege, pinned checkout, one issue
workflow="$repo_root/.github/workflows/upstream-drift.yml"
test -f "$workflow"
grep -Fq 'workflow_dispatch:' "$workflow"
grep -Eq '^\s+- cron: ' "$workflow"
grep -Fq 'issues: write' "$workflow"
grep -Fq 'contents: read' "$workflow"
grep -Fq 'persist-credentials: false' "$workflow"
grep -Fq 'tools/upstream-drift --json' "$workflow"
grep -Fq -- '--label upstream-drift' "$workflow"
grep -Fq 'gh issue close' "$workflow"
if grep -Eq 'pull-requests:|contents: write' "$workflow"; then
  echo "upstream-drift workflow asks for more than it needs" >&2
  exit 1
fi
