#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

hook_root="$(mktemp -d)"
ownership_root="$(mktemp -d)"
trap 'rm -rf "$hook_root" "$ownership_root"' EXIT
mkdir -p "$hook_root/theme-set.d" "$hook_root/post-boot.d"
mkdir -p "$ownership_root/icons/scalable/places"
ln -s "$ownership_root/icons/missing/folder.svg" "$ownership_root/icons/scalable/places/folder.svg"
cp "$repo_root/hooks/theme-set" "$hook_root/theme-set.d/theme-set"
cp "$repo_root/hooks/post-boot" "$hook_root/post-boot.d/post-boot"
printf '%s\n' "$repo_root/README.md" > "$ownership_root/managed-files"

output="$(
  ARANEA_DOCTOR_THEME='Aranea Pulse' \
  ARANEA_DOCTOR_ICON_ROOT="$ownership_root/icons" \
  ARANEA_DOCTOR_HOOK_ROOT="$hook_root" \
  ARANEA_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_SHELL_STATUS=skipped \
  ARANEA_DOCTOR_PLUGINS_STATUS=skipped \
  ARANEA_DOCTOR_RUNTIME_ROOT="$hook_root/no-runtime" \
  ARANEA_DOCTOR_QMLLINT_STATUS=ok \
  "$repo_root/scripts/aranea-doctor" --json
)"

grep -Fq '"id":"theme","status":"ok"' <<<"$output"
grep -Fq '"id":"hooks","status":"ok"' <<<"$output"
grep -Fq '"id":"manifest","status":"ok"' <<<"$output"
grep -Fq '"id":"icons","status":"repair"' <<<"$output"
grep -Fq '"id":"fonts","status":"ok"' <<<"$output"
grep -Fq '"id":"ownership","status":"ok"' <<<"$output"
grep -Fq '"id":"shell","status":"skipped"' <<<"$output"
grep -Fq '"id":"plugins","status":"skipped"' <<<"$output"
grep -Fq '"id":"runtime","status":"skipped"' <<<"$output"
grep -Fq '"id":"qmllint","status":"ok"' <<<"$output"
grep -Eq '"id":"health","status":"ok","message":"units (on|off), disk (on|off), reboot (on|off), docker (on|off[^"]*)"' <<<"$output"
grep -Fq '"status":"skipped"' <<<"$output"

while IFS= read -r line; do
  [[ "${line:0:1}" == '{' && "${line: -1}" == '}' ]]
done <<<"$output"

# --fix must reinstall a stale/missing hook in place so plugin registration
# (and everything else theme-set/post-boot drive) stops silently drifting
# after an update. Start from an empty hook_root: neither file exists yet.
fix_hook_root="$(mktemp -d)"
trap 'rm -rf "$hook_root" "$ownership_root" "$fix_hook_root"' EXIT

fix_output="$(
  ARANEA_DOCTOR_THEME='Aranea Pulse' \
  ARANEA_DOCTOR_ICON_ROOT="$ownership_root/icons" \
  ARANEA_DOCTOR_HOOK_ROOT="$fix_hook_root" \
  ARANEA_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_SHELL_STATUS=skipped \
  ARANEA_DOCTOR_PLUGINS_STATUS=skipped \
  ARANEA_DOCTOR_RUNTIME_ROOT="$fix_hook_root/no-runtime" \
  ARANEA_DOCTOR_QMLLINT_STATUS=ok \
  "$repo_root/scripts/aranea-doctor" --json --fix
)"

grep -Fq '"id":"hooks","status":"ok"' <<<"$fix_output"
cmp -s "$repo_root/hooks/theme-set" "$fix_hook_root/theme-set.d/theme-set"
cmp -s "$repo_root/hooks/post-boot" "$fix_hook_root/post-boot.d/post-boot"

# --- notification inbox health
inbox_root="$(mktemp -d)"
trap 'rm -rf "$hook_root" "$ownership_root" "$fix_hook_root" "$inbox_root"' EXIT
printf '%s\n' '{"id":1,"originalId":1,"app":"A","timestamp":1,"onScreen":false}' > "$inbox_root/1-1.json"
printf '%s\n' '{"id":2,' > "$inbox_root/2-2.json"
inbox_output="$(
  ARANEA_DOCTOR_THEME='Aranea Pulse' \
  ARANEA_DOCTOR_ICON_ROOT="$ownership_root/icons" \
  ARANEA_DOCTOR_HOOK_ROOT="$hook_root" \
  ARANEA_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_SHELL_STATUS=skipped \
  ARANEA_DOCTOR_PLUGINS_STATUS=skipped \
  ARANEA_DOCTOR_RUNTIME_ROOT="$hook_root/no-runtime" \
  ARANEA_DOCTOR_QMLLINT_STATUS=ok \
  ARANEA_DOCTOR_INBOX_ROOT="$inbox_root" \
  "$repo_root/scripts/aranea-doctor" --json
)"
grep -Fq '"id":"notifications","status":"repair","message":"inbox holds 2 entries, 1 unreadable"' <<<"$inbox_output"

rm -f "$inbox_root/2-2.json"
inbox_output="$(
  ARANEA_DOCTOR_THEME='Aranea Pulse' \
  ARANEA_DOCTOR_ICON_ROOT="$ownership_root/icons" \
  ARANEA_DOCTOR_HOOK_ROOT="$hook_root" \
  ARANEA_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_SHELL_STATUS=skipped \
  ARANEA_DOCTOR_PLUGINS_STATUS=skipped \
  ARANEA_DOCTOR_RUNTIME_ROOT="$hook_root/no-runtime" \
  ARANEA_DOCTOR_QMLLINT_STATUS=ok \
  ARANEA_DOCTOR_INBOX_ROOT="$inbox_root" \
  "$repo_root/scripts/aranea-doctor" --json
)"
grep -Fq '"id":"notifications","status":"ok","message":"inbox holds 1 entries"' <<<"$inbox_output"

echo "doctor contract passed"
