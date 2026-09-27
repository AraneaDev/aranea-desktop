#!/usr/bin/env bash
# Contract for the generated font icon theme: index.theme wiring, every
# required icon present as a real file with the brand fill colour and a
# generation metadata comment, install-integration --dry-run/--yes plans and
# installs the whole set, and a stale icon is removed from disk and from the
# ownership ledger together.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
theme_root="$repo_root/integrations/icons/aranea"
theme_file="$theme_root/index.theme"
generator="$repo_root/scripts/generate-font-icon-theme"

test -f "$theme_file"
grep -Fq 'morphology Erode Disk:2' "$generator"
test "$(find "$theme_root/scalable" -type l -name '*.svg' | wc -l)" -eq 0
grep -Fq 'Inherits=Yaru-prussiangreen-dark,Adwaita,hicolor' "$theme_file"

contexts=(places devices status actions mimetypes apps)
for context in "${contexts[@]}"; do
  test -d "$theme_root/scalable/$context"
  grep -Fq "scalable/$context" "$theme_file"
done

required_core=(
  places/folder.svg places/folder-open.svg places/user-home.svg places/folder-root.svg
  places/folder-documents.svg places/folder-download.svg places/folder-music.svg
  places/folder-pictures.svg places/folder-videos.svg places/folder-new.svg
  places/go-home.svg places/user-trash.svg places/user-trash-full.svg
  places/user-home-symbolic.svg places/folder-symbolic.svg places/folder-download-symbolic.svg
  places/folder-pictures-symbolic.svg places/folder-videos-symbolic.svg places/user-trash-symbolic.svg
  places/network-workgroup-symbolic.svg
  actions/go-up.svg actions/go-previous.svg actions/go-next.svg actions/view-refresh.svg
  actions/edit-find.svg actions/view-list.svg actions/view-grid.svg
  actions/document-open-recent-symbolic.svg actions/starred-symbolic.svg
  actions/document-new.svg actions/document-open.svg actions/document-save.svg
  actions/edit-copy.svg actions/edit-cut.svg actions/edit-delete.svg actions/application-exit.svg
  devices/computer-desktop.svg devices/drive-harddisk.svg devices/drive-harddisk-system.svg devices/drive-removable-media.svg
  devices/drive-optical.svg devices/media-flash.svg devices/media-sd.svg
  devices/computer.svg devices/computer-laptop.svg devices/network-server.svg devices/network-wireless.svg
  status/emblem-mounted.svg status/emblem-readonly.svg status/emblem-shared.svg
  mimetypes/text-plain.svg
  mimetypes/text-x-generic.svg mimetypes/text-markdown.svg mimetypes/x-office-document.svg
  mimetypes/application-toml.svg mimetypes/application-schema+json.svg mimetypes/application-pdf.svg mimetypes/image-x-generic.svg
  mimetypes/video-x-generic.svg mimetypes/audio-x-generic.svg mimetypes/text-x-script.svg
  mimetypes/text-html.svg mimetypes/application-json.svg mimetypes/application-zip.svg
  mimetypes/application-x-tar.svg mimetypes/application-x-executable.svg mimetypes/application-x-desktop.svg
  apps/accessories-text-editor.svg apps/preferences-system.svg apps/system-file-manager.svg
  apps/utilities-terminal.svg apps/web-browser.svg
)
for icon in "${required_core[@]}"; do
  test -f "$theme_root/scalable/$icon"
  test "$(stat -c '%F' "$theme_root/scalable/$icon")" = "regular file"
  grep -Fq 'fill="#3bff9e"' "$theme_root/scalable/$icon"
  grep -Eq '<metadata>(Source glyph|Composition of font glyphs)' "$theme_root/scalable/$icon"
  if grep -Fq 'stroke=' "$theme_root/scalable/$icon"; then
    exit 1
  fi
done

declare -A command_center_sources=(
  ['places/folder.svg']='Source glyph U+F024B'
  ['apps/utilities-terminal.svg']='Source glyph U+F489'
  ['apps/preferences-system.svg']='Source glyph U+E615'
)
for icon in "${!command_center_sources[@]}"; do
  grep -Fq "${command_center_sources[$icon]}" "$theme_root/scalable/$icon"
done

actual_svg_count="$(find "$theme_root/scalable" -type f -name '*.svg' | wc -l)"
test "$actual_svg_count" -eq "${#required_core[@]}"

dry_run_output="$(bash "$repo_root/scripts/install-integration" --dry-run icons)"
grep -Fq 'scalable/devices/drive-harddisk.svg' <<<"$dry_run_output"
grep -Fq 'scalable/mimetypes/application-pdf.svg' <<<"$dry_run_output"
grep -Fq 'scalable/apps/utilities-terminal.svg' <<<"$dry_run_output"
grep -Eq 'would copy .*scalable/places/folder\.svg ->' <<<"$dry_run_output"
expected_svg_count="$(find "$theme_root/scalable" -type f -name '*.svg' | wc -l)"
installed_svg_count="$(grep -cE 'would copy .*scalable/.+\.svg ->' <<<"$dry_run_output")"
test "$installed_svg_count" -eq "$expected_svg_count"

