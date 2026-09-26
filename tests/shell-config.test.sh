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
jq -e '([.disabledPlugins[]] | sort) == (["omarchy.bar", "omarchy.lock", "omarchy.menu", "omarchy.osd", "tim.bar", "tim.lock", "tim.menu"] | sort)' "$config" >/dev/null
jq -e '([.plugins[].id] | sort) == (["araneadev.lock", "araneadev.notifications", "araneadev.osd"] | sort)' "$config" >/dev/null
jq -e '.bar.position == "top" and .unrelated.keep == true' "$config" >/dev/null

grep -Fq 'repair-shell-config' "$repo_root/hooks/theme-set"
grep -Fq 'repair-shell-config' "$repo_root/hooks/post-boot"
grep -Fq 'disable --now aranea-wallpaper-day-night.timer' "$repo_root/hooks/theme-set"
if grep -Fq 'target: "omarchy.bar"' "$repo_root/plugins/araneadev.bar/Bar.qml"; then
  echo "Aranea bar must not register the stock omarchy.bar IPC target" >&2
  exit 1
fi

# --- notification bell placement
state_root="$test_root/state"
export ARANEA_STATE_ROOT="$state_root"
marker="$state_root/notifications-widget-placed"

cat > "$config" <<'EOF'
{"bar": {"layout": {"left": [], "center": [], "right": [{"id": "omarchy.microphone"}, {"id": "omarchy.tray"}, {"id": "omarchy.network"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] == ["omarchy.microphone", "araneadev.notifications", "omarchy.tray", "omarchy.network"]' "$config" >/dev/null
test -f "$marker"

# Idempotent: a second run adds nothing.
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id | select(. == "araneadev.notifications")] | length == 1' "$config" >/dev/null

# Removal is respected once the marker exists (Review Focus 5).
jq '.bar.layout.right |= map(select(.id != "araneadev.notifications"))' "$config" > "$config.tmp" && mv "$config.tmp" "$config"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] | index("araneadev.notifications") == null' "$config" >/dev/null

# No tray: prepend. No layout: untouched, no marker.
rm -f "$marker"
cat > "$config" <<'EOF'
{"bar": {"layout": {"right": [{"id": "omarchy.network"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right[0].id == "araneadev.notifications"' "$config" >/dev/null

rm -f "$marker"
cat > "$config" <<'EOF'
{"bar": {"position": "top"}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout == null' "$config" >/dev/null
test ! -e "$marker"

# Already placed by the user in another section: not duplicated, marker written.
cat > "$config" <<'EOF'
{"bar": {"layout": {"center": [{"id": "araneadev.notifications"}], "right": [{"id": "omarchy.tray"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] == ["omarchy.tray"]' "$config" >/dev/null
test -f "$marker"

# String layout entries (review Important #1)
rm -f "$marker"
cat > "$config" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.clock", {"id": "omarchy.tray"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right[1].id == "araneadev.notifications" and .bar.id == "araneadev.bar"' "$config" >/dev/null
rm -f "$marker"
cat > "$config" <<'EOF'
{"bar": {"layout": {"right": ["araneadev.notifications", "omarchy.tray"]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end) | select(. == "araneadev.notifications")] | length == 1' "$config" >/dev/null

echo "shell config contract passed"
