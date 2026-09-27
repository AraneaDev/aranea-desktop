#!/usr/bin/env bash
# Contract for scripts/ensure-shell-running: it is executable, has valid
# syntax, and is wired into both the theme-set and post-boot hooks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

[[ -x "$repo_root/scripts/ensure-shell-running" ]]
grep -Fq 'ensure-shell-running' "$repo_root/hooks/theme-set"
grep -Fq 'ensure-shell-running' "$repo_root/hooks/post-boot"
bash -n "$repo_root/scripts/ensure-shell-running"

echo "shell availability contract passed"