install_tmp="$(mktemp -d)"
state_tmp="$(mktemp -d)"
fake_bin="$install_tmp/bin"
mkdir -p "$fake_bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/gsettings"
chmod +x "$fake_bin/gsettings"
stale_icon="$install_tmp/icons/Aranea-icons/scalable/legacy/old.svg"
unmanaged_icon="$install_tmp/icons/Aranea-icons/scalable/legacy/user.svg"
mkdir -p "$(dirname "$stale_icon")"
printf '%s\n' stale >"$stale_icon"
printf '%s\n' unmanaged >"$unmanaged_icon"
printf '%s\n' "$stale_icon" >"$state_tmp/managed-files"
XDG_DATA_HOME="$install_tmp" ARANEA_OWNERSHIP_ROOT="$state_tmp" PATH="$fake_bin:$PATH" \
  bash "$repo_root/scripts/install-integration" --yes icons >/dev/null
test ! -e "$stale_icon"
test -e "$unmanaged_icon"
# Removing a stale icon from disk must also drop it from the ownership
# ledger, or aranea-doctor reports a permanent false "repair" for a target
# that was intentionally retired.
if grep -Fqx -- "$stale_icon" "$state_tmp/managed-files"; then
  echo "stale icon was removed from disk but left in the ownership ledger" >&2
  exit 1
fi
rm -rf "$install_tmp" "$state_tmp"

# --- 4d: each icon is rendered by exactly one group; text-x-generic uses its family's glyph
dups="$(sed -n '/^render_group [0-9A-F]/,/[^\\]$/p' "$repo_root/scripts/generate-font-icon-theme" |
  grep -o '[a-z-]*/[A-Za-z0-9+._-]*\.svg' | sort | uniq -d)"
[[ -z "$dups" ]] || {
  echo "rendered twice: $dups" >&2
  exit 1
}
grep -Fq 'Source glyph U+F0F6 ' "$repo_root/integrations/icons/aranea/scalable/mimetypes/text-x-generic.svg"

# --- 4d: generated cursor/icon files are in the ledger; gsettings are saved
# once, before Aranea's first change
gen_tmp="$(mktemp -d)"
gen_bin="$gen_tmp/bin"
mkdir -p "$gen_bin"
cat >"$gen_bin/gsettings" <<'SH'
#!/usr/bin/env bash
if [[ $1 == get ]]; then cat "$GEN_TMP/current-$3" 2>/dev/null; fi
exit 0
SH
cat >"$gen_bin/gtk-update-icon-cache" <<'SH'
#!/usr/bin/env bash
touch "$3/icon-theme.cache"
SH
cat >"$gen_bin/magick" <<'SH'
#!/usr/bin/env bash
touch "${@: -1}"
SH
cat >"$gen_bin/xcursorgen" <<'SH'
#!/usr/bin/env bash
touch "$2"
SH
chmod +x "$gen_bin"/*
printf "'Adwaita'\n" >"$gen_tmp/current-icon-theme"
printf "'Adwaita'\n" >"$gen_tmp/current-cursor-theme"
# Runs install-integration INTEGRATION against the throwaway dirs and stubs.
gen_run() {
  GEN_TMP="$gen_tmp" XDG_DATA_HOME="$gen_tmp/data" XDG_STATE_HOME="$gen_tmp/state" \
    ARANEA_OWNERSHIP_ROOT="$gen_tmp/state/aranea" PATH="$gen_bin:$PATH" \
    bash "$repo_root/scripts/install-integration" --yes "$1" >/dev/null
}
gen_run icons
gen_run cursor
gen_ledger="$gen_tmp/state/aranea/managed-files"
grep -Fqx "$gen_tmp/data/icons/Aranea-icons/icon-theme.cache" "$gen_ledger"
grep -Fqx "$gen_tmp/data/icons/Aranea/cursors/left_ptr" "$gen_ledger"
saved="$gen_tmp/state/aranea/gsettings"
[[ "$(<"$saved/org.gnome.desktop.interface.icon-theme")" == "'Adwaita'" ]]
[[ "$(<"$saved/org.gnome.desktop.interface.cursor-theme")" == "'Adwaita'" ]]
# a reinstall keeps the pre-Aranea values
printf "'Aranea-icons'\n" >"$gen_tmp/current-icon-theme"
gen_run icons
[[ "$(<"$saved/org.gnome.desktop.interface.icon-theme")" == "'Adwaita'" ]]
rm -rf "$gen_tmp"

echo "icon theme contract passed (${#contexts[@]} contexts)"
