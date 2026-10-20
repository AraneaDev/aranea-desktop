#!/usr/bin/env bash
# Contract for the World Clock globe's generated assets: rebuilding them with
# tools/build-worldclock-globe reproduces the committed land mask and shader
# pack byte for byte, and the mask is a 2048x1024 equirectangular map (white
# land, transparent sea) with land and sea where the planet has them.
# Skips (exit 0; 1 with ARANEA_CHECK_REQUIRE_ALL=1) without node, qsb or
# ImageMagick.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

plugin="$repo_root/plugins/araneadev.worldclock"
require_all="$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)"
if ! command -v node >/dev/null || [[ ! -x /usr/lib/qt6/bin/qsb ]] || ! command -v magick >/dev/null; then
  echo "SKIP: the World Clock asset contract needs node, /usr/lib/qt6/bin/qsb and magick"
  [[ "$require_all" == 1 ]] && exit 1
  exit 0
fi

out="$TMPDIR/worldclock-assets"
"$repo_root/tools/build-worldclock-globe" --out "$out"
cmp "$out/land.png" "$plugin/land.png"
cmp "$out/shaders/globe.frag.qsb" "$plugin/shaders/globe.frag.qsb"

[[ "$(magick identify -format '%wx%h' "$plugin/land.png")" == 2048x1024 ]]

# Alpha (0..255) of the mask at LON, LAT degrees.
alpha_at() {
  local x y
  x="$(awk -v lon="$1" 'BEGIN { printf "%d", (lon + 180) / 360 * 2048 }')"
  y="$(awk -v lat="$2" 'BEGIN { printf "%d", (90 - lat) / 180 * 1024 }')"
  magick "$plugin/land.png" -format "%[fx:round(255*p{$x,$y}.a)]" info:
}
# Land: central Africa, Brazil, Siberia, Australia.
for point in "20 0" "-55 -10" "100 60" "135 -25"; do
  # shellcheck disable=SC2086
  [[ "$(alpha_at $point)" == 255 ]] || {
    echo "expected land at $point" >&2
    exit 1
  }
done
# Sea: the mid Atlantic, the central Pacific, the Indian Ocean.
for point in "-30 0" "-150 0" "80 -30"; do
  # shellcheck disable=SC2086
  [[ "$(alpha_at $point)" == 0 ]] || {
    echo "expected sea at $point" >&2
    exit 1
  }
done
echo "worldclock assets ok"
