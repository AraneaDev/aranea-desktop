#!/usr/bin/env bash
# Contract for the araneadev.menu plugin's Menu.qml: favourites and recents
# persist to the Aranea state file, the favourite limit is enforced with a
# notice, and pinning works from the keyboard. Logic contract:
# tests/js/menu-model.test.js, menu-tree.test.js and menu-guards.test.js.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"
menu_qml="$repo_root/plugins/araneadev.menu/Menu.qml"
menu_window="$repo_root/plugins/araneadev.menu/MenuWindow.qml"
menu_results="$repo_root/plugins/araneadev.menu/MenuResultList.qml"
# Behaviour (pin limit and notice, search dedupe, hints, Ctrl+P, Ctrl+1..3,
# Favorites route after the menu files load): tests/qml/menu.qml, run
# offscreen by tests/qml-behaviour.test.sh.

# --- 4f: the entry is non-visual; the window is created from its own file
if grep -Eq 'PanelWindow|import Quickshell.Wayland' "$menu_qml"; then
  echo "Menu.qml must stay free of window types (it runs offscreen in tests)" >&2
  exit 1
fi
grep -Fq 'Qt.createComponent(Qt.resolvedUrl("MenuWindow.qml"))' "$menu_qml"
grep -Fq 'panel.root.handleKey(event)' "$menu_window"
# App rows must render their desktop-entry icon through the shared app-library
# resolver; carrying appIcon in the model alone is not enough.
grep -Fq 'id: appIconImage' "$menu_results"
grep -Fq 'results.appLibrary.iconSource(row.appIcon)' "$menu_results"

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
# --- 4b: search shows each app once; Apps keeps Favorites/Recent on top
grep -Fq 'rows = MenuModel.dedupeAppRows(currentRows.concat(drilldownRows))' "$menu_qml"
grep -Fq 'rows = MenuModel.sortAppsMenu(rows)' "$menu_qml"
# --- 4b: honest hints, notice first; tiles have Ctrl+1..3; the clock ticks
grep -Fq 'root.notice || MenuModel.hintText(' "$menu_qml"
if grep -Fq '"ESC BACK  ·  ENTER OPEN"' "$menu_qml"; then
  echo "stale ESC BACK hint" >&2
  exit 1
fi
grep -Fq 'precision: SystemClock.Minutes' "$menu_qml"
grep -Fq 'Qt.formatDateTime(menuClock.date, "HH:mm")' "$menu_qml"
# --- 4b: provider state per menu; routes resolve when the rows exist
grep -Fq 'property var providerLoadingMenus: ({})' "$menu_qml"
grep -Fq 'property var providerErrorMenus: ({})' "$menu_qml"
grep -Fq 'MenuModel.emptyState(' "$menu_qml"
if grep -Eq 'property bool provider(Loading|Error)|openGeneratedAppsMenu|attempt < 12' "$menu_qml"; then
  echo "global provider flags and the route retry loop must be gone" >&2
  exit 1
fi
grep -Fq 'function resolvePendingAppsRoute(): void' "$menu_qml"
# --- 4b: no "undefined" commands; scaled bar button; dead code stays gone
block_grep "$menu_qml" 'function runAction(action): void' 'if (typeof action !== "string" || !action.trim())'
block_grep "$repo_root/plugins/araneadev.bar/Bar.qml" 'function run(command): void' 'if (typeof command !== "string" || !command.trim())'
grep -Fq 'fixedWidth: Style.space(30)' "$repo_root/plugins/araneadev.menu/BarWidget.qml"
if grep -Eq 'tileBackground|hoveredTileBorder|compactHeaderHeight|summon omarchy\.menu|text: row\.childCount|tile\.appId' "$menu_qml"; then
  echo "menu dead code or stale comments are back" >&2
  exit 1
fi
if grep -Eq 'root\.setActiveMenu\([^,()]+, (true|false)\)|root\.activateIndex\([^,()]+\)$' "$menu_qml"; then
  echo "setActiveMenu/activateIndex must receive every declared argument" >&2
  exit 1
fi
# --- 4b final review: state loads before use; stale routes never reopen; clock only when open
block_grep "$menu_qml" 'id: appHistoryFile' 'blockLoading: true'
block_grep "$menu_qml" 'id: menuClock' 'enabled: root.opened'
[[ "$(grep -c 'root.pendingInitialMenu = ""' "$menu_qml")" -ge 4 ]] || {
  echo "every other open/cancel path must drop a pending Favorites/Recent route" >&2
  exit 1
}
grep -Fq 'menu.json' "$repo_root/README.md"
grep -Fq 'Ctrl+P' "$repo_root/README.md"

echo "menu contract passed"
