#!/usr/bin/env bash
# A provider's two-second deadline must include wrapper cleanup and worker descendants.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
fixture="$TMPDIR/hook"
mkdir -p "$fixture"
cp "$repo_root/scripts/aranea-agent-hook" "$fixture/aranea-agent-hook"
# Only the slow external worker is replaced: the real wrapper owns its deadline.
cat >"$fixture/aranea-agent-hook-worker" <<'WORKER'
#!/bin/bash
if [[ ${ARANEA_TEST_WORKER_TERM:-} == resistant ]]; then trap '' TERM; fi
printf '%s\n' "$$" >>"$ARANEA_STATE_ROOT/pids"
/bin/bash -c 'trap "" TERM; printf "%s\n" "$$" >>"$ARANEA_STATE_ROOT/pids"; exec /bin/sleep 30' &
wait
WORKER
mkdir -p "$ARANEA_STATE_ROOT"
# shellcheck disable=SC2016
sandbox_on_exit 'if [[ -f "$ARANEA_STATE_ROOT/pids" ]]; then while read -r pid; do kill -KILL "$pid" 2>/dev/null || true; done <"$ARANEA_STATE_ROOT/pids"; fi'
for worker_term in default resistant; do
  : >"$ARANEA_STATE_ROOT/pids"
  status=0
  ARANEA_TEST_WORKER_TERM="$worker_term" /usr/bin/timeout 2 "$fixture/aranea-agent-hook" claude </dev/null >"$TMPDIR/out" 2>"$TMPDIR/err" || status=$?
  [[ $status == 0 ]] || {
    echo "FAIL $worker_term worker exceeded outer provider deadline (exit $status)"
    exit 1
  }
  [[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
  [[ $(wc -l <"$ARANEA_STATE_ROOT/pids") == 2 ]]
  while read -r pid; do
    if [[ -r /proc/$pid/stat ]] && [[ $(awk '{print $3}' "/proc/$pid/stat") != Z ]]; then
      echo "FAIL $worker_term worker descendant $pid survived wrapper"
      exit 1
    fi
  done <"$ARANEA_STATE_ROOT/pids"
done
echo 'PASS default and TERM-resistant workers leave no live descendants before outer two-second deadline'
# A successful worker receives native stdin and keeps its detached helper alive.
cat >"$fixture/aranea-agent-hook-worker" <<'WORKER'
#!/bin/bash
IFS= read -r payload
[[ $payload == 'native payload' ]] || exit 17
printf '%s\n' "$payload" >"$ARANEA_STATE_ROOT/received"
/usr/bin/setsid /bin/bash -c 'printf "%s\n" "$$" >>"$ARANEA_STATE_ROOT/pids"; touch "$ARANEA_STATE_ROOT/helper-ready"; exec /bin/sleep 30' </dev/null >/dev/null 2>&1 &
WORKER
: >"$ARANEA_STATE_ROOT/pids"
printf 'native payload\n' | /usr/bin/timeout 2 "$fixture/aranea-agent-hook" claude >"$TMPDIR/out" 2>"$TMPDIR/err"
[[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
[[ $(cat "$ARANEA_STATE_ROOT/received") == 'native payload' ]]
for _ in {1..100}; do
  [[ ! -e "$ARANEA_STATE_ROOT/helper-ready" ]] || break
  sleep .01
done
[[ -e "$ARANEA_STATE_ROOT/helper-ready" ]]
helper_pid=$(cat "$ARANEA_STATE_ROOT/pids")
kill -0 "$helper_pid"
[[ $(awk '{print $3}' "/proc/$helper_pid/stat") != Z ]]
echo 'PASS successful worker receives native stdin and detached helper survives'
# Failure and missing-worker exits must still leave the provider with no output.
for mode in failed missing; do
  if [[ $mode == failed ]]; then
    printf '#!/bin/bash\necho failed; echo failed >&2; exit 23\n' >"$fixture/aranea-agent-hook-worker"
  else
    rm "$fixture/aranea-agent-hook-worker"
  fi
  /usr/bin/timeout 2 "$fixture/aranea-agent-hook" claude </dev/null >"$TMPDIR/out" 2>"$TMPDIR/err"
  [[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
done
echo 'PASS failed and missing workers are silent successful advisory deliveries'
# Exercise real lock contention, and preserve exact durable bytes on failure.
mkdir -p "$ARANEA_STATE_ROOT"
printf '{broken\n' >"$ARANEA_STATE_ROOT/agent-activity.json"
cp "$ARANEA_STATE_ROOT/agent-activity.json" "$TMPDIR/before"
# shellcheck disable=SC2016
flock "$ARANEA_STATE_ROOT/agent-activity.json.lock" -c 'touch "$TMPDIR/locked"; sleep 3' &
locker=$!
# shellcheck disable=SC2016
sandbox_on_exit 'kill "$locker" 2>/dev/null || true; wait "$locker" 2>/dev/null || true'
for _ in {1..100}; do
  [[ ! -e "$TMPDIR/locked" ]] || break
  sleep .01
done
[[ -e "$TMPDIR/locked" ]]
printf '{"session_id":"contended","hook_event_name":"SessionStart"}\n' | /usr/bin/timeout 2 "$repo_root/scripts/aranea-agent-hook" claude >"$TMPDIR/out" 2>"$TMPDIR/err"
[[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
cmp "$TMPDIR/before" "$ARANEA_STATE_ROOT/agent-activity.json"
wait "$locker"
echo 'PASS real contended transaction returns within provider deadline without changing state'
# A store cut off by the deadline still removes its own scratch files.
slow="$TMPDIR/slow-scripts"
cp -r "$repo_root/scripts" "$slow"
# The mapper spins inside the store's own shell until the deadline signal.
printf '%s\n' '#!/usr/bin/env bash' 'agent_hooks_prepare_request() { while :; do :; done; }' >"$slow/lib/agent-hooks.sh"
rm -rf "$ARANEA_STATE_ROOT"
mkdir -p "$ARANEA_STATE_ROOT"
for _ in 1 2 3 4 5 6; do
  printf '{"session_id":"slow","hook_event_name":"Stop","cwd":"/"}\n' | /usr/bin/timeout 2 "$slow/aranea-agent-hook" claude >"$TMPDIR/out" 2>"$TMPDIR/err"
  [[ ! -s "$TMPDIR/out" && ! -s "$TMPDIR/err" ]]
done
leftovers=0
for _ in {1..50}; do
  leftovers=$(find "$ARANEA_STATE_ROOT" -mindepth 1 -maxdepth 1 \( -name '.activity.*' -o -name 'agent-activity.json.??????*' \) | wc -l)
  ((leftovers == 0)) && break
  sleep .02
done
((leftovers == 0)) || {
  echo "FAIL store cut off by the deadline left $leftovers scratch files"
  ls -a "$ARANEA_STATE_ROOT"
  exit 1
}
echo 'PASS store cut off by the deadline removes its scratch files'
