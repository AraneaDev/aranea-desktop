#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture_script="$repo_root/scripts/capture-screenshots"
readme="$repo_root/README.md"

mapfile -t surfaces < <(
  sed -n 's/^all_surfaces=(\(.*\))$/\1/p' "$capture_script" | tr ' ' '\n'
)
for surface in "${surfaces[@]}"; do
  test -f "$repo_root/screenshots/$surface.png"
  grep -Fq "screenshots/$surface.png" "$readme"
done

test -f "$repo_root/screenshots/hero-showcase.gif"
grep -Fq 'screenshots/hero-showcase.gif' "$readme"
grep -Fq 'build_hero_showcase' "$capture_script"
grep -Fq 'omarchy-launch-screensaver force' "$capture_script"

echo "screenshot coverage contract passed (${#surfaces[@]} surfaces)"
