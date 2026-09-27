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
