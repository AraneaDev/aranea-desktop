#!/usr/bin/env bash
# Contract for scripts/deploy-plugins-safely: it is wired into both hooks,
# stops quickshell and restarts the shell, calls repair-shell-config, and
# repairs shell.json even when every plugin is already deployed on disk (a
# plugin present but never registered must not stay silently disabled).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

[[ -x "$repo_root/scripts/deploy-plugins-safely" ]]
grep -Fq 'deploy-plugins-safely' "$repo_root/hooks/theme-set"
grep -Fq 'deploy-plugins-safely' "$repo_root/hooks/post-boot"
grep -Fq 'quickshell kill' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'omarchy restart shell' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'repair-shell-config' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'araneadev.shared' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'araneadev.vpn' "$repo_root/scripts/deploy-plugins-safely"
bash -n "$repo_root/scripts/deploy-plugins-safely"

# A plugin can end up deployed on disk without ever being registered in
# shell.json (a manual deploy, an update that skipped the theme-set/post-boot
# hooks). deploy-plugins-safely must repair shell.json even when every plugin
# already matches its source and no live redeploy is needed, so the config
# self-heals on the very next boot or theme-set instead of staying silently
# disabled indefinitely.
work_dir="$(mktemp -d)"
export ARANEA_STATE_ROOT="$work_dir/state"
config_dir="$work_dir/config"
plugins_dir="$config_dir/plugins"
mkdir -p "$plugins_dir" "$work_dir/bin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$work_dir/bin/omarchy-hyprland-session-locked"
chmod +x "$work_dir/bin/omarchy-hyprland-session-locked"
export PATH="$work_dir/bin:$PATH"
cat >"$config_dir/shell.json" <<'EOF'
{"plugins": [{"id": "araneadev.lock"}], "disabledPlugins": []}
EOF
for plugin_id in araneadev.lock araneadev.menu araneadev.bar araneadev.notifications araneadev.health araneadev.clipboard araneadev.emojis araneadev.polkit araneadev.osd araneadev.workspaces araneadev.updates araneadev.audio araneadev.bluetooth araneadev.monitor araneadev.network araneadev.vpn araneadev.power araneadev.clock araneadev.weather araneadev.tray araneadev.agents; do
  cp -a "$repo_root/plugins/$plugin_id" "$plugins_dir/$plugin_id"
done

"$repo_root/scripts/deploy-plugins-safely" "$repo_root" "$plugins_dir"

jq -e '.bar.id == "araneadev.bar"' "$config_dir/shell.json" >/dev/null
jq -e '([.plugins[].id] | sort) == (["araneadev.settings", "araneadev.clipboard", "araneadev.emojis", "araneadev.health", "araneadev.lock", "araneadev.notifications", "araneadev.osd", "araneadev.polkit", "araneadev.updates", "araneadev.workspaces"] | sort)' "$config_dir/shell.json" >/dev/null

# A settings plugin missing from the target is deployed and registered; the
# unrelated plugin and its inline settings survive deployment/release/return.
jq '.plugins += [{id:"user.widget", option:7}] | .userSettings = {keep:true}' "$config_dir/shell.json" >"$config_dir/shell.next"
mv "$config_dir/shell.next" "$config_dir/shell.json"
"$repo_root/scripts/deploy-plugins-safely" "$repo_root" "$plugins_dir"
test -f "$plugins_dir/araneadev.settings/Settings.qml"
diff -qr "$repo_root/plugins/araneadev.settings" "$plugins_dir/araneadev.settings"
jq -e '([.plugins[].id | select(. == "araneadev.settings")] | length) == 1
  and (.plugins | map(select(.id == "user.widget"))) == [{id:"user.widget", option:7}]
  and .userSettings.keep' "$config_dir/shell.json" >/dev/null
"$repo_root/scripts/release-shell-config" "$config_dir/shell.json"
jq -e '([.plugins[].id] | index("araneadev.settings")) == null and .userSettings.keep' "$config_dir/shell.json" >/dev/null
"$repo_root/scripts/deploy-plugins-safely" "$repo_root" "$plugins_dir"
jq -e '([.plugins[].id | select(. == "araneadev.settings")] | length) == 1 and .userSettings.keep' "$config_dir/shell.json" >/dev/null

# --- 4d: a missing argument prints a usage line and exits 2
rc=0
out="$("$repo_root/scripts/deploy-plugins-safely" 2>&1)" || rc=$?
[[ $rc -eq 2 ]] || exit 1
grep -Fq 'Usage: scripts/deploy-plugins-safely <theme-root> [target-root]' <<<"$out"
rc=0
out="$("$repo_root/scripts/deploy-plugin" 2>&1)" || rc=$?
[[ $rc -eq 2 ]] || exit 1
grep -Fq 'Usage: scripts/deploy-plugin <source-dir> <target-dir>' <<<"$out"

echo "shell deployment lifecycle contract passed"
