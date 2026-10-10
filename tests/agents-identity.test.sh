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

# A Codex claim must never borrow a Claude executable's proof.
jq '.provider="codex"' <<<"$query" | "$helper" | jq -e '.verified==false' >/dev/null
cp /usr/bin/sleep "$ARANEA_TEST_SANDBOX/bin/codex"
"$ARANEA_TEST_SANDBOX/bin/codex" 30 &
codex_pid=$!
sandbox_on_exit "kill $codex_pid 2>/dev/null || true"
agent_hooks_provider_process "$codex_pid" codex || {
  echo 'FAIL Codex CLI process proof unavailable'
  exit 1
}
if agent_hooks_provider_process "$codex_pid" claude; then exit 1; fi
read -r parent start < <(agent_hooks_process "$codex_pid")
evidence=$(jq --argjson pid "$codex_pid" --arg start "$start" --arg exe "$(readlink -f "/proc/$codex_pid/exe")" --arg hash "$(agent_hooks_command_hash "$codex_pid")" '.pid=$pid|.startTime=$start|.executable=$exe|.commandHash=$hash' <<<"$evidence")
jq -cn --argjson evidence "$evidence" '{provider:"codex",provenance:$evidence}' | "$helper" | jq -e '.verified' >/dev/null
jq -cn --argjson evidence "$evidence" '{provenance:$evidence}' | "$helper" | jq -e '.verified' >/dev/null
cp /bin/bash "$ARANEA_TEST_SANDBOX/bin/codex-app"
# The absolute codex symlink models a versioned native install with app-server argv.
rm "$ARANEA_TEST_SANDBOX/bin/codex"
ln -s "$ARANEA_TEST_SANDBOX/bin/codex-app" "$ARANEA_TEST_SANDBOX/bin/codex"
"$ARANEA_TEST_SANDBOX/bin/codex" -c 'sleep 30 & wait' app-server &
app_pid=$!
sandbox_on_exit "kill $app_pid 2>/dev/null || true"
sleep .05
if agent_hooks_provider_process "$app_pid" codex; then
  echo 'FAIL app-server accepted as CLI'
  exit 1
fi
echo 'PASS provider-specific Codex CLI proof and app-server refusal'
