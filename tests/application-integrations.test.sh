#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for file in \
  "$repo_root/integrations/browser/README.md" \
  "$repo_root/integrations/session/README.md" \
  "$repo_root/integrations/media/README.md" \
  "$repo_root/integrations/developer/neovim.lua" \
  "$repo_root/branding/about-card.txt"; do
  test -f "$file"
done

grep -Fq 'Aranea' "$repo_root/branding/about-card.txt"
grep -Fq 'fall back' "$repo_root/integrations/browser/README.md"
grep -Fq 'unsupported' "$repo_root/integrations/session/README.md"
grep -Fq 'native' "$repo_root/integrations/media/README.md"

echo "application integration contract passed"
