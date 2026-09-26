#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -x "$repo_root/scripts/deploy-plugins-safely" ]]
grep -Fq 'deploy-plugins-safely' "$repo_root/hooks/theme-set"
grep -Fq 'deploy-plugins-safely' "$repo_root/hooks/post-boot"
grep -Fq 'quickshell kill' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'omarchy restart shell' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'repair-shell-config' "$repo_root/scripts/deploy-plugins-safely"
bash -n "$repo_root/scripts/deploy-plugins-safely"

# A plugin can end up deployed on disk without ever being registered in
# shell.json (a manual deploy, an update that skipped the theme-set/post-boot
# hooks). deploy-plugins-safely must repair shell.json even when every plugin
# already matches its source and no live redeploy is needed, so the config
# self-heals on the very next boot or theme-set instead of staying silently
# disabled indefinitely.
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
config_dir="$work_dir/config"
plugins_dir="$config_dir/plugins"
mkdir -p "$plugins_dir"
cat > "$config_dir/shell.json" <<'EOF'
{"plugins": [{"id": "araneadev.lock"}], "disabledPlugins": []}
EOF
for plugin_id in araneadev.lock araneadev.menu araneadev.bar araneadev.notifications araneadev.osd; do
  cp -a "$repo_root/plugins/$plugin_id" "$plugins_dir/$plugin_id"
done

"$repo_root/scripts/deploy-plugins-safely" "$repo_root" "$plugins_dir"

jq -e '.bar.id == "araneadev.bar"' "$config_dir/shell.json" >/dev/null
jq -e '([.plugins[].id] | sort) == (["araneadev.lock", "araneadev.notifications", "araneadev.osd"] | sort)' "$config_dir/shell.json" >/dev/null

echo "shell deployment lifecycle contract passed"
