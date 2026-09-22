#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

hook_root="$(mktemp -d)"
trap 'rm -rf "$hook_root"' EXIT
mkdir -p "$hook_root/theme-set.d" "$hook_root/post-boot.d"
cp "$repo_root/hooks/theme-set" "$hook_root/theme-set.d/theme-set"
cp "$repo_root/hooks/post-boot" "$hook_root/post-boot.d/post-boot"

output="$(
  ARANEA_DOCTOR_THEME=Aranea \
  ARANEA_DOCTOR_HOOK_ROOT="$hook_root" \
  "$repo_root/scripts/aranea-doctor" --json
)"

grep -Fq '"id":"theme","status":"ok"' <<<"$output"
grep -Fq '"id":"hooks","status":"ok"' <<<"$output"
grep -Fq '"id":"manifest","status":"ok"' <<<"$output"
grep -Fq '"status":"skipped"' <<<"$output"

while IFS= read -r line; do
  [[ "${line:0:1}" == '{' && "${line: -1}" == '}' ]]
done <<<"$output"

echo "doctor contract passed"
