#!/usr/bin/env bash
# Canonical tokens must produce the committed host and QML projections.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
node "$repo_root/tools/token-generator.mjs" --check
grep -Fq 'design/tokens.toml' "$repo_root/tools/token-generator.mjs"
grep -Fq 'singleton DesignTokens' "$repo_root/plugins/araneadev.shared/qmldir"
test -f "$repo_root/design/templates/integrations/terminal/alacritty.toml.in"
test -f "$repo_root/design/templates/integrations/developer/btop.theme.in"
grep -Fq 'cursor_shadow' "$repo_root/design/tokens.toml"
grep -Fq '#3bff9e' "$repo_root/integrations/cursor/cursors/crosshair.svg"
test -f "$repo_root/design/templates/assets/cursor-left_ptr.svg.in"
echo "token generation contract passed"
