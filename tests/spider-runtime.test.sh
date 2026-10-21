#!/usr/bin/env bash
# Validate planted gait and isolated live-server lifecycle in the standard suite.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
python3 "$repo_root/tests/spider-gait.test.py"
python3 "$repo_root/tests/spider-live.test.py"
