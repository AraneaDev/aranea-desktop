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
  "$repo_root/branding/about-card.txt" \
  "$repo_root/branding/glyphs/theme-change.txt" \
  "$repo_root/branding/marks/aranea-primary.svg" \
  "$repo_root/branding/marks/aranea-glyph.svg" \
  "$repo_root/branding/marks/aranea-ceremony.svg" \
  "$repo_root/integrations/qt/kvantum/Aranea/Aranea.svg"; do
  test -f "$file"
done

grep -Fq 'Aranea' "$repo_root/branding/about-card.txt"
grep -Fq 'fall back' "$repo_root/integrations/browser/README.md"
grep -Fq 'unsupported' "$repo_root/integrations/session/README.md"
grep -Fq 'native' "$repo_root/integrations/media/README.md"
grep -Fq 'Aranea' "$repo_root/integrations/browser/chromium/new-tab/index.html"
grep -Fq 'aranea-primary.svg' "$repo_root/integrations/session/omarchy.css"
grep -Fq 'aranea-glyph.svg' "$repo_root/integrations/browser/aranea.css"
grep -Fq 'CEREMONY' "$repo_root/branding/glyphs/theme-change.txt"
grep -Fq '#3bff9e' "$repo_root/integrations/session/omarchy.css"
grep -Fq '#7a5cff' "$repo_root/integrations/media/pavucontrol.css"
if about_output="$("$repo_root/scripts/aranea-about" 2>&1)"; then
  :
else
  status=$?
  printf '%s\n' "$about_output" >&2
  echo "aranea-about failed with status $status" >&2
  exit 1
fi
printf '%s\n' "$about_output"
grep -Fq 'Theme version:' <<<"$about_output"
grep -Fq 'Bar profile:' <<<"$about_output"
grep -Fq 'Health:' <<<"$about_output"

browser_output="$("$repo_root/scripts/install-integration" browser --dry-run)"
printf '%s\n' "$browser_output"
if command -v firefox >/dev/null 2>&1; then
  grep -Fq 'browser/firefox/userChrome.css' <<<"$browser_output"
fi
if command -v chromium >/dev/null 2>&1; then
  grep -Fq 'browser/chromium/new-tab/index.html' <<<"$browser_output"
fi

session_output="$("$repo_root/scripts/install-integration" session --dry-run)"
printf '%s\n' "$session_output"
grep -Fq 'session/omarchy.css' <<<"$session_output"

if command -v pavucontrol >/dev/null 2>&1 || command -v pwvucontrol >/dev/null 2>&1; then
  media_output="$("$repo_root/scripts/install-integration" media --dry-run)"
  printf '%s\n' "$media_output"
  grep -Fq 'media/pavucontrol.css' <<<"$media_output"
fi

echo "application integration contract passed"
