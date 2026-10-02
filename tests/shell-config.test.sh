#!/usr/bin/env bash
# Contract for scripts/repair-shell-config and scripts/release-shell-config:
# repair swaps in the Aranea bar/plugins/clones and places the bell/health
# icons idempotently, release hands everything back to Omarchy and parks
# state for a clean return, polkit/lock/osd/menu/bar each end up with
# exactly one provider either way, a polkit handover marker drives a running
# shell restart, and string plugin entries / a symlinked shell.json survive.
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
jq -e '([.plugins[].id] | sort) == (["araneadev.clipboard", "araneadev.emojis", "araneadev.health", "araneadev.lock", "araneadev.notifications", "araneadev.osd", "araneadev.polkit", "araneadev.updates", "araneadev.workspaces"] | sort)' "$config" >/dev/null
grep -Fq 'araneadev.health' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'araneadev.updates' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'araneadev.workspaces' "$repo_root/scripts/deploy-plugins-safely"
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

# --- workspace overview and update center replace their stock bar entries
cat >"$config" <<'EOF'
{"bar": {"layout": {"left": ["omarchy.menu", "omarchy.workspaces"], "right": [{"id": "omarchy.system-update"}, {"id": "omarchy.tray"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.left[1] == "araneadev.workspaces" and .bar.layout.right[0].id == "araneadev.updates"' "$config" >/dev/null
"$repo_root/scripts/release-shell-config" "$config"
jq -e '.bar.layout.left[1] == "omarchy.workspaces" and .bar.layout.right[0].id == "omarchy.system-update"' "$config" >/dev/null

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

# --- audio dropdown: only retargeted once araneadev.audio is installed
# (guard: $(dirname "$config_file")/plugins/araneadev.audio/manifest.json)
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.audio", {"id": "omarchy.audio", "x": 1}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right == ["omarchy.audio", {"id": "omarchy.audio", "x": 1}]
  and ((.cloneSourceRestores // []) | index("araneadev.audio")) == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
mkdir -p "$(dirname "$config")/plugins/araneadev.audio"
: >"$(dirname "$config")/plugins/araneadev.audio/manifest.json"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right == ["araneadev.audio", {"id": "araneadev.audio", "x": 1}]
  and (.cloneSourceRestores | index("araneadev.audio")) != null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
"$repo_root/scripts/release-shell-config" "$config"
jq -e '.bar.layout.right == ["omarchy.audio", {"id": "omarchy.audio", "x": 1}]
  and ((.cloneSourceRestores // []) | index("araneadev.audio")) == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}

# A symlinked shell.json (dotfile managers): the deploy writes the plugin
# beside the config path the shell uses, not beside the link's target.
audio_real="$test_root/audio-dotfiles/shell.json"
audio_link="$test_root/audio-config/shell.json"
mkdir -p "$(dirname "$audio_real")" "$(dirname "$audio_link")/plugins/araneadev.audio"
: >"$(dirname "$audio_link")/plugins/araneadev.audio/manifest.json"
printf '%s\n' '{"bar": {"layout": {"right": ["omarchy.audio"]}}}' >"$audio_real"
ln -s "$audio_real" "$audio_link"
"$repo_root/scripts/repair-shell-config" "$audio_link"
test -L "$audio_link"
jq -e '.bar.layout.right == ["araneadev.audio"]' "$audio_real" >/dev/null || {
  cat "$audio_real"
  exit 1
}

# --- bluetooth dropdown: only retargeted once araneadev.bluetooth is
# installed (guard: $(dirname "$config_file")/plugins/araneadev.bluetooth/manifest.json)
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.bluetooth", {"id": "omarchy.bluetooth", "x": 1}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right == ["omarchy.bluetooth", {"id": "omarchy.bluetooth", "x": 1}]
  and ((.cloneSourceRestores // []) | index("araneadev.bluetooth")) == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
mkdir -p "$(dirname "$config")/plugins/araneadev.bluetooth"
: >"$(dirname "$config")/plugins/araneadev.bluetooth/manifest.json"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right == ["araneadev.bluetooth", {"id": "araneadev.bluetooth", "x": 1}]
  and (.cloneSourceRestores | index("araneadev.bluetooth")) != null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
"$repo_root/scripts/release-shell-config" "$config"
jq -e '.bar.layout.right == ["omarchy.bluetooth", {"id": "omarchy.bluetooth", "x": 1}]
  and ((.cloneSourceRestores // []) | index("araneadev.bluetooth")) == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}

# A symlinked shell.json (dotfile managers): the deploy writes the plugin
# beside the config path the shell uses, not beside the link's target.
bluetooth_real="$test_root/bluetooth-dotfiles/shell.json"
bluetooth_link="$test_root/bluetooth-config/shell.json"
mkdir -p "$(dirname "$bluetooth_real")" "$(dirname "$bluetooth_link")/plugins/araneadev.bluetooth"
: >"$(dirname "$bluetooth_link")/plugins/araneadev.bluetooth/manifest.json"
printf '%s\n' '{"bar": {"layout": {"right": ["omarchy.bluetooth"]}}}' >"$bluetooth_real"
ln -s "$bluetooth_real" "$bluetooth_link"
"$repo_root/scripts/repair-shell-config" "$bluetooth_link"
test -L "$bluetooth_link"
jq -e '.bar.layout.right == ["araneadev.bluetooth"]' "$bluetooth_real" >/dev/null || {
  cat "$bluetooth_real"
  exit 1
}

# --- network dropdown: only retargeted once araneadev.network is
# installed (guard: $(dirname "$config_file")/plugins/araneadev.network/manifest.json)
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.network", {"id": "omarchy.network", "x": 1}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right == ["omarchy.network", {"id": "omarchy.network", "x": 1}]
  and ((.cloneSourceRestores // []) | index("araneadev.network")) == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
mkdir -p "$(dirname "$config")/plugins/araneadev.network"
: >"$(dirname "$config")/plugins/araneadev.network/manifest.json"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right == ["araneadev.network", {"id": "araneadev.network", "x": 1}]
  and (.cloneSourceRestores | index("araneadev.network")) != null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
"$repo_root/scripts/release-shell-config" "$config"
jq -e '.bar.layout.right == ["omarchy.network", {"id": "omarchy.network", "x": 1}]
  and ((.cloneSourceRestores // []) | index("araneadev.network")) == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}

# A symlinked shell.json (dotfile managers): the deploy writes the plugin
# beside the config path the shell uses, not beside the link's target.
network_real="$test_root/network-dotfiles/shell.json"
network_link="$test_root/network-config/shell.json"
mkdir -p "$(dirname "$network_real")" "$(dirname "$network_link")/plugins/araneadev.network"
: >"$(dirname "$network_link")/plugins/araneadev.network/manifest.json"
printf '%s\n' '{"bar": {"layout": {"right": ["omarchy.network"]}}}' >"$network_real"
ln -s "$network_real" "$network_link"
"$repo_root/scripts/repair-shell-config" "$network_link"
test -L "$network_link"
jq -e '.bar.layout.right == ["araneadev.network"]' "$network_real" >/dev/null || {
  cat "$network_real"
  exit 1
}

# --- power dropdown: only retargeted once araneadev.power is
# installed (guard: $(dirname "$config_file")/plugins/araneadev.power/manifest.json);
# a user setting (showPercentage) on the entry survives the round trip.
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.power", {"id": "omarchy.power", "showPercentage": true}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right == ["omarchy.power", {"id": "omarchy.power", "showPercentage": true}]
  and ((.cloneSourceRestores // []) | index("araneadev.power")) == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
mkdir -p "$(dirname "$config")/plugins/araneadev.power"
: >"$(dirname "$config")/plugins/araneadev.power/manifest.json"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '.bar.layout.right == ["araneadev.power", {"id": "araneadev.power", "showPercentage": true}]
  and (.cloneSourceRestores | index("araneadev.power")) != null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
"$repo_root/scripts/release-shell-config" "$config"
jq -e '.bar.layout.right == ["omarchy.power", {"id": "omarchy.power", "showPercentage": true}]
  and ((.cloneSourceRestores // []) | index("araneadev.power")) == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}

# A symlinked shell.json (dotfile managers): the deploy writes the plugin
# beside the config path the shell uses, not beside the link's target.
power_real="$test_root/power-dotfiles/shell.json"
power_link="$test_root/power-config/shell.json"
mkdir -p "$(dirname "$power_real")" "$(dirname "$power_link")/plugins/araneadev.power"
: >"$(dirname "$power_link")/plugins/araneadev.power/manifest.json"
printf '%s\n' '{"bar": {"layout": {"right": ["omarchy.power"]}}}' >"$power_real"
ln -s "$power_real" "$power_link"
"$repo_root/scripts/repair-shell-config" "$power_link"
test -L "$power_link"
jq -e '.bar.layout.right == ["araneadev.power"]' "$power_real" >/dev/null || {
  cat "$power_real"
  exit 1
}

# --- VPN bar entry: not a clone (no stock id to retarget), inserted right
# after the network entry only once its own manifest is installed (guard:
# $(dirname "$config_file")/plugins/araneadev.vpn/manifest.json), and only
# once (a placed marker, parked by release like the health icon's)
vmarker="$state_root/vpn-widget-placed"
vparked="$state_root/vpn-widget-parked"
rm -f "$vmarker" "$vparked"
cat >"$config" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.network", {"id": "omarchy.tray"}]}}}
EOF
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] == ["araneadev.network", "omarchy.tray"]' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
mkdir -p "$(dirname "$config")/plugins/araneadev.vpn"
: >"$(dirname "$config")/plugins/araneadev.vpn/manifest.json"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] == ["araneadev.network", "araneadev.vpn", "omarchy.tray"]' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
# Not duplicated on a second repair.
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end) | select(. == "araneadev.vpn")] | length == 1' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
# release removes it.
"$repo_root/scripts/release-shell-config" "$config"
jq -e '[.bar.layout.right[]? | (if type == "string" then . else .id end)] | index("araneadev.vpn") == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
test -f "$vmarker"
# It was in the bar: release parks it, and the return (the plugin deployed
# again) puts it back once.
test -f "$vparked"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] == ["araneadev.network", "araneadev.vpn", "omarchy.tray"]' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
test ! -e "$vparked"
test -f "$vmarker"
# Removed by the user while on Aranea: a repair leaves it out.
jq '.bar.layout.right |= map(select((if type == "string" then . else .id end) != "araneadev.vpn"))' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] | index("araneadev.vpn") == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}
# Leaving parks nothing, and returning adds nothing.
"$repo_root/scripts/release-shell-config" "$config"
test ! -e "$vparked"
"$repo_root/scripts/repair-shell-config" "$config"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] | index("araneadev.vpn") == null' "$config" >/dev/null || {
  cat "$config"
  exit 1
}

# Inserted after omarchy.network when the Aranea network clone is not
# installed (a separate dir, so network_installed stays false there).
vpn_only_dir="$test_root/vpn-only"
mkdir -p "$vpn_only_dir/plugins/araneadev.vpn"
: >"$vpn_only_dir/plugins/araneadev.vpn/manifest.json"
vpn_only_cfg="$vpn_only_dir/shell.json"
cat >"$vpn_only_cfg" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.network", {"id": "omarchy.tray"}]}}}
EOF
rm -f "$vmarker"
"$repo_root/scripts/repair-shell-config" "$vpn_only_cfg"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] == ["omarchy.network", "araneadev.vpn", "omarchy.tray"]' "$vpn_only_cfg" >/dev/null || {
  cat "$vpn_only_cfg"
  exit 1
}

# Inserted after an object-form network entry.
vpn_obj_dir="$test_root/vpn-object"
mkdir -p "$vpn_obj_dir/plugins/araneadev.vpn"
: >"$vpn_obj_dir/plugins/araneadev.vpn/manifest.json"
vpn_obj_cfg="$vpn_obj_dir/shell.json"
cat >"$vpn_obj_cfg" <<'EOF'
{"bar": {"layout": {"right": [{"id": "omarchy.network", "x": 1}, {"id": "omarchy.tray"}]}}}
EOF
rm -f "$vmarker"
"$repo_root/scripts/repair-shell-config" "$vpn_obj_cfg"
jq -e '.bar.layout.right == [{"id": "omarchy.network", "x": 1}, {"id": "araneadev.vpn"}, {"id": "omarchy.tray"}]' "$vpn_obj_cfg" >/dev/null || {
  cat "$vpn_obj_cfg"
  exit 1
}

# No network entry at all: appended to the right section's end.
vpn_nonet_dir="$test_root/vpn-no-network"
mkdir -p "$vpn_nonet_dir/plugins/araneadev.vpn"
: >"$vpn_nonet_dir/plugins/araneadev.vpn/manifest.json"
vpn_nonet_cfg="$vpn_nonet_dir/shell.json"
cat >"$vpn_nonet_cfg" <<'EOF'
{"bar": {"layout": {"right": [{"id": "omarchy.tray"}]}}}
EOF
rm -f "$vmarker"
"$repo_root/scripts/repair-shell-config" "$vpn_nonet_cfg"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] == ["omarchy.tray", "araneadev.vpn"]' "$vpn_nonet_cfg" >/dev/null || {
  cat "$vpn_nonet_cfg"
  exit 1
}

# A network entry split across two sections (left carries the araneadev
# clone, right carries the stock id) must only insert araneadev.vpn once,
# into the section vpn_target_section picks first (right, by the fixed
# scan order), never into both.
vpn_split_dir="$test_root/vpn-split"
mkdir -p "$vpn_split_dir/plugins/araneadev.vpn"
: >"$vpn_split_dir/plugins/araneadev.vpn/manifest.json"
vpn_split_cfg="$vpn_split_dir/shell.json"
cat >"$vpn_split_cfg" <<'EOF'
{"bar": {"layout": {"left": ["araneadev.network"], "right": ["omarchy.network", {"id": "omarchy.tray"}]}}}
EOF
rm -f "$vmarker"
"$repo_root/scripts/repair-shell-config" "$vpn_split_cfg"
jq -e '.bar.layout.left == ["araneadev.network"]
  and [.bar.layout.right[] | (if type == "string" then . else .id end)] == ["omarchy.network", "araneadev.vpn", "omarchy.tray"]
  and ([.bar.layout[]? | arrays | .[] | (if type == "string" then . else .id end) | select(. == "araneadev.vpn")] | length) == 1' "$vpn_split_cfg" >/dev/null || {
  cat "$vpn_split_cfg"
  exit 1
}

# Both network ids in the same array: inserted once, after the araneadev
# entry, regardless of which id comes first in the array.
vpn_both_a_dir="$test_root/vpn-both-a"
mkdir -p "$vpn_both_a_dir/plugins/araneadev.vpn"
: >"$vpn_both_a_dir/plugins/araneadev.vpn/manifest.json"
vpn_both_a_cfg="$vpn_both_a_dir/shell.json"
cat >"$vpn_both_a_cfg" <<'EOF'
{"bar": {"layout": {"right": ["araneadev.network", "omarchy.network"]}}}
EOF
rm -f "$vmarker"
"$repo_root/scripts/repair-shell-config" "$vpn_both_a_cfg"
jq -e '.bar.layout.right == ["araneadev.network", {"id": "araneadev.vpn"}, "omarchy.network"]' "$vpn_both_a_cfg" >/dev/null || {
  cat "$vpn_both_a_cfg"
  exit 1
}

vpn_both_b_dir="$test_root/vpn-both-b"
mkdir -p "$vpn_both_b_dir/plugins/araneadev.vpn"
: >"$vpn_both_b_dir/plugins/araneadev.vpn/manifest.json"
vpn_both_b_cfg="$vpn_both_b_dir/shell.json"
cat >"$vpn_both_b_cfg" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.network", "araneadev.network"]}}}
EOF
rm -f "$vmarker"
"$repo_root/scripts/repair-shell-config" "$vpn_both_b_cfg"
jq -e '.bar.layout.right == ["omarchy.network", "araneadev.network", {"id": "araneadev.vpn"}]' "$vpn_both_b_cfg" >/dev/null || {
  cat "$vpn_both_b_cfg"
  exit 1
}

# An existing araneadev.vpn in bare-string form is not duplicated.
vpn_bare_dir="$test_root/vpn-bare"
mkdir -p "$vpn_bare_dir/plugins/araneadev.vpn"
: >"$vpn_bare_dir/plugins/araneadev.vpn/manifest.json"
vpn_bare_cfg="$vpn_bare_dir/shell.json"
cat >"$vpn_bare_cfg" <<'EOF'
{"bar": {"layout": {"right": ["omarchy.network", "araneadev.vpn"]}}}
EOF
rm -f "$vmarker"
"$repo_root/scripts/repair-shell-config" "$vpn_bare_cfg"
jq -e '.bar.layout.right == ["omarchy.network", "araneadev.vpn"]' "$vpn_bare_cfg" >/dev/null || {
  cat "$vpn_bare_cfg"
  exit 1
}

# A symlinked shell.json (dotfile managers): the deploy writes the plugin
# beside the config path the shell uses, not beside the link's target.
vpn_real="$test_root/vpn-dotfiles/shell.json"
vpn_link="$test_root/vpn-config/shell.json"
mkdir -p "$(dirname "$vpn_real")" "$(dirname "$vpn_link")/plugins/araneadev.vpn"
: >"$(dirname "$vpn_link")/plugins/araneadev.vpn/manifest.json"
printf '%s\n' '{"bar": {"layout": {"right": ["omarchy.network"]}}}' >"$vpn_real"
ln -s "$vpn_real" "$vpn_link"
rm -f "$vmarker"
"$repo_root/scripts/repair-shell-config" "$vpn_link"
test -L "$vpn_link"
jq -e '[.bar.layout.right[] | (if type == "string" then . else .id end)] == ["omarchy.network", "araneadev.vpn"]' "$vpn_real" >/dev/null || {
  cat "$vpn_real"
  exit 1
}

echo "shell config contract passed"
