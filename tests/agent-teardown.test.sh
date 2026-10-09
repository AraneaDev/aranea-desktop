#!/usr/bin/env bash
# Held publication and queued ingress must not outlive either uninstall scope.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
store="$repo_root/scripts/aranea-agent-store"
mkdir -p "$TMPDIR/bin"
cat >"$TMPDIR/bin/mv" <<'MV'
#!/bin/bash
if [[ "$*" == *agent-activity.json* && "${HOLD_PUBLICATION:-0}" == 1 ]]; then
  touch "$TMPDIR/held"
  for _ in {1..1000}; do [[ ! -e "$TMPDIR/release" ]] || break; sleep .01; done
fi
exec /usr/bin/mv "$@"
MV
cat >"$TMPDIR/bin/flock" <<'FLOCK'
#!/bin/bash
[[ "${TEARDOWN_PROBE:-0}" != 1 ]] || touch "$TMPDIR/teardown-lock"
[[ "${QUEUED_PROBE:-0}" != 1 ]] || touch "$TMPDIR/queued-lock"
exec /usr/bin/flock "$@"
FLOCK
chmod +x "$TMPDIR/bin/"*
export PATH="$TMPDIR/bin:$PATH"
pids=()
# Every fixture child has bounded waits and cleanup on an assertion failure.
cleanup_writers() {
  touch "$TMPDIR/release"
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
}
sandbox_on_exit cleanup_writers
for scope in integration complete; do
  for layout in separate equal activity-nested ownership-nested; do
    base="$ARANEA_TEST_SANDBOX/$scope-$layout"
    export ARANEA_STATE_ROOT="$base/activity" ARANEA_OWNERSHIP_ROOT="$base/ownership"
    case "$layout" in
      equal) export ARANEA_OWNERSHIP_ROOT="$ARANEA_STATE_ROOT" ;;
      activity-nested) export ARANEA_STATE_ROOT="$ARANEA_OWNERSHIP_ROOT/nested/activity" ;;
      ownership-nested) export ARANEA_OWNERSHIP_ROOT="$ARANEA_STATE_ROOT/nested/ownership" ;;
    esac
    "$store" mutate <<<'{"action":"register","args":{"provider":"claude","providerSessionId":"manual","producerEpoch":"e","tasks":[]}}' >/dev/null
    inode=$(stat -c %i "$ARANEA_STATE_ROOT/agent-activity.json.lock")
    generation=$(cat "$ARANEA_STATE_ROOT/agent-activity.json.lock")
    generation=${generation:-initial}
    rm -f "$TMPDIR/held" "$TMPDIR/release" "$TMPDIR/teardown-lock" "$TMPDIR/queued-lock" "$TMPDIR/removed"
    HOLD_PUBLICATION=1 "$store" mutate <<<'{"action":"prune","args":{}}' >"$TMPDIR/writer" &
    writer=$!
    pids+=("$writer")
    for _ in {1..200}; do
      [[ ! -e "$TMPDIR/held" ]] || break
      sleep .01
    done
    [[ -e "$TMPDIR/held" ]]
    QUEUED_PROBE=1 "$store" mutate <<<'{"action":"prune","args":{}}' >"$TMPDIR/queued" &
    queued=$!
    pids+=("$queued")
    for _ in {1..200}; do
      [[ ! -e "$TMPDIR/queued-lock" ]] || break
      sleep .01
    done
    [[ -e "$TMPDIR/queued-lock" ]]
    (
      TEARDOWN_PROBE=1 "$repo_root/scripts/uninstall.sh" --yes --json --scope "$scope" >"$TMPDIR/uninstall"
      touch "$TMPDIR/removed"
    ) &
    removal=$!
    pids+=("$removal")
    for _ in {1..300}; do
      [[ ! -e "$TMPDIR/teardown-lock" && ! -e "$TMPDIR/removed" ]] || break
      sleep .01
    done
    [[ -e "$TMPDIR/teardown-lock" && ! -e "$TMPDIR/removed" ]] || {
      echo "FAIL $scope/$layout uninstall returned without draining held publication"
      exit 1
    }
    touch "$TMPDIR/release"
    wait "$writer"
    wait "$queued" || jq -e '.ok==false and (.error.code=="ACTIVITY_LOCK_FAILED" or .error.code=="ACTIVITY_REMOVED")' "$TMPDIR/queued" >/dev/null
    wait "$removal"
    [[ ! -e "$ARANEA_STATE_ROOT/agent-activity.json" && ! -e "$ARANEA_STATE_ROOT/agent-heartbeats" ]]
    [[ $(stat -c %i "$ARANEA_STATE_ROOT/agent-activity.json.lock") == "$inode" ]]
    jq -es 'last.event=="completed" and last.status=="ok"' "$TMPDIR/uninstall" >/dev/null
    if "$store" mutate <<<'{"action":"register","args":{"provider":"claude","providerSessionId":"late","producerEpoch":"e","tasks":[]}}' >"$TMPDIR/late"; then
      echo 'FAIL delayed registration recreated removed state'
      exit 1
    fi
    jq -e '.error.code=="ACTIVITY_REMOVED"' "$TMPDIR/late" >/dev/null
    # Normal reinstall reactivates the same inode; old captured worker lifetimes fail.
    "$store" activate >/dev/null
    if ARANEA_ACTIVITY_GENERATION="$generation" "$store" mutate <<<'{"action":"prune","args":{}}' >"$TMPDIR/late"; then
      echo 'FAIL old ingress crossed reinstall generation'
      exit 1
    fi
    jq -e '.error.code=="ACTIVITY_REMOVED"' "$TMPDIR/late" >/dev/null
    "$store" mutate <<<'{"action":"register","args":{"provider":"claude","providerSessionId":"new","producerEpoch":"e","tasks":[]}}' >/dev/null
    [[ $(stat -c %i "$ARANEA_STATE_ROOT/agent-activity.json.lock") == "$inode" ]]
    echo "PASS $scope/$layout held publication, queued ingress, stable inode and reinstall fencing"
  done
