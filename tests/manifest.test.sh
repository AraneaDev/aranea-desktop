#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/theme-manifest.toml"

test -f "$manifest"

for profile in minimal full no_apps; do
  grep -Eq "^\[profiles\.${profile}\]$" "$manifest"
done

integration_count="$(grep -c '^\[\[integrations\]\]$' "$manifest")"
test "$integration_count" -gt 0

for field in id profile target_kind fallback; do
  count="$(grep -c "^${field} =" "$manifest")"
  test "$count" -eq "$integration_count"
done

for token in motion_enabled reduced_motion_fallback; do
  grep -Eq "^${token}[[:space:]]*=" "$repo_root/colors.toml"
done

for token in context-text tile-background footer-text node-alpha; do
  grep -Eq "^${token}[[:space:]]*=" "$repo_root/shell.toml"
done

echo "manifest contract passed"
