#!/usr/bin/env bash
# Production MenuSurface capture in a scratch offscreen host. Removing
# showcase isolation, geometry, or capture routing must fail this contract.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
quickshell_bin=""
while IFS= read -r candidate; do
  [[ "$candidate" == */tests/guard-bin/* ]] && continue
  quickshell_bin="$candidate"
  break
done < <(type -ap quickshell 2>/dev/null || true)
if [[ -z "$quickshell_bin" || ! -f /usr/share/omarchy/shell/Commons/qmldir ]] || ! command -v magick >/dev/null; then
  echo 'SKIP: menu preview requires Quickshell, Omarchy and ImageMagick'
  exit 0
fi
out="$ARANEA_TEST_SANDBOX/shots"
for fixture in mixed no-match no-compositor vanished actions action-pending action-error action-long-label; do
  ARANEA_MENU_PREVIEW_QUICKSHELL="$quickshell_bin" "$repo_root/scripts/capture-screenshots" --surface "menu-search-$fixture" --output "$out"
  [[ "$(magick identify -format '%w' "$out/menu-search-$fixture.png")" == 480 ]]
done
# Isolated preview must never summon or mutate the active desktop owners.
# Shared host Style probes compositor geometry read-only. With session sockets
# removed these cannot contact the desktop; no menu owner commands may run.
if [[ -f "$ARANEA_TEST_SANDBOX/guard.log" ]] && grep -Ev '^hyprctl -j getoption (general:gaps_out|decoration:rounding)$' "$ARANEA_TEST_SANDBOX/guard.log"; then
  exit 1
fi
rc=0
"$repo_root/tools/render-menu-preview" --output "$out/invalid.png" --fixture invalid >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 && ! -e "$out/invalid.png" ]]
echo 'menu preview contract passed'
