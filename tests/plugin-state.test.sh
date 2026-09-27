#!/usr/bin/env bash
# Contract for the plugin state logic: a placeholder so tests/run always has
# a shell test for this area; the real assertions live in the JS logic
# contract below.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Logic contract: tests/js/bar-model.test.js, menu-model.test.js and
# plugin-signatures.test.js (node:test; run by tests/js.test.sh).

echo "plugin state contract passed"
