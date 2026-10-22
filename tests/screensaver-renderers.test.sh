#!/usr/bin/env bash
# Shared scene HTTP boundaries and fixed renderer process ownership.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export PYTHONDONTWRITEBYTECODE=1
python3 "$repo_root/tests/screensaver-renderers.test.py"
