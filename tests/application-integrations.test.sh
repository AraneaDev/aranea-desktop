#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for file in \
  "$repo_root/integrations/browser/README.md" \
  "$repo_root/integrations/browser/firefox/userChrome.css" \
  "$repo_root/integrations/browser/firefox/userContent.css" \
  "$repo_root/integrations/browser/chromium/new-tab/index.html" \
  "$repo_root/integrations/browser/chromium/new-tab/style.css" \
  "$repo_root/integrations/session/README.md" \
  "$repo_root/integrations/session/omarchy.css" \
  "$repo_root/integrations/media/README.md" \
  "$repo_root/integrations/media/pavucontrol.css" \
  "$repo_root/integrations/developer/neovim.lua" \
  "$repo_root/branding/about-card.txt"; do
  test -f "$file"
done

grep -Fq 'Aranea' "$repo_root/branding/about-card.txt"
grep -Fq 'fall back' "$repo_root/integrations/browser/README.md"
grep -Fq 'unsupported' "$repo_root/integrations/session/README.md"
grep -Fq 'native' "$repo_root/integrations/media/README.md"
grep -Fq 'Aranea' "$repo_root/integrations/browser/chromium/new-tab/index.html"
grep -Fq '#3bff9e' "$repo_root/integrations/session/omarchy.css"
grep -Fq '#7a5cff' "$repo_root/integrations/media/pavucontrol.css"
about_output="$($repo_root/scripts/aranea-about)"
grep -Fq 'Theme version:' <<<"$about_output"
grep -Fq 'Bar profile:' <<<"$about_output"
grep -Fq 'Health:' <<<"$about_output"

browser_output="$($repo_root/scripts/install-integration browser --dry-run)"
if command -v firefox >/dev/null 2>&1; then
  grep -Fq 'browser/firefox/userChrome.css' <<<"$browser_output"
fi
if command -v chromium >/dev/null 2>&1; then
  grep -Fq 'browser/chromium/new-tab/index.html' <<<"$browser_output"
fi

session_output="$($repo_root/scripts/install-integration session --dry-run)"
grep -Fq 'session/omarchy.css' <<<"$session_output"

if command -v pavucontrol >/dev/null 2>&1 || command -v pwvucontrol >/dev/null 2>&1; then
  media_output="$($repo_root/scripts/install-integration media --dry-run)"
  grep -Fq 'media/pavucontrol.css' <<<"$media_output"
fi

echo "application integration contract passed"
