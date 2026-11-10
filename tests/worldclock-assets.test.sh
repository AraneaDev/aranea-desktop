#!/usr/bin/env bash
# Contract for the World Clock globe's generated assets: rebuilding them with
# tools/build-worldclock-globe reproduces the committed land mask and shader
# pack (exact decoded pixels and shader bytes), and the mask is a 2048x1024
# equirectangular map (white land, transparent sea) with land and sea where
# the planet has them.
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
# PNG compression can differ across zlib builds. Compare dimensions and every
# decoded RGBA byte, including the colour channels of transparent sea pixels.
magick "$plugin/land.png" -depth 8 "RGBA:$out/expected.rgba"
# Tests whether a PNG has the exact committed mask dimensions and RGBA pixels.
same_mask() {
  [[ "$(magick identify -format '%wx%h' "$1")" == 2048x1024 ]] || return 1
  magick "$1" -depth 8 "RGBA:$out/actual.rgba" || return 1
  cmp -s "$out/expected.rgba" "$out/actual.rgba"
}
same_mask "$out/land.png"

# Controls: lossless re-encoding must pass, while one changed pixel must fail.
magick "$out/land.png" -define png:compression-level=0 "PNG32:$out/recompressed.png"
if cmp -s "$out/land.png" "$out/recompressed.png"; then
  echo "compression control did not change the PNG encoding" >&2
  exit 1
fi
same_mask "$out/recompressed.png"
magick "$out/land.png" -fill '#ff0000ff' -draw 'point 0,0' "PNG32:$out/changed.png"
if same_mask "$out/changed.png"; then
  echo "mask comparison accepted a changed pixel" >&2
  exit 1
fi
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
