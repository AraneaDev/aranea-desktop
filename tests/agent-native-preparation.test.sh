#!/usr/bin/env bash
# Native preparation keeps fingerprint identity while avoiding repeated history parsing.
set -euo pipefail
export LC_ALL=C
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
# shellcheck source=scripts/lib/agent-activity.sh
source "$repo_root/scripts/lib/agent-activity.sh"
mkdir -p "$TMPDIR/checkout"
ln -s "$TMPDIR/checkout" "$TMPDIR/alias"
jq -n --arg cwd "$TMPDIR/alias" --argjson now "$(date +%s)" --argjson monotonic "$(cut -d. -f1 /proc/uptime)" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" -f "$repo_root/tests/fixtures/agent-history.jq" >"$TMPDIR/dense"
jq --arg cwd "$TMPDIR/alias" '{action:"report",args:{schemaVersion:1,eventId:"event:colon",provider:"claude",providerSessionId:.sessions[0].providerSessionId,producerEpoch:.sessions[0].producerEpoch,sequence:513,taskId:.tasks[0].taskId,kind:"snapshot",payload:{cwd:$cwd,reportedState:"working",description:"Unicode λ and quotes: \"task\""}},nativeMetadata:.sessions[0].nativeMetadata}' "$TMPDIR/dense" >"$TMPDIR/normalized"
normalized=$(cat "$TMPDIR/normalized")
# Exercise the actual fully validated fingerprint projection.
fingerprint() {
  command jq -Sce --arg hash "" --arg operation normalized-fingerprint --arg activity_provider "$1" --argjson activity_context '[{}]' --argjson activity_projects '[{"projects":[]}]' --argjson activity_request '[null]' -f "$repo_root/scripts/lib/agent-activity.jq"
}
compact=$(fingerprint claude <<<"$normalized")
# Preserve every fingerprint preimage byte, including the final LF used by SHA.
jq -Sc 'del(.nativeMetadata)' <<<"$normalized" >"$TMPDIR/expected"
printf '%s\n' "$compact" >"$TMPDIR/actual"
cmp "$TMPDIR/expected" "$TMPDIR/actual"
if fingerprint codex <<<"$normalized" >"$TMPDIR/invalid" 2>/dev/null; then exit 1; fi
[[ ! -s "$TMPDIR/invalid" ]]
if jq '.nativeMetadata.callbackOwners[0].key="invalid"' <<<"$normalized" | fingerprint claude >"$TMPDIR/invalid" 2>/dev/null; then exit 1; fi
[[ ! -s "$TMPDIR/invalid" ]]
# Count bytes fed to jq, never record payloads. Dense metadata should only need
# one parse to apply a canonical path; scalar inspection uses the compact input.
jq() {
  local input
  input=$(cat)
  printf '%s\n' "${#input}" >>"$TMPDIR/parse-sizes"
  command jq "$@" <<<"$input"
}
prepared=$(agent_activity_prepare "$normalized" "$compact")
unset -f jq
jq -e --arg cwd "$TMPDIR/checkout" --argjson original "$compact" --slurpfile normalized "$TMPDIR/normalized" '.args.payload.cwd == $cwd and (.args|del(.payload.cwd)) == ($original.args|del(.payload.cwd)) and .nativeMetadata == $normalized[0].nativeMetadata' <<<"$prepared" >/dev/null
parsed=$(awk '{n+=$1} END {print n}' "$TMPDIR/parse-sizes")
if ((parsed >= 2 * ${#normalized})); then
  printf 'FAIL compact preparation reparsed dense history: %s bytes for %s-byte input\n' "$parsed" "${#normalized}"
  exit 1
fi
# One-argument public callers retain the same canonicalization result.
legacy=$(agent_activity_prepare "$normalized")
[[ "$legacy" == "$prepared" ]]
echo 'PASS native fingerprint bytes, full mapping validation and compact path preparation'
