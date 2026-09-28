#!/usr/bin/env bash

set -euo pipefail

# Readers for theme-manifest.toml (ARANEA_MANIFEST_FILE overrides the path):
# profiles, their integrations, and integration fields.

manifest_file="${ARANEA_MANIFEST_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/theme-manifest.toml}"

# True when the manifest has a [profiles.PROFILE] section.
manifest_profile_exists() {
  local profile="$1"
  SECTION="[profiles.$profile]" awk '
    BEGIN { section = ENVIRON["SECTION"] }
    { line = $0; sub(/[[:space:]]*(#.*)?$/, "", line) }
    line == section { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$manifest_file"
}

# Prints the integration ids listed by profile PROFILE, one per line.
manifest_profile_integrations() {
  local profile="$1"
  SECTION="[profiles.$profile]" awk '
    BEGIN { section = ENVIRON["SECTION"] }
    { line = $0; sub(/[[:space:]]*(#.*)?$/, "", line) }
    line == section { inside = 1; next }
    inside && /^\[/ { exit }
    inside && /^integrations[[:space:]]*=/ {
      line = $0
      sub(/^[^=]*=[[:space:]]*\[/, "", line)
      sub(/\][[:space:]]*$/, "", line)
      gsub(/"/, "", line)
      gsub(/[[:space:]]/, "", line)
      n = split(line, values, ",")
      for (i = 1; i <= n; i++) if (values[i] != "") print values[i]
      exit
    }
  ' "$manifest_file"
}

# True when the manifest has an [[integrations]] entry with id INTEGRATION.
manifest_integration_exists() {
  local integration="$1"
  WANTED="$integration" awk '
    BEGIN { wanted = ENVIRON["WANTED"]; wanted_field = ENVIRON["WANTED_FIELD"] }
    /^\[\[integrations\]\][[:space:]]*(#.*)?$/ { in_block = 1; found = 0; next }
    in_block && /^\[/ { in_block = 0 }
    in_block && /^id[[:space:]]*=/ {
      value = $0
      sub(/^id[[:space:]]*=[[:space:]]*"/, "", value)
      sub(/"[[:space:]]*$/, "", value)
      if (value == wanted) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' "$manifest_file"
}

# Prints FIELD of integration INTEGRATION without surrounding quotes
# (nothing when absent). The lookup stays inside that [[integrations]] block.
manifest_integration_field() {
  local integration="$1"
  local field="$2"
  WANTED="$integration" WANTED_FIELD="$field" awk '
    BEGIN { wanted = ENVIRON["WANTED"]; wanted_field = ENVIRON["WANTED_FIELD"] }
    /^\[\[integrations\]\][[:space:]]*(#.*)?$/ { in_block = 1; found = 0; next }
    in_block && /^\[/ { in_block = 0; found = 0 }
    in_block && /^id[[:space:]]*=/ {
      value = $0
      sub(/^id[[:space:]]*=[[:space:]]*"/, "", value)
      sub(/"[[:space:]]*$/, "", value)
      if (value == wanted) { found = 1; next }
    }
    # The field name is compared as text, never as a regex.
    found && in_block && index($0, wanted_field) == 1 && substr($0, length(wanted_field) + 1) ~ /^[[:space:]]*=/ {
      line = $0
      sub(/^[^=]*=[[:space:]]*/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }
  ' "$manifest_file"
}
