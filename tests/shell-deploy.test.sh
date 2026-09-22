#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -x "$repo_root/scripts/deploy-plugins-safely" ]]
grep -Fq 'deploy-plugins-safely' "$repo_root/hooks/theme-set"
grep -Fq 'deploy-plugins-safely' "$repo_root/hooks/post-boot"
grep -Fq 'quickshell kill' "$repo_root/scripts/deploy-plugins-safely"
grep -Fq 'omarchy restart shell' "$repo_root/scripts/deploy-plugins-safely"
bash -n "$repo_root/scripts/deploy-plugins-safely"

echo "shell deployment lifecycle contract passed"
