#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/theme-manifest.toml"
source "$repo_root/scripts/lib/manifest.sh"

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

mapfile -t integrations < <(awk -F'"' '/^id = "/ { print $2 }' "$manifest")
for profile in minimal full no_apps; do
  while IFS= read -r integration; do
    test -n "$integration"
    manifest_integration_exists "$integration"
  done < <(manifest_profile_integrations "$profile")
done

for integration in "${integrations[@]}"; do
  test -n "$(manifest_integration_field "$integration" profile)"
  test -n "$(manifest_integration_field "$integration" target_kind)"
  test -n "$(manifest_integration_field "$integration" fallback)"
done

for token in motion_enabled reduced_motion_fallback; do
  grep -Eq "^${token}[[:space:]]*=" "$repo_root/colors.toml"
done

for token in context-text tile-background footer-text node-alpha; do
  grep -Eq "^${token}[[:space:]]*=" "$repo_root/shell.toml"
done

echo "manifest contract passed"
