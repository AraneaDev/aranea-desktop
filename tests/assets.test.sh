#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while IFS= read -r path; do
  test -n "$path"
  test -f "$repo_root/$path"
done < <(sed -n 's/^path = "\(.*\)"$/\1/p' "$repo_root/backgrounds/manifest.toml")

test -f "$repo_root/screenshots/hero-showcase.gif"
hero_dimensions="$(identify -format '%wx%h' "$repo_root/screenshots/hero-showcase.gif[0]")"
hero_frames="$(identify "$repo_root/screenshots/hero-showcase.gif" | wc -l)"
[[ "$hero_dimensions" == '1280x720' && "$hero_frames" -eq 21 ]] || {
  hero_info="$hero_dimensions $hero_frames"
  echo "unexpected hero showcase metadata: $hero_info" >&2
  exit 1
}

while IFS= read -r path; do
  test -n "$path"
  test -f "$repo_root/$path"
done < <(rg -o '\]\([^)]*\)' "$repo_root/README.md" | sed 's/^](//; s/)$//' | rg -v '^(https?://|#)')

find "$repo_root/integrations" -type f -name '*.svg' -print0 |
  xargs -0 -n1 xmllint --noout

for path in \
  branding/marks/aranea-primary.svg \
  branding/marks/aranea-glyph.svg \
  branding/marks/aranea-ceremony.svg \
  branding/glyphs/ready.svg \
  branding/glyphs/active.svg \
  branding/glyphs/attention.svg \
  branding/glyphs/warning.svg \
  branding/glyphs/error.svg \
  branding/glyphs/sleep.svg \
  branding/glyphs/power.svg \
  branding/motifs/node-divider.svg \
  branding/motifs/edge-trace.svg \
  branding/motifs/menu-network.svg \
  branding/motifs/node-halo.svg; do
  test -f "$repo_root/$path"
  xmllint --noout "$repo_root/$path"
done

find "$repo_root/backgrounds" "$repo_root/screenshots" -type f \( -name '*.png' -o -name '*.jpg' \) -print0 |
  xargs -0 -n1 identify >/dev/null

echo "asset contract passed"
