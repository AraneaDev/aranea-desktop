#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if "$repo_root/scripts/install-integration" --dry-run missing-integration 2>"$repo_root/tests/.integration-error"; then
  echo "unknown integration unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown integration' "$repo_root/tests/.integration-error"
rm -f "$repo_root/tests/.integration-error"

echo "integration contract passed"
