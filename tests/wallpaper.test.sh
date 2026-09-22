#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'id = "day"' "$repo_root/backgrounds/manifest.toml"
grep -Fq 'id = "night"' "$repo_root/backgrounds/manifest.toml"
grep -Fq 'id = "monochrome"' "$repo_root/backgrounds/manifest.toml"
for asset in sparse.png dense.png dusk.png monochrome.png ultrawide.png; do
  test -f "$repo_root/backgrounds/variants/$asset"
done

list_output="$($repo_root/scripts/aranea-wallpaper list)"
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

echo "wallpaper contract passed"
