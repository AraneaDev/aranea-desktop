#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

hook_root="$(mktemp -d)"
ownership_root="$(mktemp -d)"
trap 'rm -rf "$hook_root" "$ownership_root"' EXIT
mkdir -p "$hook_root/theme-set.d" "$hook_root/post-boot.d"
cp "$repo_root/hooks/theme-set" "$hook_root/theme-set.d/theme-set"
cp "$repo_root/hooks/post-boot" "$hook_root/post-boot.d/post-boot"
printf '%s\n' "$repo_root/README.md" > "$ownership_root/managed-files"

output="$(
  ARANEA_DOCTOR_THEME=Aranea \
  ARANEA_DOCTOR_HOOK_ROOT="$hook_root" \
  ARANEA_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_SHELL_STATUS=skipped \
  ARANEA_DOCTOR_PLUGINS_STATUS=skipped \
  ARANEA_DOCTOR_RUNTIME_STATUS=skipped \
  ARANEA_DOCTOR_QMLLINT_STATUS=ok \
  "$repo_root/scripts/aranea-doctor" --json
)"

grep -Fq '"id":"theme","status":"ok"' <<<"$output"
grep -Fq '"id":"hooks","status":"ok"' <<<"$output"
grep -Fq '"id":"manifest","status":"ok"' <<<"$output"
grep -Fq '"id":"fonts","status":"ok"' <<<"$output"
grep -Fq '"id":"ownership","status":"ok"' <<<"$output"
grep -Fq '"id":"shell","status":"skipped"' <<<"$output"
grep -Fq '"id":"plugins","status":"skipped"' <<<"$output"
grep -Fq '"id":"runtime","status":"skipped"' <<<"$output"
grep -Fq '"id":"qmllint","status":"ok"' <<<"$output"
grep -Fq '"status":"skipped"' <<<"$output"

while IFS= read -r line; do
  [[ "${line:0:1}" == '{' && "${line: -1}" == '}' ]]
done <<<"$output"

echo "doctor contract passed"
