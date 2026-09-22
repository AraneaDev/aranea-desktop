#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$(
  ARANEA_DOCTOR_THEME=Aranea \
  ARANEA_DOCTOR_HOOKS=ok \
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
