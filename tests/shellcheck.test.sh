#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck unavailable; skipped"; exit 0; }
# Same scope and flags as CI (.github/workflows/ci.yml): every shell script.
cd "$repo_root"
find scripts hooks tests tools .githooks -type f -print0 2>/dev/null |
  xargs -0 grep -lI '^#!.*sh' |
  xargs -r shellcheck -x
echo "shellcheck contract passed"
