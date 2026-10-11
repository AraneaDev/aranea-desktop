#!/usr/bin/env bash
# Every interactive window retains decorative closing frames without input.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for file in MenuWindow ClipboardWindow EmojiWindow PolkitWindow ProjectsWindow SettingsWindow; do
  path="$(rg --files "$repo_root/plugins" | rg "/$file.qml$")"
  rg -q 'Aranea.SurfaceMotion' "$path"
  rg -q 'visible: surfaceMotion.present' "$path"
  rg -q 'WlrKeyboardFocus.None' "$path"
  rg -q 'mask: Region' "$path"
  rg -q 'scale: surfaceMotion.scale' "$path"
done
for name in projects settings; do
  rg -q '!surfaceMotion.running' "$repo_root/plugins/araneadev.$name/${name^}Window.qml"
done
# Tooltip native windows use the same passive, whole-bubble presentation.
rg -q 'id: tooltipMotion' "$repo_root/plugins/araneadev.bar/Bar.qml"
rg -q 'visible: tooltipMotion.present' "$repo_root/plugins/araneadev.bar/Bar.qml"
