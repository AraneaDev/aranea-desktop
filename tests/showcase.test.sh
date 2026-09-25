#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

list_output="$("$repo_root/scripts/aranea-showcase" list)"
for surface in desktop menu menu-submenu menu-search menu-input ceremony notifications diagnostics lock boot about idle file-manager editor dawn; do
  grep -Fq "$surface" <<<"$list_output"
done

if "$repo_root/scripts/aranea-showcase" surface unknown 2>"$repo_root/tests/.showcase-error"; then
  echo "unknown showcase surface unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown surface' "$repo_root/tests/.showcase-error"
rm -f "$repo_root/tests/.showcase-error"

if "$repo_root/scripts/capture-screenshots" --surface unknown --output "$repo_root/tests" 2>"$repo_root/tests/.capture-error"; then
  echo "unknown capture surface unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown surface' "$repo_root/tests/.capture-error"
rm -f "$repo_root/tests/.capture-error"

echo "showcase contract passed"
