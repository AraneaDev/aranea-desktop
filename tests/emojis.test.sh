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
grep -Fq 'EmojiPickerContent {' "$plugin/Emojis.qml"
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
grep -Fq 'Math.floor((root.cardWidth - root.contentMargin * 2) / root.cellWidth)' "$plugin/Emojis.qml"
grep -Fq 'lastRowStart' "$plugin/Emojis.qml"

# --- 4d: without a manifest the picker hides itself, not the stock one
grep -Fq '|| "araneadev.emojis")' "$plugin/Emojis.qml"

echo "emojis contract passed"
