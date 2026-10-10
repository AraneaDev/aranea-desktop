#!/usr/bin/env bash
# Contract for the application integrations (browser, session, media) and
# branding assets: every referenced file exists, carries Aranea branding,
# and scripts/install-integration --dry-run plans the right files per target.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

for file in \
  "$repo_root/integrations/browser/README.md" \
  "$repo_root/integrations/aranea-colors.css" \
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
  "$repo_root/branding/screensaver.txt" \
  "$repo_root/branding/glyphs/theme-change.txt" \
  "$repo_root/branding/marks/aranea-primary.svg" \
  "$repo_root/branding/marks/aranea-glyph.svg" \
  "$repo_root/branding/marks/aranea-ceremony.svg" \
  "$repo_root/integrations/qt/kvantum/Aranea/Aranea.svg"; do
  test -f "$file"
done

grep -Fq 'Aranea' "$repo_root/branding/about-card.txt"
test -s "$repo_root/branding/screensaver.txt"
grep -Fq 'branding/screensaver.txt' "$repo_root/scripts/lib/ownership.sh"
grep -Fq 'link_theme_files' "$repo_root/hooks/theme-set"
grep -Fq 'link_theme_files' "$repo_root/hooks/post-boot"
grep -Fq 'fall back' "$repo_root/integrations/browser/README.md"
grep -Fq 'unsupported' "$repo_root/integrations/session/README.md"
grep -Fq 'native' "$repo_root/integrations/media/README.md"
grep -Fq 'Aranea' "$repo_root/integrations/browser/chromium/new-tab/index.html"
grep -Fq 'branding/brand.svg' "$repo_root/integrations/session/omarchy.css"
grep -Fq 'branding/brand.svg' "$repo_root/integrations/browser/aranea.css"
grep -Fq 'CEREMONY' "$repo_root/branding/glyphs/theme-change.txt"
grep -Fq '@import "aranea-colors.css"' "$repo_root/integrations/session/omarchy.css"
grep -Fq 'var(--aranea-focus)' "$repo_root/integrations/media/pavucontrol.css"
grep -Fq -- '--aranea-accent: #3bff9e;' "$repo_root/integrations/aranea-colors.css"
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
grep -Fq 'Health:' <<<"$about_output"

browser_output="$("$repo_root/scripts/install-integration" browser --dry-run)"
printf '%s\n' "$browser_output"
# firefox and chromium are guard stubs, so both are always planned.
grep -Fq 'browser/firefox/userChrome.css' <<<"$browser_output"
grep -Fq 'browser/chromium/new-tab/index.html' <<<"$browser_output"
grep -Fq 'integrations/aranea-colors.css' <<<"$browser_output"

session_output="$("$repo_root/scripts/install-integration" session --dry-run)"
printf '%s\n' "$session_output"
grep -Fq 'session/omarchy.css' <<<"$session_output"
grep -Fq 'integrations/aranea-colors.css' <<<"$session_output"

media_output="$("$repo_root/scripts/install-integration" media --dry-run)"
printf '%s\n' "$media_output"
grep -Fq 'media/pavucontrol.css' <<<"$media_output"
grep -Fq 'integrations/aranea-colors.css' <<<"$media_output"

# --- 4d: the README says how to run the helper scripts
for script in aranea-motion aranea-doctor aranea-integrations aranea-wallpaper aranea-about uninstall.sh; do
  grep -Fq "scripts/$script" "$repo_root/README.md" || {
    echo "README misses scripts/$script" >&2
    exit 1
  }
done
grep -Fq '.config/omarchy/themes/aranea/scripts/<name>' "$repo_root/README.md"

# Scripts links are not general integration ownership: only the stable
# installed project's exact executable may be removed/restored as managed.
source "$repo_root/scripts/lib/ownership.sh"
mkdir -p "$HOME/.local/bin" "$HOME/.config/omarchy/themes/aranea"
cp -a "$repo_root/scripts" "$HOME/.config/omarchy/themes/aranea/scripts"
ln -s "$HOME/.config/omarchy/themes/aranea/scripts/aranea" "$HOME/.local/bin/aranea"
"$HOME/.local/bin/aranea" projects list --json | jq -se 'last | .data.projects == []' >/dev/null
is_aranea_target "$HOME/.local/bin/aranea" || {
  echo 'stable installed project command was not recognized as owned' >&2
  exit 1
}
for destination in \
  "$HOME/.config/omarchy/themes/aranea/scripts/aranea-doctor" \
  "$HOME/.local/state/omarchy/current/theme/scripts/aranea" \
  "$repo_root/scripts/aranea" \
  "$HOME/other-theme/scripts/aranea"; do
  ln -sf "$destination" "$HOME/.local/bin/foreign"
  if is_aranea_target "$HOME/.local/bin/foreign"; then
    echo "arbitrary scripts symlink was counted as managed: $destination" >&2
    exit 1
  fi
done

echo "application integration contract passed"
