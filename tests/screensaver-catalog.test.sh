#!/usr/bin/env bash
# Catalog, preference storage, and read-only owner CLI filesystem contracts.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export PYTHONDONTWRITEBYTECODE=1
python3 "$repo_root/tests/screensaver-catalog.test.py"
