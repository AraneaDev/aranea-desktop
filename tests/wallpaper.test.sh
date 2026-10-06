#!/usr/bin/env bash
# Contract for scripts/aranea-wallpaper: every manifest variant exists and
# is listed, an unknown wallpaper is rejected, set/motion apply through the
# configured applier, and the day/night schedule writes and removes its
# systemd timer/service and honours a configured time window when picking
# the current phase.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

grep -Fq 'id = "day"' "$repo_root/backgrounds/manifest.toml"
grep -Fq 'id = "dawn"' "$repo_root/backgrounds/manifest.toml"
grep -Fq 'id = "night"' "$repo_root/backgrounds/manifest.toml"
grep -Fq 'id = "monochrome"' "$repo_root/backgrounds/manifest.toml"
for asset in dawn.png sparse.png dense.png dusk.png monochrome.png ultrawide.png; do
  test -f "$repo_root/backgrounds/variants/$asset"
done

list_output="$("$repo_root/scripts/aranea-wallpaper" list)"
grep -Fq 'day' <<<"$list_output"
grep -Fq 'dawn' <<<"$list_output"
grep -Fq 'monochrome' <<<"$list_output"

if "$repo_root/scripts/aranea-wallpaper" set invalid 2>"$ARANEA_TEST_SANDBOX/wallpaper-error"; then
  echo "invalid wallpaper unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown wallpaper' "$ARANEA_TEST_SANDBOX/wallpaper-error"
rm -f "$ARANEA_TEST_SANDBOX/wallpaper-error"

state_root="$(mktemp -d)"
motion_output="$(ARANEA_STATE_ROOT="$state_root" "$repo_root/scripts/aranea-wallpaper" motion off)"
grep -Fq 'motion: off' <<<"$motion_output"

applied_output="$(ARANEA_WALLPAPER_APPLIER=/bin/echo "$repo_root/scripts/aranea-wallpaper" set day)"
grep -Fq 'backgrounds/background-day.png' <<<"$applied_output"

unit_root="$(mktemp -d)"
schedule_state="$(mktemp -d)"
config_root="$(mktemp -d)"
ARANEA_SYSTEMD_USER_DIR="$unit_root" ARANEA_STATE_ROOT="$schedule_state" XDG_CONFIG_HOME="$config_root" ARANEA_SYSTEMCTL=/bin/true \
  "$repo_root/scripts/aranea-wallpaper" schedule on >/dev/null
test -f "$unit_root/aranea-wallpaper-day-night.timer"
test -f "$unit_root/aranea-wallpaper-day-night.service"
grep -Fq '06:00:00' "$unit_root/aranea-wallpaper-day-night.timer"
grep -Fq '08:00:00' "$unit_root/aranea-wallpaper-day-night.timer"
grep -Fq '18:00:00' "$unit_root/aranea-wallpaper-day-night.timer"
grep -Fq '20:00:00' "$unit_root/aranea-wallpaper-day-night.timer"
grep -Fq 'set-phase' "$unit_root/aranea-wallpaper-day-night.service"
grep -Fq 'wallpaper schedule: on' <(XDG_CONFIG_HOME="$config_root" ARANEA_STATE_ROOT="$schedule_state" "$repo_root/scripts/aranea-wallpaper" schedule status)
ARANEA_SYSTEMD_USER_DIR="$unit_root" ARANEA_STATE_ROOT="$schedule_state" XDG_CONFIG_HOME="$config_root" ARANEA_SYSTEMCTL=/bin/true \
  "$repo_root/scripts/aranea-wallpaper" schedule configure 05:30 08:00 18:30 21:00 >/dev/null
grep -Fq '05:30' "$config_root/aranea/wallpaper-schedule.conf"
grep -Fq '21:00:00' "$unit_root/aranea-wallpaper-day-night.timer"
phase_output="$(ARANEA_NOW=19:00 ARANEA_WALLPAPER_DRY_RUN=1 XDG_CONFIG_HOME="$config_root" "$repo_root/scripts/aranea-wallpaper" set-phase)"
grep -Fq 'variants/dusk.png' <<<"$phase_output"
ARANEA_SYSTEMD_USER_DIR="$unit_root" ARANEA_STATE_ROOT="$schedule_state" XDG_CONFIG_HOME="$config_root" ARANEA_SYSTEMCTL=/bin/true \
  "$repo_root/scripts/aranea-wallpaper" schedule off >/dev/null
