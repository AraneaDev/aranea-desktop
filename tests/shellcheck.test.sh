#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck unavailable; skipped"; exit 0; }
shellcheck "$repo_root/scripts/aranea-motion" \
  "$repo_root/scripts/aranea-wallpaper" \
  "$repo_root/scripts/aranea-integrations" \
  "$repo_root/scripts/aranea-doctor" \
  "$repo_root/hooks/theme-set" \
  "$repo_root/hooks/post-boot"
echo "shellcheck contract passed"
