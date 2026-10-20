#!/usr/bin/env bash
# Diagnostic continuation lines must not become independent baseline entries.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
check_root="$repo_root"
source "$repo_root/tools/lib/check-qml.sh"
report='{"files":[{"filename":"plugins/Test.qml","warnings":[{"id":"block-scope-var-declaration","message":"var declaration in block scope is hoisted to function scope\nReplace it with const or let to silence the warning\n"},{"id":"block-scope-var-declaration","message":"var declaration in block scope is hoisted to function scope\nReplace it with const or let to silence the warning\n"}]}]}'
actual="$(qml_warning_counts <<<"$report")"
expected=$'2\tplugins/Test.qml:block-scope-var-declaration:var declaration in block scope is hoisted to function scope'
[[ "$actual" == "$expected" ]] || {
  printf 'unexpected warning counts: %s\n' "$actual" >&2
  exit 1
}
echo 'qml warning count contract passed'
