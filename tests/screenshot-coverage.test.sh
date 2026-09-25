#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture_script="$repo_root/scripts/capture-screenshots"
readme="$repo_root/README.md"

mapfile -t surfaces < <(
  sed -n 's/^all_surfaces=(\(.*\))$/\1/p' "$capture_script" | tr ' ' '\n'
)
expected_surfaces=(
  menu menu-submenu menu-search menu-input desktop diagnostics lock plymouth
  btop file-manager neovim notifications network audio bluetooth agents
  power monitor apps favorites recent
  dawn osd
)
expected_hero_frames=(
  lock desktop menu menu-submenu menu-search menu-input apps favorites
  recent notifications network audio bluetooth agents power monitor diagnostics
  btop file-manager neovim
)
[[ "${surfaces[*]}" == "${expected_surfaces[*]}" ]]

for surface in "${surfaces[@]}"; do
  test -f "$repo_root/screenshots/$surface.png"
  if [[ "$surface" == dawn ]]; then
    grep -Eq 'screenshots/dawn\.png|backgrounds/variants/dawn\.png' "$readme"
  else
    grep -Fq "screenshots/$surface.png" "$readme"
  fi
done

test -f "$repo_root/screenshots/dawn.png"
test -f "$repo_root/screenshots/osd.png"
grep -Fq 'ARANEA_OSD_CAPTURE_COMMAND' "$capture_script"

test ! -e "$repo_root/screenshots/idle.png"
test -f "$repo_root/screenshots/hero-showcase.gif"
grep -Fq 'screenshots/hero-showcase.gif' "$readme"
grep -Fq 'build_hero_showcase' "$capture_script"

hero_frames="$(identify "$repo_root/screenshots/hero-showcase.gif" | wc -l)"
[[ "$hero_frames" -eq "${#expected_hero_frames[@]}" ]]

hero_tmp="$(mktemp -d)"
trap 'rm -rf "$hero_tmp"' EXIT
# Use the classic convert/compare binaries rather than the unified `magick`
# wrapper: CI's apt-get imagemagick package is ImageMagick 6, which has no
# `magick` command at all, while `convert`/`compare` work on both IM6 and
# IM7 (as a deprecated but functional compatibility shim).
convert "$repo_root/screenshots/hero-showcase.gif" -coalesce -resize '160x90!' \
  "$hero_tmp/frame-%02d.png" 2>/dev/null
for index in "${!expected_hero_frames[@]}"; do
  convert "$repo_root/screenshots/${expected_hero_frames[$index]}.png" \
    -resize '160x90!' "$hero_tmp/expected.png" 2>/dev/null
  metric="$(
    compare -metric RMSE \
      "$hero_tmp/frame-$(printf '%02d' "$index").png" \
      "$hero_tmp/expected.png" null: 2>&1 || true
  )"
  # IM7's compare shim prints its own deprecation notice on the same stream
  # as the RMSE result; drop it before parsing the "N (n.nnn)" metric line.
  metric="$(grep -v '^WARNING:' <<<"$metric" || true)"
  normalized_metric="${metric##*(}"
  normalized_metric="${normalized_metric%)}"
  awk -v metric="$normalized_metric" 'BEGIN { exit !(metric < 0.03) }'
done

echo "screenshot coverage contract passed (${#surfaces[@]} surfaces)"
