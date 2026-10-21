#!/usr/bin/env bash
# Real supervisor processes and IPC with fake compositor and renderer boundaries.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export PYTHONDONTWRITEBYTECODE=1
python3 "$repo_root/tests/screensaver-session.test.py"
