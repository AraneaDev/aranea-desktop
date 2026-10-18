#!/usr/bin/env bash
# The host Color singleton is read only as Commons.Color. Since Qt 6.12,
# QtQuick also exports a Color type, and a bare Color can resolve to it
# whatever the import order, so every token reads as undefined.
#
# Usage: tests/qml-color-qualified.test.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Code lines only: comments may still name Color.qml.
bare="$(grep -rnE '(^|[^.A-Za-z0-9_])Color\.[a-zA-Z]' \
  "$repo_root/plugins" "$repo_root/tests/qml" "$repo_root/tools" \
  --include='*.qml' --include='token-generator.mjs' |
  grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)"
if [[ -n "$bare" ]]; then
  echo "bare Color singleton use; write Commons.Color (import qs.Commons as Commons):"
  printf "  %s\n" "${bare//"$repo_root"\//}"
  exit 1
fi

# Every file using Commons.Color imports the alias.
missing=0
while IFS= read -r file; do
  grep -qx 'import qs.Commons as Commons' "$file" || {
    echo "missing 'import qs.Commons as Commons': ${file#"$repo_root"/}"
    missing=1
  }
done < <(grep -rlF 'Commons.Color.' "$repo_root/plugins" "$repo_root/tests/qml" --include='*.qml')
((missing == 0)) || exit 1
echo "Color singleton reads are qualified"
