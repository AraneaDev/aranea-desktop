#!/usr/bin/env bash
# Contract for theme-manifest.toml and scripts/lib/manifest.sh: every profile
# and integration is well-formed and every field present, the manifest
# helpers match ids and profiles literally (never as patterns), and
# colors.toml/shell.toml carry the tokens the manifest depends on.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
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

# Ids and profiles are matched literally, never as patterns.
manifest_profile_exists full
if manifest_profile_exists 'full|x'; then
  echo "unexpected success: manifest_profile_exists 'full|x'" >&2
  exit 1
fi
if manifest_profile_exists 'f.ll'; then
  echo "unexpected success: manifest_profile_exists 'f.ll'" >&2
  exit 1
fi
manifest_integration_exists session
if manifest_integration_exists '.*'; then
  echo "unexpected success: manifest_integration_exists '.*'" >&2
  exit 1
fi
[[ -z "$(manifest_integration_field '.*' optional_command)" ]]

# --- 4d: a field lookup never leaks from a later section; commented headers count
odd_manifest="$(mktemp)"
cat >"$odd_manifest" <<'TOML'
[profiles.full] # everything
integrations = ["a"]

[[integrations]]
id = "a"

[other]
optional_command = "leak"
TOML
(
  export ARANEA_MANIFEST_FILE="$odd_manifest"
  source "$repo_root/scripts/lib/manifest.sh"
  [[ -z "$(manifest_integration_field a optional_command)" ]] || {
    echo "field leaked from [other]" >&2
    exit 1
  }
  manifest_profile_exists full || {
    echo "commented profile header not found" >&2
    exit 1
  }
  [[ "$(manifest_profile_integrations full)" == a ]] || {
    echo "commented profile integrations" >&2
    exit 1
  }
  [[ -z "$(manifest_integration_field a 'opt.*')" ]] || {
    echo "field name matched as a regex" >&2
    exit 1
  }
)
rm -f "$odd_manifest"

echo "manifest contract passed"