done
# A native worker can have started but still be waiting for its provider input.
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/delayed-worker" ARANEA_OWNERSHIP_ROOT="$ARANEA_TEST_SANDBOX/delayed-owner"
"$store" activate >/dev/null
mkfifo "$TMPDIR/native-input"
/bin/bash "$repo_root/scripts/aranea-agent-hook-worker" claude <"$TMPDIR/native-input" >"$TMPDIR/native-result" 2>&1 &
worker=$!
pids+=("$worker")
exec {input_fd}>"$TMPDIR/native-input"
# Seeing head beneath the real worker proves generation capture preceded teardown.
for _ in {1..200}; do
  reading=false
  children=()
  read -r -a children <"/proc/$worker/task/$worker/children" || true
  for child in "${children[@]}"; do
    grandchildren=()
    read -r -a grandchildren <"/proc/$child/task/$child/children" 2>/dev/null || true
    for grandchild in "${grandchildren[@]}"; do
      if [[ $(tr '\0' ' ' <"/proc/$grandchild/cmdline" 2>/dev/null || true) == *'head -c 1048577'* ]]; then reading=true; fi
    done
  done
  [[ "$reading" != true ]] || break
  sleep .01
done
[[ "$reading" == true ]]
"$repo_root/scripts/uninstall.sh" --yes >/dev/null
"$store" activate >/dev/null
printf '{"hook_event_name":"SessionStart","session_id":"late-native","cwd":"%s"}\n' "$HOME" >&"$input_fd"
exec {input_fd}>&-
if wait "$worker"; then
  echo 'FAIL delayed native input crossed reinstall'
  exit 1
fi
[[ ! -e "$ARANEA_STATE_ROOT/agent-activity.json" && ! -e "$ARANEA_STATE_ROOT/agent-heartbeats" ]]
ARANEA_ACTIVITY_GENERATION=initial /bin/bash "$repo_root/scripts/aranea-agent-heartbeat" claude late-native epoch "$$" 1 "$(cat /proc/sys/kernel/random/boot_id)"
[[ ! -e "$ARANEA_STATE_ROOT/agent-heartbeats" ]]
echo 'PASS already-started native worker and delayed helper cannot cross reinstall'
# Coordination failure is a real failed removal; held state remains untouched.
"$store" mutate <<<'{"action":"register","args":{"provider":"claude","providerSessionId":"kept","producerEpoch":"e","tasks":[]}}' >/dev/null
exec {held_fd}<>"$ARANEA_STATE_ROOT/agent-activity.json.lock"
flock -x "$held_fd"
if "$repo_root/scripts/uninstall.sh" --yes --json >"$TMPDIR/blocked"; then
  echo 'FAIL lock timeout claimed removal'
  exit 1
fi
jq -es 'last.event=="completed" and last.status=="failed" and last.code=="activity_teardown_failed"' "$TMPDIR/blocked" >/dev/null
[[ -e "$ARANEA_STATE_ROOT/agent-activity.json" ]]
exec {held_fd}>&-
echo 'PASS lock timeout reports failed teardown without false state removal'
