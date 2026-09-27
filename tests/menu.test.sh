#!/usr/bin/env bash
# Contract for the araneadev.menu plugin's Menu.qml: favourites and recents
# persist to the Aranea state file, the favourite limit is enforced with a
# notice, and pinning works from the keyboard. Logic contract:
# tests/js/plugin-state.test.js (MenuModel).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"
menu_qml="$repo_root/plugins/araneadev.menu/Menu.qml"

# --- 4b: favourites and recents persist to $XDG_STATE_HOME/aranea/menu.json
grep -Fq '"/menu.json"' "$menu_qml"
grep -Fq 'MenuModel.parseAppHistory(' "$menu_qml"
grep -Fq 'MenuModel.serializeAppHistory(' "$menu_qml"
grep -Fq 'MenuModel.pruneAppIds(' "$menu_qml"
if grep -Fq 'PersistentProperties' "$menu_qml"; then
  echo "menu state must live in the state file" >&2
  exit 1
fi
# --- 4b: a 13th favourite is refused with a notice; Ctrl+P pins from the keyboard
grep -Fq '12 FAVOURITES · UNPIN ONE FIRST' "$menu_qml"
grep -Fq 'event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)' "$menu_qml"
# --- 4b: search shows each app once; Apps keeps Favorites/Recent on top
grep -Fq 'rows = MenuModel.dedupeAppRows(currentRows.concat(drilldownRows))' "$menu_qml"
grep -Fq 'rows = MenuModel.sortAppsMenu(rows)' "$menu_qml"
# --- 4b: honest hints, notice first; tiles have Ctrl+1..3; the clock ticks
grep -Fq 'root.notice || MenuModel.hintText(' "$menu_qml"
if grep -Fq '"ESC BACK  ·  ENTER OPEN"' "$menu_qml"; then
  echo "stale ESC BACK hint" >&2
  exit 1
fi
grep -Fq 'event.key >= Qt.Key_1 && event.key <= Qt.Key_3' "$menu_qml"
grep -Fq 'precision: SystemClock.Minutes' "$menu_qml"
grep -Fq 'Qt.formatDateTime(menuClock.date, "HH:mm")' "$menu_qml"

echo "menu contract passed"
