#!/usr/bin/env bash
# Runs the real theme-set and post-boot hooks against a fake installed theme
# in the sandbox HOME: the Aranea branch, the reinstall name, leaving and
# returning, and a deactivated integration.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

stable="$HOME/.config/omarchy/themes/aranea"
current="$HOME/.local/state/omarchy/current/theme"
mkdir -p "$(dirname "$stable")" "$(dirname "$current")"
ln -s "$repo_root" "$stable"
ln -s "$repo_root" "$current"
cfg="$XDG_CONFIG_HOME/omarchy/shell.json"
mkdir -p "$(dirname "$cfg")"
printf '{"bar": {"layout": {"right": ["omarchy.tray"]}}, "plugins": []}\n' > "$cfg"

# `omarchy theme current` must say Aranea for post-boot to run.
fake="$ARANEA_TEST_SANDBOX/fake-bin"
mkdir -p "$fake"
cat > "$fake/omarchy" <<'EOF'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >> "$ARANEA_TEST_SANDBOX/guard.log"
if [[ "$*" == "theme current" ]]; then echo Aranea; fi
exit 0
EOF
chmod +x "$fake/omarchy"
export PATH="$fake:$PATH"

session_link="$XDG_CONFIG_HOME/omarchy/session/aranea.css"
plugin_ids() { jq -c '[.plugins[]? | (if type == "string" then . else .id end)]' "$cfg"; }

# Aranea branch: integrations link from the stable installed theme (spec B3).
"$repo_root/hooks/theme-set" aranea
[[ "$(readlink "$session_link")" == "$stable/integrations/session/omarchy.css" ]] || { echo "session link: $(readlink "$session_link")" >&2; exit 1; }
jq -e '[.plugins[]? | (if type == "string" then . else .id end)] | index("araneadev.lock") != null' "$cfg" >/dev/null || { plugin_ids; exit 1; }

# Reinstall name: still the Aranea branch, nothing released (spec A3).
"$repo_root/hooks/theme-set" aranea-desktop
jq -e '[.plugins[]? | (if type == "string" then . else .id end)] | index("araneadev.lock") != null' "$cfg" >/dev/null || { plugin_ids; exit 1; }

# Leaving with the wallpaper schedule on: units go, the state stays "on" (spec A2).
mkdir -p "$XDG_STATE_HOME/aranea"
printf on > "$XDG_STATE_HOME/aranea/wallpaper-schedule"
"$repo_root/hooks/theme-set" tokyo-night
[[ "$(<"$XDG_STATE_HOME/aranea/wallpaper-schedule")" == on ]]
if grep -Fq 'omarchy plugin disable araneadev.lock' "$ARANEA_TEST_SANDBOX/guard.log"; then
  echo "leaving must not disable the lock over IPC" >&2; exit 1
fi
test -e "$session_link"   # stable links survive leaving

# Returning brings the schedule units back.
"$repo_root/hooks/theme-set" aranea
test -f "$XDG_CONFIG_HOME/systemd/user/aranea-wallpaper-day-night.timer"

# An integration the user deactivated stays off (spec B4).
mkdir -p "$XDG_STATE_HOME/aranea/integrations"
printf inactive > "$XDG_STATE_HOME/aranea/integrations/session"
rm -f "$session_link"
"$repo_root/hooks/theme-set" aranea
test ! -e "$session_link"
"$repo_root/hooks/post-boot"
test ! -e "$session_link"
rm "$XDG_STATE_HOME/aranea/integrations/session"
"$repo_root/hooks/post-boot"
[[ "$(readlink "$session_link")" == "$stable/integrations/session/omarchy.css" ]]

echo "hooks contract passed"
