#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/assert.sh"
plugin="$repo_root/plugins/araneadev.polkit"

# Logic contract: tests/js/polkit.test.js (node:test; run by tests/js.test.sh).

# --- plugin shape: a clone of the stock agent
jq -e '.id == "araneadev.polkit" and .omarchy.clonedFrom == "omarchy.polkit" and .keepLoaded == true
  and .kinds == ["service"] and .entryPoints.service == "PolkitAgent.qml"' "$plugin/manifest.json" >/dev/null
grep -Fq 'import "PolkitLogic.js" as PolkitLogic' "$plugin/PolkitAgent.qml"
if grep -Fq 'PolkitModel' "$plugin/PolkitAgent.qml"; then
  echo "use PolkitLogic, not PolkitModel" >&2
  exit 1
fi
# The stock behaviour that must survive the restyle.
grep -Fq 'path: "/org/omarchy/PolkitAgent"' "$plugin/PolkitAgent.qml"
grep -Fq 'WlrLayershell.namespace: "omarchy-polkit"' "$plugin/PolkitAgent.qml"
grep -Fq 'path: "/etc/pam.d/polkit-1"' "$plugin/PolkitAgent.qml"
grep -Fq 'omarchy-hw-laptop-closed' "$plugin/PolkitAgent.qml"
grep -Fq 'id: shakeAnimation' "$plugin/PolkitAgent.qml"
grep -Fq 'flow.cancelAuthenticationRequest()' "$plugin/PolkitAgent.qml"
if grep -E 'console\.(log|warn).*passwordInput' "$plugin/PolkitAgent.qml"; then
  echo "never log the password" >&2
  exit 1
fi

# --- Aranea card
agent="$plugin/PolkitAgent.qml"
grep -Fq 'AUTHENTICATION REQUIRED' "$agent"
grep -Fq 'SYSTEM // PRIVILEGED' "$agent"
grep -Fq 'aranea-glyph.svg' "$agent"
grep -Fq 'PolkitLogic.requestMarkup(root.currentMessage' "$agent"
grep -Fq 'textFormat: Text.StyledText' "$agent"
grep -Fq 'PolkitLogic.contextLine(' "$agent"
grep -Fq 'PolkitLogic.detailRows(' "$agent"
grep -Fq 'ENTER AUTHORIZE · TAB DETAILS · ESC CANCEL' "$agent"
grep -Fq 'Math.max(Color.polkit.scrim.a, 0.72)' "$agent"
grep -Fq 'aranea/motion' "$agent"
# Review Focus 5: the card never exceeds the screen
grep -Fq 'Math.max(Style.space(120), Math.min(Style.space(380), panel.width - Style.gapsOut * 2))' "$agent"
# Action lookup: argv only, validated id, one request's result only (Review Focus 1)
grep -Fq '["timeout", "2", "pkaction", "--action-id", id, "--verbose"]' "$agent"
grep -Fq 'PolkitLogic.validActionId(id)' "$agent"
grep -Fq 'root.lookupQueued' "$agent"
grep -Fq 'String(flow.cookie || "") === root.lookupCookie' "$agent"
if grep -Eq '"(sh|bash)", "-c".*pkaction' "$agent"; then
  echo "pkaction must not run through a shell" >&2
  exit 1
fi
# Details start collapsed for every request
grep -Fq 'detailsOpen = false' "$agent"
# Review Focus 4: every focus holder routes keys through one handler
[[ "$(grep -c 'root.handleKey(event)' "$agent")" -ge 3 ]]
grep -Fq 'Qt.Key_Backtab' "$agent"
grep -Fq 'flow.selectedIdentity = flow.identities[' "$agent"
# The old pill above the card is gone (the request lives in the card now)
if grep -Fq 'justificationText' "$agent"; then
  echo "stock justification pill should be gone" >&2
  exit 1
fi

# --- final review fixes
# m1: a pkaction result rebuilds the details; keep keys working afterwards
grep -A1 -F 'if (root.detailsOpen)' "$agent" | grep -Fq 'Qt.callLater(root.refocus)'
# m2: content never spills past the card on very short screens
block_grep "$agent" 'id: card' 'clip: true'
# m4: doctor reports whether a polkit prompt is enabled
grep -Fq 'ARANEA_DOCTOR_POLKIT_STATUS' "$repo_root/scripts/aranea-doctor"
# README tells a hand-disabler to restart the shell
grep -Fq 'omarchy plugin disable araneadev.polkit' "$repo_root/README.md"

echo "polkit contract passed"
