#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
test_root="$(mktemp -d)"
# Markers go to a scratch state dir from the very first repair, never the
# real ~/.local/state/aranea (a stray polkit-handover marker there would
# restart the live shell on the next hook run).
export ARANEA_STATE_ROOT="$test_root/state"

config="$test_root/shell.json"
cat >"$config" <<'EOF'
{
  "bar": {"id": "omarchy.bar", "position": "top"},
  "plugins": [{"id": "araneadev.lock"}],
  "disabledPlugins": ["omarchy.menu"],
  "unrelated": {"keep": true}
}
EOF

"$repo_root/scripts/repair-shell-config" "$config"

jq -e '.bar.id == "araneadev.bar"' "$config" >/dev/null
jq -e '([.disabledPlugins[]] | sort) == (["omarchy.bar", "omarchy.clipboard", "omarchy.emojis", "omarchy.lock", "omarchy.menu", "omarchy.notifications", "omarchy.osd", "omarchy.polkit"] | sort)' "$config" >/dev/null
jq -e '([.plugins[].id] | sort) == (["araneadev.clipboard", "araneadev.emojis", "araneadev.health", "araneadev.lock", "araneadev.notifications", "araneadev.osd", "araneadev.polkit"] | sort)' "$config" >/dev/null
grep -Fq 'araneadev.health' "$repo_root/scripts/deploy-plugins-safely"
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
# The bell sections below assert exact layouts; keep the health icon out of
# them (its own section at the end clears this marker).
mkdir -p "$state_root" && touch "$state_root/health-widget-placed"

