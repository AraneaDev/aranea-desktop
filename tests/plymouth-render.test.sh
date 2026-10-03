#!/usr/bin/env bash
# Contract for tools/render-plymouth-preview: it renders the password prompt
# of Omarchy's Plymouth theme at the device-scaled size (the theme
# background in the corners, the logo centred, bullets at omarchy.script's
# positions inside the entry), honours --bullets and --size, and refuses,
# writing nothing, when omarchy.script's geometry has drifted. Skips cleanly
# without ImageMagick or an Omarchy Plymouth theme.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"
renderer="$repo_root/tools/render-plymouth-preview"

dialog_dir=""
for candidate in ${OMARCHY_PATH:+"$OMARCHY_PATH/default/plymouth"} /usr/share/omarchy/default/plymouth /usr/share/plymouth/themes/omarchy; do
  if [[ -f "$candidate/omarchy.script" && -f "$candidate/entry.png" && -f "$candidate/lock.png" && -f "$candidate/bullet.png" ]]; then
    dialog_dir="$candidate"
    break
  fi
done
if ! command -v magick >/dev/null 2>&1 || [[ -z "$dialog_dir" ]]; then
  skip "plymouth render needs ImageMagick and an Omarchy Plymouth theme"
  exit 0
fi

out="$TMPDIR/out"
mkdir -p "$out"

# Prints the colour of pixel X,Y of FILE as "r g b" (0 to 255).
pixel() {
  magick "$1" -format "%[fx:int(255*p{$2,$3}.r)] %[fx:int(255*p{$2,$3}.g)] %[fx:int(255*p{$2,$3}.b)]\n" info:
}

"$renderer" --output "$out/boot.png" --dialog-dir "$dialog_dir" >/dev/null
test "$(magick identify -format '%wx%h' "$out/boot.png")" = 3840x2160

# The theme background (#08090b in colors.toml) fills the corners.
test "$(pixel "$out/boot.png" 0 0)" = "8 9 11"
test "$(pixel "$out/boot.png" 3839 2159)" = "8 9 11"

# The 640 px logo is centred in the 1920x1080 window and scaled by 2: its
# box (1280..2559, 440..1719) holds bright spider pixels.
test "$(magick "$out/boot.png" -crop 1280x1280+1280+440 -format '%[fx:int(255*maxima.g)]' info:)" -gt 200

# The first bullet: 7x7 at (entry.x + 20, entry.y + 24 - 3.5) = (837, 920)
# in the window, centred near (1681, 1847) once scaled.
read -r r g b < <(pixel "$out/boot.png" 1681 1847)
((r > 200 && g > 200 && b > 200))

# No bullets: the same spot is the entry's dark fill.
"$renderer" --output "$out/empty.png" --dialog-dir "$dialog_dir" --bullets 0 >/dev/null
read -r r g b < <(pixel "$out/empty.png" 1681 1847)
((r < 80 && g < 80 && b < 80))

# A 1x render is the logical window.
"$renderer" --output "$out/small.png" --dialog-dir "$dialog_dir" --scale 1 --size 1280x800 >/dev/null
test "$(magick identify -format '%wx%h' "$out/small.png")" = 1280x800

# Drifted geometry in omarchy.script: refused, nothing written.
drift="$TMPDIR/drift"
mkdir -p "$drift"
cp "$dialog_dir"/{entry,lock,bullet}.png "$drift/"
sed 's/logo.image.GetHeight() + 40;/logo.image.GetHeight() + 60;/' "$dialog_dir/omarchy.script" >"$drift/omarchy.script"
if "$renderer" --output "$out/drift.png" --dialog-dir "$drift" 2>"$out/drift.err"; then
  echo "drifted omarchy.script was accepted" >&2
  exit 1
fi
grep -Fq 'no longer contains' "$out/drift.err"
test ! -e "$out/drift.png"
test -z "$(find "$out" -name '.render-plymouth.*')"

# Bad arguments are refused.
if "$renderer" --output "$out/bad.png" --bullets 22 2>/dev/null; then
  echo "--bullets 22 was accepted" >&2
  exit 1
fi

# The capture script renders the boot screen with it, not static artwork,
# and fails closed: a render that fails leaves no screenshot.
code_grep "$repo_root/scripts/capture-screenshots" 'tools/render-plymouth-preview'
"$repo_root/scripts/capture-screenshots" --surface plymouth --output "$out/capture" >/dev/null
test "$(magick identify -format '%wx%h' "$out/capture/plymouth.png")" = 3840x2160
mkdir -p "$TMPDIR/omarchy/default"
ln -s "$drift" "$TMPDIR/omarchy/default/plymouth"
if OMARCHY_PATH="$TMPDIR/omarchy" "$repo_root/scripts/capture-screenshots" --surface plymouth --output "$out/failed" >/dev/null 2>&1; then
  echo "a failed plymouth render still captured" >&2
  exit 1
fi
test ! -e "$out/failed/plymouth.png"

echo "plymouth render contract passed"
