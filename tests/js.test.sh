#!/usr/bin/env bash
# Runs the node:test logic suites in tests/js, so tests/run covers them too.
# (tools/check runs them itself, with coverage floors, and skips this one.)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

cd "$repo_root"
node --test tests/js/
echo "js logic contract passed"
