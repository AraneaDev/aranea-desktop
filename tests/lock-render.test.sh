#!/usr/bin/env bash
# Contract for tools/render-lock-preview: the real LockView rendered
# offscreen at the device size (dark corners, the mint-to-violet field
# outline, the stand-in clock and its date in LockView's own format), never
# through the session lock, failing closed (a missing background or shell
# writes nothing, also through scripts/capture-screenshots). The render
# skips without quickshell or the Omarchy shell; fail-closed checks always run.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"
renderer="$repo_root/tools/render-lock-preview"
out="$TMPDIR/out"
mkdir -p "$out"

# The renderer never touches the session lock or the running shell.
if code_grep "$renderer" 'WlSessionLock' || code_grep "$renderer" 'omarchy-shell' || code_grep "$renderer" 'loginctl'; then
  echo "render-lock-preview must not use the session lock or the running shell" >&2
  exit 1
fi
code_grep "$renderer" 'QT_QPA_PLATFORM=offscreen'
code_grep "$repo_root/scripts/capture-screenshots" 'tools/render-lock-preview'
# The stand-in date uses LockView's own format: editing one without the
# other fails here.
code_grep "$repo_root/plugins/araneadev.lock/LockView.qml" 'Qt.formatDate(now, "dddd • dd MMMM")'
code_grep "$renderer" '"dddd • dd MMMM"'

# Fail closed: no shell, no background.
if "$renderer" --output "$out/none.png" --shell-dir "$TMPDIR/no-shell" 2>/dev/null; then
  echo "a missing shell was accepted" >&2
  exit 1
fi
test ! -e "$out/none.png"
if OMARCHY_PATH="$TMPDIR/no-omarchy" "$repo_root/scripts/capture-screenshots" --surface lock --output "$out/failed" >/dev/null 2>&1; then
  echo "a failed lock render still captured" >&2
  exit 1
fi
test ! -e "$out/failed/lock.png"

shell_dir="$(sandbox_inherited_value ARANEA_QML_SHELL_DIR)"
shell_dir="${shell_dir:-${OMARCHY_PATH:-/usr/share/omarchy}/shell}"
if "$renderer" --output "$out/none.png" --shell-dir "$shell_dir" --background "$TMPDIR/missing.png" 2>/dev/null; then
  echo "a missing background was accepted" >&2
  exit 1
fi
test ! -e "$out/none.png"

# The real quickshell: the sandbox puts a guard stub of that name first.
quickshell_bin=""
while IFS= read -r candidate; do
  [[ "$candidate" == */tests/guard-bin/* ]] && continue
  quickshell_bin="$candidate"
  break
done < <(type -ap quickshell 2>/dev/null || true)
if [[ -z "$quickshell_bin" || ! -f "$shell_dir/Commons/qmldir" ]] || ! command -v magick >/dev/null 2>&1; then
  skip "lock render needs quickshell, ImageMagick and the Omarchy shell at $shell_dir"
  echo "lock render contract passed (fail-closed checks only)"
  exit 0
fi

# The sandbox home's current theme is this repository, as after an install.
mkdir -p "$HOME/.local/state/omarchy/current"
ln -s "$repo_root" "$HOME/.local/state/omarchy/current/theme"
ln -s "$repo_root/backgrounds/background-night.png" "$HOME/.local/state/omarchy/current/background"

"$renderer" --output "$out/lock.png" --shell-dir "$shell_dir" --quickshell "$quickshell_bin" >/dev/null
test "$(magick identify -format '%wx%h' "$out/lock.png")" = 3840x2160
test -z "$(find "$out" -name '.render-lock.*')"

# Prints the largest value of fx expression EXPR (0 to 255) over the
# WxH+X+Y region of the render.
region_max() {
  magick "$out/lock.png" -crop "$1" +repage -fx "$2" -format '%[fx:int(255*maxima)]' info:
}

# The corners are the dark lock overlay.
test "$(region_max 40x40+0+0 'max(r,max(g,b))')" -lt 60
# The field outline across the middle: mint (green well above red) at its
# left end, violet (blue well above green) at its right end.
test "$(region_max 400x200+1000+980 'g-r')" -gt 80
test "$(region_max 400x200+2440+980 'b-g')" -gt 80
# The stand-in clock below the field draws bright text.
test "$(region_max 600x200+1620+1180 'min(r,min(g,b))')" -gt 200

# A second render at another size and scale.
"$renderer" --output "$out/small.png" --shell-dir "$shell_dir" --quickshell "$quickshell_bin" --size 1920x1200 --scale 2 >/dev/null
test "$(magick identify -format '%wx%h' "$out/small.png")" = 1920x1200

echo "lock render contract passed"
