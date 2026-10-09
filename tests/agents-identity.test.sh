#!/usr/bin/env bash
# Current kernel evidence and reverse terminal ancestry, without a live provider.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
helper="$repo_root/scripts/aranea-agent-identity"
[[ -x "$helper" ]] || {
  echo 'Missing native identity helper'
  exit 1
}
mkdir -p "$ARANEA_TEST_SANDBOX/bin"
cp /usr/bin/sleep "$ARANEA_TEST_SANDBOX/bin/claude"
"$ARANEA_TEST_SANDBOX/bin/claude" 30 &
pid=$!
sandbox_on_exit "kill $pid 2>/dev/null || true"
script_dir="$repo_root/scripts"
# shellcheck source=scripts/lib/agent-hooks.sh
source "$script_dir/lib/agent-hooks.sh"
read -r parent start < <(agent_hooks_process "$pid")
read -r _ host_start < <(agent_hooks_process "$parent")
evidence=$(jq -cn --argjson pid "$pid" --arg start "$start" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" --arg executable "$(readlink -f "/proc/$pid/exe")" --arg hash "$(agent_hooks_command_hash "$pid")" --argjson parent "$parent" --arg hostStart "$host_start" '{pid:$pid,startTime:$start,bootId:$boot,executable:$executable,commandHash:$hash,ancestors:[{pid:$parent,startTime:$hostStart}],windowAddress:null,observedAt:0}')
query=$(jq -cn --argjson evidence "$evidence" --argjson host "$parent" '{provenance:$evidence,terminalPid:$host}')
result=$("$helper" <<<"$query")
jq -e '.ok and .verified and .terminal.startTime!=null' <<<"$result" >/dev/null
for mutation in '.provenance.startTime="0"' '.provenance.bootId="wrong"' '.provenance.commandHash=("0"*64)' '.provenance.executable="/wrong"' '.provenance.ancestors[0].startTime="0"' '.terminalPid=.provenance.pid' '.terminalPid=1'; do
  result=$(jq "$mutation" <<<"$query" | "$helper")
  jq -e '.ok and (.verified|not)' <<<"$result" >/dev/null
done
echo 'PASS native boot/PID/start/executable/hash/ancestry and terminal-parent direction'
