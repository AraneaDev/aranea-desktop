#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'Name=Aranea' "$repo_root/integrations/cursor/index.theme"
grep -Fq 'Inherits=' "$repo_root/integrations/cursor/index.theme"
grep -Fq 'xcursorgen' "$repo_root/scripts/install-integration"
grep -Fq 'setcursor Aranea' "$repo_root/scripts/install-integration"
grep -Fq 'uwsm/env.d/aranea-cursor' "$repo_root/scripts/install-integration"
grep -Fq 'XCURSOR_THEME=Aranea' "$repo_root/integrations/cursor/uwsm-env"
for cursor in left_ptr.svg hand2.svg watch.svg crosshair.svg; do
  test -f "$repo_root/integrations/cursor/cursors/$cursor"
done
grep -Fq 'BackgroundNormal=' "$repo_root/integrations/qt/kvantum/Aranea/Aranea.kvconfig"
grep -Fq 'selection' "$repo_root/gtk.css"
grep -Fq 'destructive-action' "$repo_root/gtk.css"
grep -Fq 'does not replace' "$repo_root/integrations/icons/README.md"

echo "toolkit contract passed"
