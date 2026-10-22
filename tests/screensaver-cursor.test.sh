#!/usr/bin/env bash
# Real Chromium verifies hidden cursors and dismissal independently of WebGL.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export PYTHONDONTWRITEBYTECODE=1
python3 "$repo_root/tests/screensaver-cursor.test.py"
