#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while IFS= read -r path; do
  test -n "$path"
  test -f "$repo_root/$path"
done < <(sed -n 's/^path = "\(.*\)"$/\1/p' "$repo_root/backgrounds/manifest.toml")

while IFS= read -r path; do
  test -n "$path"
  test -f "$repo_root/$path"
done < <(rg -o '\]\([^)]*\)' "$repo_root/README.md" | sed 's/^](//; s/)$//' | rg -v '^(https?://|#)')

find "$repo_root/integrations" -type f -name '*.svg' -print0 |
  xargs -0 -n1 xmllint --noout

find "$repo_root/backgrounds" "$repo_root/screenshots" -type f \( -name '*.png' -o -name '*.jpg' \) -print0 |
  xargs -0 -n1 identify >/dev/null

echo "asset contract passed"
