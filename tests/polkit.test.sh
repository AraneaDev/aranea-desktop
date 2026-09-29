#!/usr/bin/env bash
# Contract for the araneadev.polkit plugin: it is a clone of the stock agent
# that keeps the stock behaviour (D-Bus path, layer namespace, PAM path,
# laptop-lid trigger, cancel-on-close, never logging the password) while
# wearing the Aranea card (styling, keyboard routing, action lookup via
# argv-only pkaction, collapsed details, size clamped to the screen) and the
# final-review fixes below.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"
plugin="$repo_root/plugins/araneadev.polkit"
# The entry (state, logic), its window and the system-bus agent; text checks
# look in all three. Behaviour (empty Enter, submit, identities, hint, spoofed
# target): tests/qml/polkit.qml, run offscreen by tests/qml-behaviour.test.sh.
polkit_files=("$plugin/PolkitAgent.qml" "$plugin/PolkitWindow.qml" "$plugin/PolkitPromptCard.qml" "$plugin/PolkitDetails.qml" "$plugin/PolkitAgentService.qml")

# Logic contract: tests/js/polkit.test.js (node:test; run by tests/js.test.sh).

# --- plugin shape: a clone of the stock agent
jq -e '.id == "araneadev.polkit" and .omarchy.clonedFrom == "omarchy.polkit" and .keepLoaded == true
  and .kinds == ["service"] and .entryPoints.service == "PolkitAgent.qml"' "$plugin/manifest.json" >/dev/null
grep -Fq 'import "PolkitLogic.js" as PolkitLogic' "${polkit_files[@]}"
if grep -Fq 'PolkitModel' "${polkit_files[@]}"; then
  echo "use PolkitLogic, not PolkitModel" >&2
  exit 1
fi
# The stock behaviour that must survive the restyle.
grep -Fq 'path: "/org/omarchy/PolkitAgent"' "${polkit_files[@]}"
grep -Fq 'WlrLayershell.namespace: "omarchy-polkit"' "${polkit_files[@]}"
grep -Fq 'path: "/etc/pam.d/polkit-1"' "${polkit_files[@]}"
grep -Fq 'omarchy-hw-laptop-closed' "${polkit_files[@]}"
grep -Fq 'id: shakeAnimation' "${polkit_files[@]}"
grep -Fq 'flow.cancelAuthenticationRequest()' "${polkit_files[@]}"
if grep -E 'console\.(log|warn).*passwordInput' "${polkit_files[@]}"; then
  echo "never log the password" >&2
  exit 1
fi

# --- Aranea card
agent="$plugin/PolkitAgent.qml"
grep -Fq 'PolkitPromptCard {' "$plugin/PolkitWindow.qml"
grep -Fq 'AUTHENTICATION REQUIRED' "$plugin/PolkitPromptCard.qml"
grep -Fq 'SYSTEM // PRIVILEGED' "${polkit_files[@]}"
grep -Fq 'RuntimePaths.glyphUrl' "${polkit_files[@]}"
grep -Fq 'PolkitLogic.requestMarkup(root.currentMessage' "${polkit_files[@]}"
grep -Fq 'textFormat: Text.StyledText' "${polkit_files[@]}"
grep -Fq 'PolkitLogic.contextLine(' "${polkit_files[@]}"
grep -Fq 'PolkitLogic.detailRows(' "${polkit_files[@]}"
grep -Fq 'PolkitLogic.hintLine(root.fingerprintMode, root.identityTotal)' "${polkit_files[@]}"
grep -Fq 'Math.max(Color.polkit.scrim.a, 0.72)' "${polkit_files[@]}"
grep -Fq 'aranea/motion' "${polkit_files[@]}"
# Review Focus 5: the card never exceeds the screen
grep -Fq 'Math.max(Style.space(120), Math.min(Style.space(380), panel.width - Style.gapsOut * 2))' "${polkit_files[@]}"
# Action lookup: argv only, validated id, one request's result only (Review Focus 1)
grep -Fq '["timeout", "2", "pkaction", "--action-id", id, "--verbose"]' "${polkit_files[@]}"
grep -Fq 'PolkitLogic.validActionId(id)' "${polkit_files[@]}"
grep -Fq 'root.lookupQueued' "${polkit_files[@]}"
grep -Fq 'String(flow.cookie || "") === root.lookupCookie' "${polkit_files[@]}"
if grep -Eq '"(sh|bash)", "-c".*pkaction' "${polkit_files[@]}"; then
  echo "pkaction must not run through a shell" >&2
  exit 1
fi
# Details start collapsed for every request
grep -Fq 'detailsOpen = false' "${polkit_files[@]}"
# Review Focus 4: every focus holder routes keys through one handler
key_handler_count="$(grep -h -c 'root.handleKey(event)' "$plugin/PolkitWindow.qml" "$plugin/PolkitDetails.qml" | awk '{ total += $1 } END { print total }')"
[[ "$key_handler_count" -ge 3 ]]
grep -Fq 'Qt.Key_Backtab' "${polkit_files[@]}"
grep -Fq 'flow.selectedIdentity = flow.identities[' "${polkit_files[@]}"
# The old pill above the card is gone (the request lives in the card now)
if grep -Fq 'justificationText' "${polkit_files[@]}"; then
  echo "stock justification pill should be gone" >&2
  exit 1
fi

# --- final review fixes
# m1: a pkaction result rebuilds the details; keep keys working afterwards
grep -A1 -F 'if (root.detailsOpen)' "$agent" | grep -Fq 'Qt.callLater(root.refocus)'
# m2: content never spills past the card on very short screens
block_grep "$plugin/PolkitWindow.qml" 'id: card' 'clip: true'
# m4: doctor reports whether a polkit prompt is enabled
grep -Fq 'ARANEA_DOCTOR_POLKIT_STATUS' "$repo_root/scripts/aranea-doctor"
# README tells a hand-disabler to restart the shell
grep -Fq 'omarchy plugin disable araneadev.polkit' "$repo_root/README.md"
# --- 4a: the target has its own line that is never elided
target_block="$(grep -A6 -B3 -F 'text: root.targetText' "$plugin/PolkitPromptCard.qml")"
grep -Fq 'text: root.targetText' <<<"$target_block"
grep -Fq 'readonly property string targetText: PolkitLogic.targetLine(root.currentMessage)' "$agent"
grep -Fq 'wrapMode: Text.Wrap' <<<"$target_block"
if grep -Eq 'elide:|maximumLineCount' <<<"$target_block"; then
  echo "the target line must never elide" >&2
  exit 1
fi
# --- 4a: clicking the details never takes focus from the password field
block_grep "$plugin/PolkitDetails.qml" 'TextEdit {' 'activeFocusOnPress: false'
# --- 4a: an empty Enter never submits (no wasted attempt), it nudges
grep -Fq 'id: nudgeAnimation' "${polkit_files[@]}"
# --- 4a: the identity count feeds the hint; the unused failed mirror is gone
if grep -Eq 'property bool failed|failed = ' "${polkit_files[@]}"; then
  echo "failed is never read" >&2
  exit 1
fi

echo "polkit contract passed"
