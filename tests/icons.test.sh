#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
theme_root="$repo_root/integrations/icons/aranea"
theme_file="$theme_root/index.theme"

test -f "$theme_file"
test "$(find "$theme_root/scalable" -type l -name '*.svg' | wc -l)" -eq 0
duplicate_hashes="$(find "$theme_root/scalable" -type f -name '*.svg' -exec sha256sum {} + | awk '{print $1}' | sort | uniq -d)"
test -z "$duplicate_hashes"
if command -v rsvg-convert >/dev/null 2>&1; then
  rendered_tmp="$(mktemp -d)"
  trap 'rm -rf "$rendered_tmp"' EXIT
  while IFS= read -r svg; do
    png="$rendered_tmp/${svg#"$theme_root/scalable/"}"
    png="${png%.svg}.png"
    mkdir -p "$(dirname "$png")"
    rsvg-convert -w 64 -h 64 -o "$png" "$svg"
  done < <(find "$theme_root/scalable" -type f -name '*.svg' | sort)
  rendered_duplicates="$(find "$rendered_tmp" -type f -name '*.png' -exec sha256sum {} + | awk '{print $1}' | sort | uniq -d)"
  test -z "$rendered_duplicates"
fi
grep -Fq 'Inherits=Yaru-prussiangreen-dark,Adwaita,hicolor' "$theme_file"

contexts=(places devices status actions mimetypes apps)
for context in "${contexts[@]}"; do
  test -d "$theme_root/scalable/$context"
  grep -Fq "scalable/$context" "$theme_file"
done

required_wave2_3=(
  actions/system-shutdown.svg actions/system-reboot.svg actions/system-log-out.svg
  status/battery.svg status/battery-low.svg status/battery-charging.svg
  status/audio-volume-high.svg status/audio-volume-muted.svg status/video-display.svg
  status/input-keyboard.svg status/bluetooth.svg status/network-wired.svg
  status/notification.svg status/system-lock-screen.svg status/emblem-synchronized.svg
  apps/utilities-terminal.svg apps/accessories-text-editor.svg apps/web-browser.svg
  apps/preferences-system.svg apps/applications-multimedia.svg apps/applications-development.svg
)
for icon in "${required_wave2_3[@]}"; do
  test -f "$theme_root/scalable/$icon"
done

required_distinct=(
  places/folder-new.svg places/folder-visiting.svg places/folder-documents.svg places/folder-download.svg places/folder-music.svg
  places/folder-pictures.svg places/folder-videos.svg places/folder-publicshare.svg
  devices/drive-multidisk.svg devices/drive-nvme.svg devices/media-memory.svg
  devices/computer-desktop.svg devices/network-workgroup.svg
  status/battery-full.svg status/battery-medium.svg status/battery-caution.svg
  status/audio-volume-medium.svg status/audio-volume-low.svg status/input-mouse.svg
  status/input-touchpad.svg status/video-projector.svg status/display-brightness.svg
  status/network-wireless.svg status/network-vpn.svg
  mimetypes/x-office-document.svg mimetypes/application-vnd.ms-excel.svg
  mimetypes/application-vnd.ms-powerpoint.svg apps/system-file-manager.svg
  actions/media-record.svg actions/media-eject.svg
)
for icon in "${required_distinct[@]}"; do
  test -f "$theme_root/scalable/$icon"
  test "$(stat -c '%F' "$theme_root/scalable/$icon")" = "regular file"
done

required_wave1=(
  places/folder.svg places/folder-open.svg places/user-home.svg places/folder-root.svg
  actions/go-up.svg actions/go-previous.svg actions/go-next.svg actions/view-refresh.svg
  actions/edit-find.svg actions/view-list.svg actions/view-grid.svg
  places/user-trash.svg places/user-trash-full.svg
  devices/drive-harddisk.svg devices/drive-harddisk-system.svg devices/drive-removable-media.svg
  devices/drive-optical.svg devices/media-flash.svg devices/media-sd.svg
  devices/computer.svg devices/computer-laptop.svg devices/network-server.svg devices/network-wireless.svg
  status/emblem-mounted.svg status/emblem-readonly.svg status/emblem-shared.svg
  mimetypes/text-x-generic.svg mimetypes/application-pdf.svg mimetypes/image-x-generic.svg
  mimetypes/video-x-generic.svg mimetypes/audio-x-generic.svg mimetypes/text-x-script.svg
  mimetypes/text-html.svg mimetypes/application-json.svg mimetypes/application-zip.svg
  mimetypes/application-x-tar.svg mimetypes/application-x-executable.svg mimetypes/application-x-desktop.svg
)
for icon in "${required_wave1[@]}"; do
  test -f "$theme_root/scalable/$icon"
done

dry_run_output="$(bash "$repo_root/scripts/install-integration" --dry-run icons)"
grep -Fq 'scalable/devices/drive-harddisk.svg' <<<"$dry_run_output"
grep -Fq 'scalable/mimetypes/application-pdf.svg' <<<"$dry_run_output"
grep -Fq 'scalable/apps/utilities-terminal.svg' <<<"$dry_run_output"
expected_svg_count="$(find "$theme_root/scalable" -type f -name '*.svg' | wc -l)"
installed_svg_count="$(grep -cE 'would link .*scalable/.+\.svg ->' <<<"$dry_run_output")"
test "$installed_svg_count" -eq "$expected_svg_count"

echo "icon theme contract passed (${#contexts[@]} contexts)"
