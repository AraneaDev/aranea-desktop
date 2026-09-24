#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'Name=Aranea' "$repo_root/integrations/cursor/index.theme"
grep -Fq 'Inherits=' "$repo_root/integrations/cursor/index.theme"
grep -Fq 'xcursorgen' "$repo_root/scripts/install-integration"
grep -Fq 'setcursor Aranea' "$repo_root/scripts/install-integration"
grep -Fq 'uwsm/env.d/aranea-cursor' "$repo_root/scripts/install-integration"
grep -Fq 'local/share}/icons/Aranea' "$repo_root/scripts/install-integration"
grep -Fq 'XCURSOR_THEME=Aranea' "$repo_root/integrations/cursor/uwsm-env"
grep -Fq 'HYPRCURSOR_THEME=Aranea' "$repo_root/integrations/cursor/uwsm-env"
grep -Fq 'hyprcursor-util --create' "$repo_root/scripts/install-integration"
test -f "$repo_root/integrations/cursor/hyprcursor/manifest.hl"
test -f "$repo_root/integrations/cursor/hyprcursor/hyprcursors/left_ptr/meta.hl"
for cursor in left_ptr.svg hand2.svg watch.svg crosshair.svg; do
  test -f "$repo_root/integrations/cursor/cursors/$cursor"
done
if rg -n '#ff5f56|#e6c98a' "$repo_root/integrations/cursor"; then
  echo 'cursor palette contains non-Aranea colors' >&2
  exit 1
fi
grep -Fq '<title>Aranea spider hand cursor</title>' "$repo_root/integrations/cursor/cursors/hand2.svg"
if rg -n 'circle cx="15"|circle cx="17"' "$repo_root/integrations/cursor"; then
  echo 'cursor hand artwork still contains eye dots' >&2
  exit 1
fi
grep -Fq '<title>Aranea spider pointer cursor</title>' "$repo_root/integrations/cursor/cursors/left_ptr.svg"
grep -Fq 'M5 4' "$repo_root/integrations/cursor/cursors/left_ptr.svg"
grep -Fq 'define_size = 32, watch-08.svg' "$repo_root/integrations/cursor/hyprcursor/hyprcursors/watch/meta.hl"
for frame in 01 02 03 04 05 06 07 08; do
  test -f "$repo_root/integrations/cursor/cursors/watch-$frame.svg"
  test -f "$repo_root/integrations/cursor/hyprcursor/hyprcursors/watch/watch-$frame.svg"
  cmp -s "$repo_root/integrations/cursor/cursors/watch-$frame.svg" \
    "$repo_root/integrations/cursor/hyprcursor/hyprcursors/watch/watch-$frame.svg"
done
for cursor in left_ptr hand2 watch crosshair; do
  cmp -s "$repo_root/integrations/cursor/cursors/$cursor.svg" \
    "$repo_root/integrations/cursor/hyprcursor/hyprcursors/$cursor/$cursor.svg"
done
grep -Fq 'BackgroundNormal=' "$repo_root/integrations/qt/kvantum/Aranea/Aranea.kvconfig"
grep -Fq 'selection' "$repo_root/gtk.css"
grep -Fq 'destructive-action' "$repo_root/gtk.css"
grep -Fq 'does not replace' "$repo_root/integrations/icons/README.md"

grep -Fq 'Name=Aranea-icons' "$repo_root/integrations/icons/aranea/index.theme"
grep -Fq 'Inherits=' "$repo_root/integrations/icons/aranea/index.theme"
grep -Fq 'Directories=scalable/places' "$repo_root/integrations/icons/aranea/index.theme"
for icon in folder.svg folder-open.svg; do
  test -f "$repo_root/integrations/icons/aranea/scalable/places/$icon"
done
grep -Fq 'icon-theme "$icon_theme"' "$repo_root/scripts/install-integration"
grep -Fq 'nautilus.icon-view default-zoom-level small' "$repo_root/scripts/install-integration"

echo "toolkit contract passed"
