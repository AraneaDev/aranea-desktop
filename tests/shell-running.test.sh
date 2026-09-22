#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -x "$repo_root/scripts/ensure-shell-running" ]]
grep -Fq 'ensure-shell-running' "$repo_root/hooks/theme-set"
grep -Fq 'ensure-shell-running' "$repo_root/hooks/post-boot"
bash -n "$repo_root/scripts/ensure-shell-running"

echo "shell availability contract passed"
