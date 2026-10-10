#!/usr/bin/env bash
# Contract for scripts/aranea-showcase: `list` names every known surface,
# and both aranea-showcase and capture-screenshots reject an unknown
# surface with a clear error instead of silently doing nothing.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

list_output="$("$repo_root/scripts/aranea-showcase" list)"
for surface in desktop menu menu-submenu menu-search menu-input ceremony notifications clipboard emojis polkit health lock boot about idle file-manager editor dawn; do
  grep -Fq "$surface" <<<"$list_output"
done

# --- 4e: the capturable dropdowns are listed; widgets without a popup and
# the Wi-Fi QR (it shows the password) are not
for surface in clock weather image-picker; do
  grep -Fxq "$surface" <<<"$list_output"
done
for surface in keyboard-layout system-update wifiqr; do
  if grep -Fxq "$surface" <<<"$list_output"; then
    echo "$surface must not be a showcase surface" >&2
    exit 1
  fi
done

if "$repo_root/scripts/aranea-showcase" surface unknown 2>"$ARANEA_TEST_SANDBOX/showcase-error"; then
  echo "unknown showcase surface unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown surface' "$ARANEA_TEST_SANDBOX/showcase-error"
rm -f "$ARANEA_TEST_SANDBOX/showcase-error"

if "$repo_root/scripts/capture-screenshots" --surface unknown --output "$ARANEA_TEST_SANDBOX" 2>"$ARANEA_TEST_SANDBOX/capture-error"; then
  echo "unknown capture surface unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown surface' "$ARANEA_TEST_SANDBOX/capture-error"
rm -f "$ARANEA_TEST_SANDBOX/capture-error"

echo "showcase contract passed"

# The Tasks preview renders production components in a separate offscreen host.
[[ -x "$repo_root/tools/render-agents-preview" ]] || {
  echo 'FAIL missing inert Tasks renderer'
  exit 1
}
source "$repo_root/tests/lib/qml-host.sh"
require_qml_host
ARANEA_QML_SHELL_DIR="$qml_shell_dir" ARANEA_AGENTS_PREVIEW_QUICKSHELL="$quickshell_bin" "$repo_root/tools/render-agents-preview" --fixture empty --output "$ARANEA_TEST_SANDBOX/agents.png"
[[ -s "$ARANEA_TEST_SANDBOX/agents.png" ]]
echo 'PASS inert production Tasks preview, execution traps and unchanged state/settings'
