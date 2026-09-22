#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'id = "day"' "$repo_root/backgrounds/manifest.toml"
grep -Fq 'id = "night"' "$repo_root/backgrounds/manifest.toml"
grep -Fq 'id = "monochrome"' "$repo_root/backgrounds/manifest.toml"
for asset in sparse.png dense.png dusk.png monochrome.png ultrawide.png; do
  test -f "$repo_root/backgrounds/variants/$asset"
done

list_output="$("$repo_root/scripts/aranea-wallpaper" list)"
grep -Fq 'day' <<<"$list_output"
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
ARANEA_SYSTEMD_USER_DIR="$unit_root" ARANEA_STATE_ROOT="$schedule_state" ARANEA_SYSTEMCTL=/bin/true \
  "$repo_root/scripts/aranea-wallpaper" schedule on >/dev/null
test -f "$unit_root/aranea-wallpaper-day-night.timer"
test -f "$unit_root/aranea-wallpaper-day-night.service"
grep -Fq '07:00:00' "$unit_root/aranea-wallpaper-day-night.timer"
grep -Fq '19:00:00' "$unit_root/aranea-wallpaper-day-night.timer"
grep -Fq 'ExecStart=%h/.local/state/omarchy/current/theme/scripts/aranea-wallpaper set-day-night' "$unit_root/aranea-wallpaper-day-night.service"
grep -Fq 'wallpaper schedule: on' <(ARANEA_STATE_ROOT="$schedule_state" "$repo_root/scripts/aranea-wallpaper" schedule status)
ARANEA_SYSTEMD_USER_DIR="$unit_root" ARANEA_STATE_ROOT="$schedule_state" ARANEA_SYSTEMCTL=/bin/true \
  "$repo_root/scripts/aranea-wallpaper" schedule off >/dev/null
test ! -e "$unit_root/aranea-wallpaper-day-night.timer"
test ! -e "$unit_root/aranea-wallpaper-day-night.service"
rm -rf "$unit_root" "$schedule_state"

echo "wallpaper contract passed"
