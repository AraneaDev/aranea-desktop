#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
state="$test_root/state"; config="$test_root/config"; mkdir -p "$state" "$config"
status="$({ XDG_CONFIG_HOME="$config" ARANEA_OWNERSHIP_ROOT="$state" "$repo_root/scripts/aranea-integrations" status --json; })"
grep -Fq '"id":"terminal"' <<<"$status"
grep -Fq '"availability":"available"' <<<"$status"
XDG_CONFIG_HOME="$config" ARANEA_OWNERSHIP_ROOT="$state" "$repo_root/scripts/aranea-integrations" activate session --yes >/dev/null
test -L "$config/omarchy/session/aranea.css"
XDG_CONFIG_HOME="$config" ARANEA_OWNERSHIP_ROOT="$state" "$repo_root/scripts/aranea-integrations" deactivate session >/dev/null
test ! -e "$config/omarchy/session/aranea.css"
if XDG_CONFIG_HOME="$config" ARANEA_OWNERSHIP_ROOT="$state" "$repo_root/scripts/aranea-integrations" activate nope --yes >/dev/null 2>&1; then exit 1; fi
echo "integration controller contract passed"
