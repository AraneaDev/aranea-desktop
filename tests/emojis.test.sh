#!/usr/bin/env bash
# Contract for the araneadev.emojis plugin's manifest and Emojis.qml:
# manifest shape, overlay wiring to EmojiLogic, direct shared chrome usage,
# and the final-review fixes below.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Logic contract: tests/js/emojis.test.js (node:test; run by tests/js.test.sh).

plugin="$repo_root/plugins/araneadev.emojis"
jq -e '.id == "araneadev.emojis" and .entryPoints.overlay == "Emojis.qml" and .omarchy.clonedFrom == "omarchy.emojis"' "$plugin/manifest.json" >/dev/null
grep -Fq 'EmojiPickerContent {' "$plugin/EmojiWindow.qml"
# the entry is non-visual; the window is created from its own file
if grep -Eq 'PanelWindow|import Quickshell.Wayland' "$plugin/Emojis.qml"; then
  echo "Emojis.qml must stay free of window types (it runs offscreen in tests)" >&2
  exit 1
fi
grep -Fq 'Qt.createComponent(Qt.resolvedUrl("EmojiWindow.qml"))' "$plugin/Emojis.qml"
grep -Fq 'Aranea.OverlayChrome {' "$plugin/EmojiPickerContent.qml"
grep -Fq 'EmojiLogic.pushRecent' "$plugin/Emojis.qml"
grep -Fq 'EmojiLogic.emojiName' "$plugin/Emojis.qml"
if [[ -e "$plugin/OverlayChrome.qml" || -e "$repo_root/plugins/araneadev.clipboard/OverlayChrome.qml" ]]; then
  echo "plugin-local OverlayChrome shims must be removed" >&2
  exit 1
fi

# --- final-review fixes (Emojis.qml)
grep -Fq 'Aranea.MotionState.motionEnabled' "$plugin/Emojis.qml"
grep -Fq 'EmojiLogic.keywordsFor' "$plugin/Emojis.qml"
# m7: columns follow the real grid width; Up from the grid lands in the last recent row
grep -Fq 'Math.floor((root.cardWidth - root.contentMargin * 2 - Border.left(root.borderSpec) - Border.right(root.borderSpec)) / root.cellWidth)' "$plugin/Emojis.qml"
grep -Fq 'lastRowStart' "$plugin/Emojis.qml"

# --- 4d: without a manifest the picker hides itself, not the stock one
grep -Fq '|| "araneadev.emojis")' "$plugin/Emojis.qml"

# --- consistency part 4: the mint outline marks Enter's target; hover only
# fills (gated) and never moves it; clicks are keyed by emoji and settled
window="$plugin/EmojiWindow.qml"
if grep -Eq 'selectFromPointer|pointerMoved\b|signal pointerMoved' "$plugin"/*.qml; then
  echo "hover must never move the emoji cursor" >&2
  exit 1
fi
grep -Fq 'cursorActive: panel.root.outlineShown' "$window"
grep -Fq 'pointerGate: pointerGate' "$window"
grep -Fq 'layoutChangedAt: panel.root.layoutChangedAt' "$window"
grep -Fq 'panel.root.activateKey(index, key)' "$window"
grep -Fq 'panel.root.activateRecentKey(index, key)' "$window"
grep -Fq 'if (panel.root.handleKey(event))' "$window"
grep -Fq 'ClickSettle.clickSettled(' "$plugin/EmojiCell.qml"
grep -Fq 'objectName: "cursorOutline"' "$plugin/EmojiCell.qml"
if grep -Fq 'displayModel.clear()' "$plugin/Emojis.qml"; then
  echo "rebuildDisplay must update the cells in place (syncRows)" >&2
  exit 1
fi

echo "emojis contract passed"
