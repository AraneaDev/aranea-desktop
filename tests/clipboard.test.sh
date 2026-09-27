#!/usr/bin/env bash
# Contract for the araneadev.clipboard plugin's manifest and Clipboard.qml:
# manifest shape, overlay wiring to ClipboardLogic, secret reveal/expiry,
# pin/paste behaviour and the final-review fixes below.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"

# Logic contract: tests/js/clipboard.test.js (node:test; run by tests/js.test.sh).

plugin="$repo_root/plugins/araneadev.clipboard"
jq -e '.id == "araneadev.clipboard" and (.kinds | index("overlay")) and .entryPoints.overlay == "Clipboard.qml" and .omarchy.clonedFrom == "omarchy.clipboard"' "$plugin/manifest.json" >/dev/null
grep -Fq 'OverlayChrome {' "$plugin/Clipboard.qml"
grep -Fq 'ClipboardLogic.displayRows' "$plugin/Clipboard.qml"
grep -Fq 'ClipboardLogic.expire' "$plugin/Clipboard.qml"
grep -Fq '"--history-index", String(row.historyIndex)' "$plugin/Clipboard.qml"
grep -Fq 'ARANEA_CLIPBOARD_SECRET_TTL_MS' "$plugin/Clipboard.qml"
# the preview only shows secret text after an explicit reveal (Review Focus 1)
grep -Fq 'root.revealedIndex === root.selectedIndex' "$plugin/Clipboard.qml"

# --- final-review fixes (Clipboard.qml)
# C1: a reveal belongs to one item; any change to the list masks everything again
block_grep "$plugin/Clipboard.qml" 'function rebuildDisplay()' 'root.revealedIndex = -1'
# I4: menu-like open motion that honours the Aranea motion setting
grep -Fq 'aranea/motion' "$plugin/Clipboard.qml"
grep -Fq 'NumberAnimation' "$plugin/Clipboard.qml"
# I5 / m1 / m6: pin time recorded; no secret toggle offered for images; header wording
grep -Fq 'ClipboardLogic.togglePinned(root.history, displayModel.get(index).historyIndex, Date.now())' "$plugin/Clipboard.qml"
grep -Fq 'row.kind !== "image"' "$plugin/Clipboard.qml"
grep -Fq ' 📌' "$plugin/Clipboard.qml"
# m3: our own writes do not trigger a full re-parse
grep -Fq 'root.lastSavedText' "$plugin/Clipboard.qml"
# m4: stock entries get their capture time saved once
grep -Fq 'ClipboardLogic.hadUnstamped' "$plugin/Clipboard.qml"
# m10: paste/copy wait for a pending history write
grep -Fq 'root.pendingAction' "$plugin/Clipboard.qml"

echo "clipboard contract passed"
