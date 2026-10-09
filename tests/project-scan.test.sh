#!/usr/bin/env bash
# The private UI scan owns cancellation of CLI, discovery and slow Git descendants.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
scan="$repo_root/scripts/aranea-project-scan"
export ARANEA_STATE_ROOT="$XDG_STATE_HOME/aranea"
mkdir -p "$ARANEA_TEST_SANDBOX/repo"
git init -q "$ARANEA_TEST_SANDBOX/repo"
root_id=$("$repo_root/scripts/aranea-project-store" mutate <<<"$(jq -cn --arg path "$ARANEA_TEST_SANDBOX/repo" '{action:"root-add",args:{path:$path}}')" | jq -r '.state.roots[0].id')
# Invalid IDs never become path or shell syntax.
if "$scan" 'r-one; touch /tmp/scan-unsafe' </dev/null >"$ARANEA_TEST_SANDBOX/invalid" 2>&1; then exit 1; fi
# Normal complete scans emit the existing public JSONL events.
"$scan" "$root_id" < <(sleep 3) >"$ARANEA_TEST_SANDBOX/result"
jq -se 'any(.[];.event == "step" and .data.candidate.path != null) and .[-1].data.outcome == "observed"' "$ARANEA_TEST_SANDBOX/result" >/dev/null
mkdir -p "$ARANEA_TEST_SANDBOX/slow-bin"
real_git=$(command -v git)
export ARANEA_SCAN_REAL_GIT="$real_git"
cat >"$ARANEA_TEST_SANDBOX/slow-bin/git" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$$" >>"$ARANEA_TEST_SANDBOX/slow-pids"
# Both Git and its grandchild deliberately ignore TERM, requiring group escalation.
trap '' TERM
sleep 60 &
printf '%s\n' "$!" >>"$ARANEA_TEST_SANDBOX/slow-pids"
wait "$!"
exec "$ARANEA_SCAN_REAL_GIT" "$@"
STUB
chmod +x "$ARANEA_TEST_SANDBOX/slow-bin/git"
mkfifo "$ARANEA_TEST_SANDBOX/input"
exec {scan_input}<>"$ARANEA_TEST_SANDBOX/input"
PATH="$ARANEA_TEST_SANDBOX/slow-bin:$PATH" "$scan" "$root_id" <&"$scan_input" >"$ARANEA_TEST_SANDBOX/cancel-result" 2>"$ARANEA_TEST_SANDBOX/diagnostics" &
scan_pid=$!
# Clean up only test-owned processes if an assertion fails.
cleanup_scan() {
  kill -TERM "$scan_pid" 2>/dev/null || true
  if [[ -e "$ARANEA_TEST_SANDBOX/slow-pids" ]]; then while read -r pid; do kill -KILL "$pid" 2>/dev/null || true; done <"$ARANEA_TEST_SANDBOX/slow-pids"; fi
}
sandbox_on_exit cleanup_scan
for ((i = 0; i < 100; i++)); do
  [[ -s "$ARANEA_TEST_SANDBOX/slow-pids" ]] && break
  sleep 0.02
done
[[ -s "$ARANEA_TEST_SANDBOX/slow-pids" ]]
printf 'cancel\n' >&"$scan_input"
for ((i = 0; i < 150; i++)); do
  kill -0 "$scan_pid" 2>/dev/null || break
  sleep 0.02
done
! kill -0 "$scan_pid" 2>/dev/null || {
  echo 'Cancellation did not terminate the wrapper' >&2
  exit 1
}
wait "$scan_pid" || true
while read -r pid; do
  if [[ -e /proc/$pid/stat && $(awk '{print $3}' "/proc/$pid/stat") != Z ]]; then
    echo "Leaked scan descendant $pid" >&2
    exit 1
  fi
done <"$ARANEA_TEST_SANDBOX/slow-pids"
