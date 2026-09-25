#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

if "$repo_root/scripts/aranea-wallpaper" set invalid 2>"$repo_root/tests/.wallpaper-error"; then
  echo "invalid wallpaper unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown wallpaper' "$repo_root/tests/.wallpaper-error"
rm -f "$repo_root/tests/.wallpaper-error"

state_root="$(mktemp -d)"
trap 'rm -rf "$state_root"' EXIT
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

echo "wallpaper contract passed"