test ! -e "$unit_root/aranea-wallpaper-day-night.timer"
test ! -e "$unit_root/aranea-wallpaper-day-night.service"
rm -rf "$unit_root" "$schedule_state" "$config_root"

# --- 4d: only [[wallpapers]] blocks count, and ids are compared as text
wp_manifest="$(mktemp)"
cat >"$wp_manifest" <<'TOML'
[[wallpapers]]
id="day"
path = "backgrounds/day.png"

[other]
path = "not-a-wallpaper.png"
TOML
listed="$(ARANEA_WALLPAPER_MANIFEST="$wp_manifest" "$repo_root/scripts/aranea-wallpaper" list)"
[[ "$listed" == $'day\tbackgrounds/day.png' ]] || {
  echo "list: $listed" >&2
  exit 1
}
regex_out="$(ARANEA_WALLPAPER_MANIFEST="$wp_manifest" ARANEA_WALLPAPER_DRY_RUN=1 "$repo_root/scripts/aranea-wallpaper" set 'd.*' 2>&1 || true)"
grep -Fq 'Unknown wallpaper: d.*' <<<"$regex_out"
exact_out="$(ARANEA_WALLPAPER_MANIFEST="$wp_manifest" ARANEA_WALLPAPER_DRY_RUN=1 "$repo_root/scripts/aranea-wallpaper" set day 2>&1 || true)"
grep -Fq "backgrounds/day.png" <<<"$exact_out"
bs_out="$(ARANEA_WALLPAPER_MANIFEST="$wp_manifest" ARANEA_WALLPAPER_DRY_RUN=1 "$repo_root/scripts/aranea-wallpaper" set 'da\y' 2>&1 || true)"
grep -Fq 'Unknown wallpaper: da\y' <<<"$bs_out"
rm -f "$wp_manifest"

# Optional catalog is machine-readable; the default text list stays intact.
"$repo_root/scripts/aranea-wallpaper" list --json | jq -e 'length == 8 and all(.[]; (.path | startswith("/")) and .available)' >/dev/null
# Missing current-background owner reports unavailable, never last selection.
"$repo_root/scripts/aranea-wallpaper" status --json | jq -e '.activeId == null and .availability == "unavailable"' >/dev/null

# Omarchy stages the active theme separately from the installed timer owner.
current="$HOME/.local/state/omarchy/current"
stable="$HOME/.config/omarchy/themes/aranea"
mkdir -p "$current/theme/backgrounds" "$stable/backgrounds"
cp "$repo_root/backgrounds/background-day.png" "$current/theme/backgrounds/background-day.png"
cp "$repo_root/backgrounds/background-day.png" "$stable/backgrounds/background-day.png"
printf 'aranea\n' >"$current/theme.name"
for theme_root in "$current/theme" "$stable"; do
  ln -sfn "$theme_root/backgrounds/background-day.png" "$current/background"
  "$repo_root/scripts/aranea-wallpaper" status --json | jq -e '.activeId == "day" and .availability == "available"' >/dev/null
done
# A foreign theme, modified staged asset or arbitrary custom copy stays unknown.
printf 'other\n' >"$current/theme.name"
"$repo_root/scripts/aranea-wallpaper" status --json | jq -e '.activeId == null' >/dev/null
printf 'aranea\n' >"$current/theme.name"
printf 'different image' >"$stable/backgrounds/background-day.png"
"$repo_root/scripts/aranea-wallpaper" status --json | jq -e '.activeId == null' >/dev/null
cp "$repo_root/backgrounds/background-day.png" "$HOME/custom-day.png"
ln -sfn "$HOME/custom-day.png" "$current/background"
"$repo_root/scripts/aranea-wallpaper" status --json | jq -e '.activeId == null and .availability == "available"' >/dev/null
echo "wallpaper contract passed"
