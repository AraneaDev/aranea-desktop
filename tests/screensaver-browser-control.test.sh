#!/usr/bin/env bash
# Private browser protocol framing, crash identity and owned FD cleanup.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export PYTHONDONTWRITEBYTECODE=1
python3 "$repo_root/tests/screensaver-browser-control.test.py"
