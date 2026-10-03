#!/usr/bin/env bash
# Contract for the qml stage's header-brace check (tools/lib/check-qml.sh
# qml_header_braces): a brace in a QML file's header comments fails, a
# normal file passes, and a file without imports only has its header read.
#
# Usage: tests/qml-header-braces.test.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

check_root="$ARANEA_TEST_SANDBOX/tree"
mkdir -p "$check_root"
# shellcheck disable=SC1091
source "$repo_root/tools/lib/check-qml.sh"

cat >"$check_root/Bad.qml" <<'QML'
// A header that names a shape {row, pill}.
import QtQuick
Item {}
QML
cat >"$check_root/Good.qml" <<'QML'
// A plain header.
pragma ComponentBehavior: Bound
import QtQuick
Item {
  // A brace in a body comment {is fine}.
}
QML
cat >"$check_root/NoImports.qml" <<'QML'
// A header without imports.

Item {
  width: 1
}
QML

if out="$(qml_header_braces Bad.qml)"; then
  echo "a brace in the header passed" >&2
  exit 1
fi
grep -Fq "brace before imports: Bad.qml:1:" <<<"$out" || {
  printf 'unexpected report: %s\n' "$out" >&2
  exit 1
}
qml_header_braces Good.qml || {
  echo "a normal file failed" >&2
  exit 1
}
qml_header_braces NoImports.qml || {
  echo "a file without imports flagged its body braces" >&2
  exit 1
}

echo "qml header brace contract passed"
