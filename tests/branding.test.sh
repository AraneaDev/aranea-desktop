#!/usr/bin/env bash
# Branding source files must generate the shared identity projections and
# raster compatibility assets from the canonical mark.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/tests/lib/sandbox.sh"

test -f "$repo_root/design/brand.toml"
test -f "$repo_root/branding/marks/aranea-primary.svg"
test -f "$repo_root/branding/brand.svg"
grep -Fq 'brandingRoot + "/" + BrandConfig.markFile' "$repo_root/plugins/araneadev.shared/RuntimePaths.qml"
node "$repo_root/tools/token-generator.mjs" --check

grep -Fq 'singleton BrandConfig' "$repo_root/plugins/araneadev.shared/qmldir"
grep -Fq 'Aranea.BrandConfig.shortName' "$repo_root/plugins/araneadev.lock/LockBranding.qml"
grep -Fq 'Aranea.RuntimePaths.brandUrl' "$repo_root/plugins/araneadev.lock/LockView.qml"
grep -Fq '<h1>Aranea</h1>' "$repo_root/integrations/browser/chromium/new-tab/index.html"

test "$(identify -format '%wx%h' "$repo_root/unlock.png")" = '640x640'
test ! -e "$repo_root/branding/screens" # lock and boot screenshots are real renders now
grep -Fq 'Theme: Aranea' "$repo_root/branding/about-card.txt"
grep -Fq 'Quiet systems. Connected focus.' "$repo_root/branding/screensaver.txt"

test -f "$repo_root/branding/brand.env"
grep -Fq "BRAND_NAME='Aranea'" "$repo_root/branding/brand.env"
grep -Fq 'var(--aranea-surface-raised)' "$repo_root/integrations/browser/chromium/new-tab/style.css"
grep -Fq 'readonly property color ceremony: Color.' "$repo_root/plugins/araneadev.shared/DesignTokens.qml"
grep -Fq 'readonly property color attention: Color.' "$repo_root/plugins/araneadev.shared/DesignTokens.qml"
grep -Fq '{{colors.accent}}' "$repo_root/design/templates/assets/branding/active.svg.in"
if grep -Fq '{{' "$repo_root/branding/motifs"/*.svg "$repo_root/branding/glyphs"/{active,ready,power,sleep,warning,attention,error}.svg; then
  echo "generated branding assets contain unresolved template tokens" >&2
  exit 1
fi
grep -Fq 'var(--aranea-ceremony)' "$repo_root/integrations/browser/chromium/new-tab/style.css"
grep -Fq 'BRAND_NAME' "$repo_root/scripts/aranea-about"

echo "branding generation contract passed"
