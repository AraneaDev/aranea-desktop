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
entry="$plugin/Clipboard.qml"
window="$plugin/ClipboardWindow.qml"
# Behaviour (secret refusal, save queue, expiry on open, restamp, swatches):
# tests/qml/clipboard.qml, run offscreen by tests/qml-behaviour.test.sh.

jq -e '.id == "araneadev.clipboard" and (.kinds | index("overlay")) and .entryPoints.overlay == "Clipboard.qml" and .omarchy.clonedFrom == "omarchy.clipboard"' "$plugin/manifest.json" >/dev/null
# --- 4f: the entry is non-visual; the window is created from its own file
if grep -Eq 'PanelWindow|import Quickshell.Wayland' "$entry"; then
  echo "Clipboard.qml must stay free of window types (it runs offscreen in tests)" >&2
  exit 1
fi
grep -Fq 'Qt.createComponent(Qt.resolvedUrl("ClipboardWindow.qml"))' "$entry"
grep -Fq 'property bool windowEnabled: true' "$entry"
grep -Fq 'if (root.captureEnabled)' "$entry"
grep -Fq 'Aranea.OverlayChrome {' "$window"
grep -Fq 'ClipboardResultsPane {' "$window"

grep -Fq 'ClipboardLogic.displayRows' "$entry"
grep -Fq '"--history-index", String(row.historyIndex)' "$entry"
grep -Fq 'ARANEA_CLIPBOARD_SECRET_TTL_MS' "$entry"
grep -Fq 'ARANEA_CLIPBOARD_SECRET_TTL_MS' "$repo_root/README.md"
# the preview only shows secret text after an explicit reveal (Review Focus 1)
grep -Fq 'activeRow.secret && revealedIndex !== selectedIndex' "$plugin/components/ClipboardResultsPane.qml"
# a reveal belongs to one item; any change to the list masks everything again
block_grep "$entry" 'function rebuildDisplay()' 'root.revealedIndex = -1'
# menu-like open motion that honours the Aranea motion setting
grep -Fq 'aranea/motion' "$entry"
grep -Fq 'NumberAnimation' "$window"
# pin time recorded; no secret toggle offered for images; header wording
grep -Fq 'ClipboardLogic.togglePinned(root.history, displayModel.get(index).historyIndex, Date.now())' "$entry"
grep -Fq 'row.kind !== "image"' "$entry"
grep -Fq ' 📌' "$window"
# stock entries get their capture time saved once
grep -Fq 'ClipboardLogic.hadUnstamped' "$entry"
# our own writes never trigger a re-parse, and failed reloads respect pending saves
grep -Fq 'root.savedTexts.indexOf(raw) >= 0' "$entry"
block_grep "$entry" 'onLoadFailed: {' 'if (root.pendingSaves > 0)'
block_grep "$entry" 'id: saveWatchdog' 'interval: 5000'
if grep -Fq 'lastSavedText' "$entry"; then
  echo "lastSavedText only remembers the last write" >&2
  exit 1
fi
# remaining time from the TTL, not hard-coded; swatch colour in the preview
grep -Fq 'ClipboardLogic.secretExpiryText(' "$plugin/components/ClipboardResultsPane.qml"
if grep -Fq 'EXPIRES 10 MIN' "$entry" "$window"; then
  echo "expiry text must come from secretTtlMs" >&2
  exit 1
fi
grep -Fq 'pane.activeRow.swatch' "$plugin/components/ClipboardResultsPane.qml"
if grep -Eq 'property int (headerHeight|contentSpacing)' "$entry" "$window"; then
  echo "unused headerHeight/contentSpacing" >&2
  exit 1
fi

echo "clipboard contract passed"
