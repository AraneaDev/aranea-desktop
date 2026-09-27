#!/usr/bin/env bash
# Contract for the araneadev.osd plugin: manifest id, Osd.qml targets the
# "osd" surface, and deploy-plugins-safely/repair-shell-config know about it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Logic contract: tests/js/osd.test.js (node:test; run by tests/js.test.sh).

test -f "$repo_root/plugins/araneadev.osd/manifest.json"
grep -Fq '"id": "araneadev.osd"' "$repo_root/plugins/araneadev.osd/manifest.json"
grep -Fq 'target: "osd"' "$repo_root/plugins/araneadev.osd/Osd.qml"
grep -Fq 'araneadev.osd' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'araneadev.osd' "$repo_root/scripts/repair-shell-config"

# --- 4d: unused OSD members stay gone
if grep -Eq 'mediaOsd|iconKey' "$repo_root/plugins/araneadev.osd/Osd.qml"; then
  echo "unused mediaOsd/iconKey are back" >&2
  exit 1
fi