cat >"$config" <<'EOF'
{"bar": {"layout": {"left": [], "center": [], "right": [{"id": "omarchy.microphone"}, {"id": "omarchy.tray"}, {"id": "omarchy.network"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] == ["omarchy.microphone", "araneadev.notifications", "omarchy.tray", "omarchy.network"]' "$config" >/dev/null
test -f "$marker"

# Idempotent: a second run adds nothing.
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id | select(. == "araneadev.notifications")] | length == 1' "$config" >/dev/null

# Removal is respected once the marker exists (Review Focus 5).
jq '.bar.layout.right |= map(select(.id != "araneadev.notifications"))' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] | index("araneadev.notifications") == null' "$config" >/dev/null

# No tray: prepend. No layout: untouched, no marker.
rm -f "$marker"
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": [{"id": "omarchy.network"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right[0].id == "araneadev.notifications"' "$config" >/dev/null

rm -f "$marker"
cat >"$config" <<'EOF'
{"bar": {"position": "top"}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout == null' "$config" >/dev/null
test ! -e "$marker"

# Already placed by the user in another section: not duplicated, marker written.
cat >"$config" <<'EOF'
{"bar": {"layout": {"center": [{"id": "araneadev.notifications"}], "right": [{"id": "omarchy.tray"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] == ["omarchy.tray"]' "$config" >/dev/null
test -f "$marker"

# String layout entries (review Important #1)
rm -f "$marker"
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.clock", {"id": "omarchy.tray"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right[1].id == "araneadev.notifications" and .bar.id == "araneadev.bar"' "$config" >/dev/null
rm -f "$marker"
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": ["araneadev.notifications", "omarchy.tray"]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end) | select(. == "araneadev.notifications")] | length == 1' "$config" >/dev/null

# --- leaving Aranea hands notifications back to Omarchy; returning restores the bell
parked="$state_root/notifications-widget-parked"
rm -f "$marker" "$parked"
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": [{"id": "omarchy.tray"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '(.disabledPlugins | index("omarchy.notifications")) != null' "$config" >/dev/null
jq '.cloneSourceRestores = ["araneadev.menu", "araneadev.notifications"]' "$config" >"$config.tmp" && mv "$config.tmp" "$config"

"$repo_root/scripts/release-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] | index("araneadev.notifications") == null' "$config" >/dev/null
jq -e '[.plugins[]?.id] | index("araneadev.notifications") == null' "$config" >/dev/null
jq -e '(.disabledPlugins | index("omarchy.notifications")) == null' "$config" >/dev/null
jq -e '((.cloneSourceRestores // []) | index("araneadev.menu")) == null' "$config" >/dev/null # the menu is handed back too
test -f "$parked"

"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] == ["araneadev.notifications", "omarchy.tray"]' "$config" >/dev/null
jq -e '(.disabledPlugins | index("omarchy.notifications")) != null' "$config" >/dev/null
jq -e '(.cloneSourceRestores | index("araneadev.notifications")) != null' "$config" >/dev/null
test ! -e "$parked"

# Removed by the user while on Aranea: leaving parks nothing, returning adds nothing.
jq '.bar.layout.right |= map(select(.id != "araneadev.notifications"))' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
"$repo_root/scripts/release-shell-config" "$config"
test ! -e "$parked"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] == ["omarchy.tray"]' "$config" >/dev/null

grep -Fq 'release-shell-config' "$repo_root/hooks/theme-set"

# --- health icon placement
hmarker="$state_root/health-widget-placed"
hparked="$state_root/health-widget-parked"
rm -f "$marker" "$parked" "$hmarker" "$hparked"
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": [{"id": "omarchy.tray"}, {"id": "omarchy.network"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] == ["araneadev.health", "araneadev.notifications", "omarchy.tray", "omarchy.network"]' "$config" >/dev/null
test -f "$hmarker"
# Bell removed by hand, health kept: nothing moves, nothing re-added (Review Focus 4)
jq '.bar.layout.right |= map(select(.id != "araneadev.notifications"))' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] == ["araneadev.health", "omarchy.tray", "omarchy.network"]' "$config" >/dev/null
# Health removed by hand stays removed
jq '.bar.layout.right |= map(select(.id != "araneadev.health"))' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[].id] | index("araneadev.health") == null' "$config" >/dev/null
# No bell: placed before the tray
rm -f "$hmarker"
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.clock", {"id": "omarchy.tray"}]}}}
EOF
touch "$marker"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] == ["omarchy.clock", "araneadev.health", "omarchy.tray"]' "$config" >/dev/null
# Leave and return
"$repo_root/scripts/release-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] | index("araneadev.health") == null' "$config" >/dev/null
jq -e '[.plugins[]?.id] | index("araneadev.health") == null' "$config" >/dev/null
test -f "$hparked"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] | index("araneadev.health") != null' "$config" >/dev/null
test ! -e "$hparked"

# --- pickers: stock pickers stay disabled on Aranea and come back elsewhere
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '([.plugins[]?.id] | index("araneadev.clipboard") != null) and ([.plugins[]?.id] | index("araneadev.emojis") != null)' "$config" >/dev/null
jq -e '(.disabledPlugins | index("omarchy.clipboard") != null) and (.disabledPlugins | index("omarchy.emojis") != null)' "$config" >/dev/null
jq -e '(.cloneSourceRestores | index("araneadev.clipboard") != null) and (.cloneSourceRestores | index("araneadev.emojis") != null)' "$config" >/dev/null
"$repo_root/scripts/release-shell-config" "$config"
jq -e '([.plugins[]?.id] | index("araneadev.clipboard") == null) and ([.plugins[]?.id] | index("araneadev.emojis") == null)' "$config" >/dev/null
jq -e '((.disabledPlugins // []) | index("omarchy.clipboard") == null) and ((.disabledPlugins // []) | index("omarchy.emojis") == null)' "$config" >/dev/null
jq -e '((.cloneSourceRestores // []) | index("araneadev.clipboard") == null)' "$config" >/dev/null

# --- polkit: exactly one agent. Ours on Aranea, stock back elsewhere, and
# stock back if ours is disabled by hand (cloneSourceRestores).
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.plugins[]?.id] | index("araneadev.polkit") != null' "$config" >/dev/null
jq -e '.disabledPlugins | index("omarchy.polkit") != null' "$config" >/dev/null
jq -e '.cloneSourceRestores | index("araneadev.polkit") != null' "$config" >/dev/null
"$repo_root/scripts/release-shell-config" "$config"
jq -e '[.plugins[]?.id] | index("araneadev.polkit") == null' "$config" >/dev/null
jq -e '(.disabledPlugins // []) | index("omarchy.polkit") == null' "$config" >/dev/null
jq -e '(.cloneSourceRestores // []) | index("araneadev.polkit") == null' "$config" >/dev/null

# --- polkit handover (final review I1): an agent registers once per shell
# process, so the running shell must restart whenever the prompt changes
# hands. The config scripts only leave a marker; finish-polkit-handover acts.
handover="$state_root/polkit-handover"
"$repo_root/scripts/repair-shell-config" "$config"
rm -f "$handover"
"$repo_root/scripts/repair-shell-config" "$config"
test ! -e "$handover"
"$repo_root/scripts/release-shell-config" "$config"
test -e "$handover"
rm -f "$handover"
"$repo_root/scripts/release-shell-config" "$config"
test ! -e "$handover"
"$repo_root/scripts/repair-shell-config" "$config"
test -e "$handover"

stub_bin="$test_root/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "shell ping" && -e "$STUB_SHELL_UP" ]]
EOF
cat >"$stub_bin/omarchy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
EOF
chmod +x "$stub_bin/omarchy-shell" "$stub_bin/omarchy"
export STUB_LOG="$test_root/omarchy.log" STUB_SHELL_UP="$test_root/shell-up"
: >"$STUB_LOG"
# No marker: nothing to do.
rm -f "$handover"
PATH="$stub_bin:$PATH" "$repo_root/scripts/finish-polkit-handover"
test ! -s "$STUB_LOG"
# Marker and a running shell: restart it, consume the marker.
: >"$handover"
: >"$STUB_SHELL_UP"
PATH="$stub_bin:$PATH" "$repo_root/scripts/finish-polkit-handover"
grep -Fxq 'restart shell' "$STUB_LOG"
test ! -e "$handover"
# Marker but no shell: the next start registers fresh; just consume it.
: >"$STUB_LOG"
rm -f "$STUB_SHELL_UP"
: >"$handover"
PATH="$stub_bin:$PATH" "$repo_root/scripts/finish-polkit-handover"
test ! -s "$STUB_LOG"
test ! -e "$handover"
# Both hook paths (leaving and arriving) and post-boot finish the handover;
# a deploy that restarts the shell itself consumes the marker.
[[ "$(grep -c 'finish-polkit-handover' "$repo_root/hooks/theme-set")" -ge 2 ]]
grep -Fq 'finish-polkit-handover' "$repo_root/hooks/post-boot"
grep -Fq 'polkit-handover' "$repo_root/scripts/deploy-plugins-safely"

# --- lock and OSD: exactly one provider each way (spec A1, Review Focus 3)
lock_cfg="$test_root/lock.json"
printf '{"plugins": []}\n' >"$lock_cfg"
"$repo_root/scripts/repair-shell-config" "$lock_cfg"
jq -e '(.cloneSourceRestores | index("araneadev.lock")) != null and (.cloneSourceRestores | index("araneadev.osd")) != null' "$lock_cfg" >/dev/null
"$repo_root/scripts/release-shell-config" "$lock_cfg"
jq -e '([.plugins[]? | (if type == "string" then . else .id end)] | (index("araneadev.lock") == null and index("araneadev.osd") == null))
  and ((.disabledPlugins // []) | (index("omarchy.lock") == null and index("omarchy.osd") == null))' "$lock_cfg" >/dev/null

# --- string plugin entries, order kept (spec C1)
str_cfg="$test_root/strings.json"
printf '{"plugins": ["zeta.widget", {"id": "alpha.widget", "x": 1}, "araneadev.lock"]}\n' >"$str_cfg"
"$repo_root/scripts/repair-shell-config" "$str_cfg"
jq -e '.plugins[0] == "zeta.widget" and .plugins[1] == {"id": "alpha.widget", "x": 1}
  and ([.plugins[] | (if type == "string" then . else .id end)] | map(select(. == "araneadev.lock")) | length) == 1' "$str_cfg" >/dev/null

# --- a symlinked shell.json stays a symlink (spec C2, Review Focus 5)
real_cfg="$test_root/dotfiles/shell.json"
mkdir -p "$(dirname "$real_cfg")"
printf '{"plugins": []}\n' >"$real_cfg"
link_cfg="$test_root/linked/shell.json"
mkdir -p "$(dirname "$link_cfg")"
ln -s "$real_cfg" "$link_cfg"
"$repo_root/scripts/repair-shell-config" "$link_cfg"
test -L "$link_cfg"
jq -e '[.plugins[] | .id] | index("araneadev.lock") != null' "$real_cfg" >/dev/null
"$repo_root/scripts/release-shell-config" "$link_cfg"
test -L "$link_cfg"

# --- release writes its markers only after a successful edit (spec C3):
# a jq that fails on release's main program must leave no parked marker.
real_jq="$(command -v jq)"
failing_jq="$test_root/failing-jq"
mkdir -p "$failing_jq"
cat >"$failing_jq/jq" <<EOF
#!/usr/bin/env bash
case "\$*" in *"def ours"*) exit 5 ;; esac
exec "$real_jq" "\$@"
EOF
chmod +x "$failing_jq/jq"
bell_cfg="$test_root/bell.json"
printf '{"bar": {"layout": {"right": ["araneadev.notifications"]}}}\n' >"$bell_cfg"
rm -f "$state_root/notifications-widget-parked"
if PATH="$failing_jq:$PATH" "$repo_root/scripts/release-shell-config" "$bell_cfg" >/dev/null 2>&1; then
  echo "release succeeded although jq failed" >&2
  exit 1
fi
if [[ -e "$state_root/notifications-widget-parked" ]]; then
  echo "marker written although the release failed" >&2
  exit 1
fi
jq -e '.bar.layout.right == ["araneadev.notifications"]' "$bell_cfg" >/dev/null

# --- the bar and menu go back to Omarchy too, and come back on return
bar_cfg="$test_root/bar.json"
printf '{"bar": {"position": "top", "layout": {"left": ["omarchy.menu", "omarchy.workspaces"], "right": ["omarchy.tray"]}}}\n' >"$bar_cfg"
"$repo_root/scripts/repair-shell-config" "$bar_cfg" >/dev/null
jq -e '.bar.id == "araneadev.bar" and .bar.layout.left[0] == "araneadev.menu"
  and (.disabledPlugins | index("omarchy.menu")) != null and (.disabledPlugins | index("omarchy.bar")) != null
  and (.cloneSourceRestores | index("araneadev.menu")) != null' "$bar_cfg" >/dev/null || {
  cat "$bar_cfg"
  exit 1
}
"$repo_root/scripts/release-shell-config" "$bar_cfg" >/dev/null
jq -e '(.bar | has("id") | not) and .bar.position == "top" and .bar.layout.left[0] == "omarchy.menu"
  and ((.disabledPlugins // []) | (index("omarchy.menu") == null and index("omarchy.bar") == null))
  and ([.plugins[]? | (if type == "string" then . else .id end)] | index("araneadev.menu") == null)' "$bar_cfg" >/dev/null || {
  cat "$bar_cfg"
  exit 1
}
"$repo_root/scripts/repair-shell-config" "$bar_cfg" >/dev/null
jq -e '.bar.id == "araneadev.bar" and .bar.layout.left[0] == "araneadev.menu"' "$bar_cfg" >/dev/null || {
  cat "$bar_cfg"
  exit 1
}

echo "shell config contract passed"
