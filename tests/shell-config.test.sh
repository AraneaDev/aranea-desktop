#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

config="$test_root/shell.json"
cat > "$config" <<'EOF'
{
  "bar": {"id": "omarchy.bar", "position": "top"},
  "plugins": [{"id": "araneadev.lock"}],
  "disabledPlugins": ["omarchy.menu"],
  "unrelated": {"keep": true}
}
EOF

"$repo_root/scripts/repair-shell-config" "$config"

jq -e '.bar.id == "araneadev.bar"' "$config" >/dev/null
jq -e '([.disabledPlugins[]] | sort) == (["omarchy.bar", "omarchy.menu", "tim.bar", "tim.lock", "tim.menu"] | sort)' "$config" >/dev/null
jq -e '([.plugins[].id] | sort) == (["araneadev.lock", "araneadev.notifications"] | sort)' "$config" >/dev/null
jq -e '.bar.position == "top" and .unrelated.keep == true' "$config" >/dev/null

grep -Fq 'repair-shell-config' "$repo_root/hooks/theme-set"
grep -Fq 'repair-shell-config' "$repo_root/hooks/post-boot"

echo "shell config contract passed"
