#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Logic contract: tests/js/osd.test.js (node:test; run by tests/js.test.sh).

test -f "$repo_root/plugins/araneadev.osd/manifest.json"
grep -Fq '"id": "araneadev.osd"' "$repo_root/plugins/araneadev.osd/manifest.json"
grep -Fq 'target: "osd"' "$repo_root/plugins/araneadev.osd/Osd.qml"
grep -Fq 'araneadev.osd' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'araneadev.osd' "$repo_root/scripts/repair-shell-config"
