#!/usr/bin/env bash

set -euo pipefail

manifest_file="${ARANEA_MANIFEST_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/theme-manifest.toml}"

manifest_profile_exists() {
  local profile="$1"
  grep -Eq "^\[profiles\.${profile//./\.}\]$" "$manifest_file"
}

manifest_profile_integrations() {
  local profile="$1"
  awk -v section="[profiles.$profile]" '
    $0 == section { inside = 1; next }
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

manifest_integration_exists() {
  local integration="$1"
  awk -v wanted="$integration" '
    /^\[\[integrations\]\]$/ { in_block = 1; found = 0; next }
    in_block && /^\[/ { in_block = 0 }
    in_block && $0 ~ "^id[[:space:]]*=[[:space:]]*\"" wanted "\"$" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$manifest_file"
}

manifest_integration_field() {
  local integration="$1"
  local field="$2"
  awk -v wanted="$integration" -v wanted_field="$field" '
    /^\[\[integrations\]\]$/ { in_block = 1; found = 0; next }
    in_block && /^\[/ { in_block = 0 }
    in_block && $0 ~ "^id[[:space:]]*=[[:space:]]*\"" wanted "\"$" { found = 1; next }
    found && $0 ~ "^" wanted_field "[[:space:]]*=" {
      line = $0
      sub(/^[^=]*=[[:space:]]*/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }
  ' "$manifest_file"
}
