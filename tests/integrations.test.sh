#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

if "$repo_root/scripts/install-integration" --dry-run missing-integration 2>"$ARANEA_TEST_SANDBOX/integration-error"; then
  echo "unknown integration unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown integration' "$ARANEA_TEST_SANDBOX/integration-error"
rm -f "$ARANEA_TEST_SANDBOX/integration-error"

for file in integrations/terminal/alacritty.toml integrations/terminal/kitty.conf integrations/terminal/foot.ini; do
  test -f "$repo_root/$file"
done

terminal_output="$("$repo_root"/scripts/install-integration terminal --dry-run)"
printf '%s\n' "$terminal_output"
grep -Eq 'Skipping terminal:|terminal/(alacritty|kitty|foot)' <<<"$terminal_output"

qt_output="$("$repo_root/scripts/install-integration" qt --dry-run)"
grep -Eq 'Skipping qt:|would link .*Aranea\.kvconfig' <<<"$qt_output"

if command -v nvim >/dev/null 2>&1; then
  developer_output="$("$repo_root/scripts/install-integration" developer --dry-run)"
  grep -Fq 'nvim/lua/plugins/aranea-theme.lua' <<<"$developer_output"
fi

cursor_output="$("$repo_root/scripts/install-integration" cursor --dry-run)"
grep -Fq 'cursor/index.theme' <<<"$cursor_output"
grep -Fq 'cursor/cursors/left_ptr.svg' <<<"$cursor_output"

icons_output="$("$repo_root/scripts/install-integration" icons --dry-run)"
grep -Eq 'Skipping icons:|would set desktop icon theme' <<<"$icons_output"

# An optional app that isn't installed never fails the integration (spec B5).
"$repo_root/scripts/install-integration" developer --yes >/dev/null

echo "integration contract passed"
