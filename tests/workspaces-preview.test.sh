#!/usr/bin/env bash
# The real workspace panel must use caller-selected art in its inert host,
# including paths that need URL escaping, and preserve output on bad input.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"
renderer="$repo_root/tools/render-settings-preview"
out="$TMPDIR/shots"
mkdir -p "$out"

shell_dir="$(sandbox_inherited_value ARANEA_QML_SHELL_DIR)"
shell_dir="${shell_dir:-/usr/share/omarchy/shell}"
quickshell_bin=""
while IFS= read -r candidate; do
  [[ "$candidate" == */tests/guard-bin/* ]] && continue
  quickshell_bin="$candidate"
  break
done < <(type -ap quickshell 2>/dev/null || true)
if [[ -z "$quickshell_bin" || ! -f "$shell_dir/Commons/qmldir" ]] || ! command -v magick >/dev/null; then
  skip "workspace preview requires Quickshell, Omarchy and ImageMagick"
  exit 0
fi
export ARANEA_SETTINGS_PREVIEW_QUICKSHELL="$quickshell_bin" ARANEA_QML_SHELL_DIR="$shell_dir"

# A relative filename with spaces, quotes and URL-reserved characters must
# reach the Image intact. A solid colour makes the expected pixels literal.
art_dir="$TMPDIR/art with spaces"
art_name="selected 'wallpaper' #?%.png"
mkdir -p "$art_dir"
magick -size 160x90 xc:'#14283c' "$art_dir/$art_name"
(cd "$art_dir" && "$renderer" --fixture workspaces --output "$out/selected.png" --background "$art_name")
[[ "$(magick identify -format '%wx%h' "$out/selected.png")" == 1440x810 ]]
for point in '0,0' '1439,809'; do
  [[ "$(magick "$out/selected.png" -format "%[pixel:p{$point}]" info:)" == 'srgba(20,40,60,1)' ]]
done
# The production WorkspacePanel still draws its header and workspace rows;
# selecting a background must not replace the panel with an artwork grab.
[[ "$(magick "$out/selected.png" -crop 420x240+36+55 +repage -fx 'min(r,min(g,b))' -format '%[fx:int(255*maxima)]' info:)" -gt 180 ]]

# An inert preview uses repository art by default, even if HOME advertises
# another current background. The visible corner must match Silken Vault.
mkdir -p "$HOME/.local/state/omarchy/current"
ln -s "$art_dir/$art_name" "$HOME/.local/state/omarchy/current/background"
"$renderer" --fixture workspaces --output "$out/default.png"
for channel in r g b; do
  expected="$(magick "$repo_root/backgrounds/variants/silken-vault.png" -format "%[fx:int(255*p{0,0}.$channel)]" info:)"
  actual="$(magick "$out/default.png" -format "%[fx:int(255*p{0,0}.$channel)]" info:)"
  ((actual >= expected - 2 && actual <= expected + 2))
done

# A missing current link must fall back even when its parent already exists.
capture="$repo_root/scripts/capture-screenshots"
rm "$HOME/.local/state/omarchy/current/background"
"$capture" --surface workspaces --output "$out/capture-fallback"
[[ "$(magick "$out/capture-fallback/workspaces.png" -format '%[pixel:p{0,0}]' info:)" == "$(magick "$out/default.png" -format '%[pixel:p{0,0}]' info:)" ]]
ln -s "$art_dir/$art_name" "$HOME/.local/state/omarchy/current/background"

# Captures default to the collection artwork even when the desktop differs.
capture="$repo_root/scripts/capture-screenshots"
"$capture" --surface workspaces --output "$out/capture-current"
[[ "$(magick "$out/capture-current/workspaces.png" -format '%[pixel:p{0,0}]' info:)" == "$(magick "$out/default.png" -format '%[pixel:p{0,0}]' info:)" ]]

# The legacy capture override cannot change collection artwork.
ARANEA_CAPTURE_BACKGROUND="$art_dir/missing.png" "$capture" --surface workspaces --output "$out/fixed-background"
[[ "$(magick "$out/fixed-background/workspaces.png" -format '%[pixel:p{0,0}]' info:)" == "$(magick "$out/default.png" -format '%[pixel:p{0,0}]' info:)" ]]

# Invalid files must fail without replacing a previously published frame.
printf 'not an image' >"$art_dir/corrupt.png"
cp "$art_dir/$art_name" "$art_dir/unreadable.png"
chmod 000 "$art_dir/unreadable.png"
bad_backgrounds=('' "$art_dir/missing.png" "$art_dir" "$art_dir/corrupt.png")
# A privileged runner may still read mode 000; only an unreadable file is invalid.
[[ -r "$art_dir/unreadable.png" ]] || bad_backgrounds+=("$art_dir/unreadable.png")
for background in "${bad_backgrounds[@]}"; do
  printf old >"$out/preserved.png"
  rc=0
  "$renderer" --fixture workspaces --output "$out/preserved.png" --background "$background" >"$TMPDIR/error.log" 2>&1 || rc=$?
  [[ "$rc" == 1 && "$(cat "$out/preserved.png")" == old ]]
done
rc=0
"$renderer" --fixture workspaces --output "$out/preserved.png" --background >"$TMPDIR/error.log" 2>&1 || rc=$?
[[ "$rc" == 2 && "$(cat "$out/preserved.png")" == old ]]
[[ -z "$(find "$out" -name '.render-settings.*')" ]]
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
echo 'workspace preview background contract passed'
