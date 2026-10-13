#!/usr/bin/env bash
# Consolidated bar controls preserve standalone fallback and configured settings.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
task_root="$(mktemp -d)"
export ARANEA_STATE_ROOT="$task_root/state"
mkdir -p "$task_root/plugins"
for id in network bluetooth audio power monitor; do
  mkdir -p "$task_root/plugins/araneadev.$id"
  printf '{}\n' >"$task_root/plugins/araneadev.$id/manifest.json"
done
config="$task_root/shell.json"
cat >"$config" <<'JSON'
{"bar":{"layout":{"left":[],"center":[],"right":[{"id":"omarchy.tray"},{"id":"araneadev.health","custom":"keep"},{"id":"araneadev.notifications"},{"id":"araneadev.agents"},{"id":"omarchy.microphone"},{"id":"omarchy.bluetooth"},{"id":"omarchy.network","custom":"network"},{"id":"omarchy.audio"},{"id":"omarchy.monitor"},{"id":"omarchy.power","showPercentage":true}]}}}
JSON
"$repo_root/scripts/repair-shell-config" "$config" >/dev/null
jq -e '([.bar.layout.right[] | .id] | index("omarchy.microphone")) == null and
  ([.bar.layout.right[] | .id] | index("araneadev.bluetooth")) == null and
  ([.bar.layout.right[] | .id] | index("araneadev.monitor")) == null and
  any(.bar.layout.right[]; .id == "araneadev.health" and .alertOnly == true and .custom == "keep") and
  any(.bar.layout.right[]; .id == "araneadev.power" and .showPercentage == true) and
  any(.bar.layout.right[]; .id == "araneadev.network" and .custom == "network")' "$config" >/dev/null
cp "$config" "$task_root/once.json"
"$repo_root/scripts/repair-shell-config" "$config" >/dev/null
cmp "$config" "$task_root/once.json"
# Removing a host keeps child controls reachable as standalone bar widgets.
cat >"$config" <<'JSON'
{"bar":{"layout":{"left":[],"right":["omarchy.bluetooth","omarchy.monitor","omarchy.microphone","araneadev.health"]}}}
JSON
"$repo_root/scripts/repair-shell-config" "$config" >/dev/null
jq -e '([.bar.layout.right[] | (if type=="string" then . else .id end)] | index("araneadev.bluetooth")) != null and
  ([.bar.layout.right[] | (if type=="string" then . else .id end)] | index("araneadev.monitor")) != null and
  ([.bar.layout.right[] | (if type=="string" then . else .id end)] | index("omarchy.microphone")) != null' "$config" >/dev/null
printf 'bar consolidation contract passed\n'
