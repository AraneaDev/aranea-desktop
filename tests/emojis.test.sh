#!/usr/bin/env bash
# Contract for the araneadev.emojis plugin's manifest and Emojis.qml:
# manifest shape, overlay wiring to EmojiLogic, the shared OverlayChrome.qml
# copy matches the clipboard plugin's, and the final-review fixes below.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Logic contract: tests/js/emojis.test.js (node:test; run by tests/js.test.sh).

plugin="$repo_root/plugins/araneadev.emojis"
jq -e '.id == "araneadev.emojis" and .entryPoints.overlay == "Emojis.qml" and .omarchy.clonedFrom == "omarchy.emojis"' "$plugin/manifest.json" >/dev/null
grep -Fq 'OverlayChrome {' "$plugin/Emojis.qml"
grep -Fq 'EmojiLogic.pushRecent' "$plugin/Emojis.qml"
grep -Fq 'EmojiLogic.emojiName' "$plugin/Emojis.qml"
cmp -s "$plugin/OverlayChrome.qml" "$repo_root/plugins/araneadev.clipboard/OverlayChrome.qml" || {
  echo "OverlayChrome.qml copies differ" >&2
  exit 1
}

# --- final-review fixes (Emojis.qml)
grep -Fq 'aranea/motion' "$plugin/Emojis.qml"
grep -Fq 'EmojiLogic.keywordsFor' "$plugin/Emojis.qml"
# m7: columns follow the real grid width; Up from the grid lands in the last recent row
grep -Fq 'Math.floor(resultGrid.width / root.cellWidth)' "$plugin/Emojis.qml"
grep -Fq 'lastRowStart' "$plugin/Emojis.qml"

echo "emojis contract passed"
