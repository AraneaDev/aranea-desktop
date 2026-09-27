#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

hook_root="$(mktemp -d)"
ownership_root="$(mktemp -d)"
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
grep -Eq '"id":"health","status":"(ok|repair)","message":"units (on|off), disk (on|off), reboot (on|off), docker (on|off[^"]*), actions (on|off[^"]*)"' <<<"$output"
# Without a terminal launcher the journal/log actions are off: repair, not ok.
no_term_output="$(
  ARANEA_DOCTOR_THEME='Aranea Pulse' ARANEA_DOCTOR_ICON_ROOT="$ownership_root/icons" \
  ARANEA_DOCTOR_HOOK_ROOT="$hook_root" ARANEA_OWNERSHIP_ROOT="$ownership_root" \
  ARANEA_DOCTOR_OWNERSHIP_ROOT="$ownership_root" ARANEA_DOCTOR_SHELL_STATUS=skipped \
  ARANEA_DOCTOR_PLUGINS_STATUS=skipped ARANEA_DOCTOR_RUNTIME_ROOT="$hook_root/no-runtime" \
  ARANEA_DOCTOR_QMLLINT_STATUS=ok ARANEA_DOCTOR_TERMINAL_BIN=aranea-no-such-terminal \
  "$repo_root/scripts/aranea-doctor" --json
)"
grep -Eq '"id":"health","status":"repair","message":"[^"]*actions off \(aranea-no-such-terminal missing\)"' <<<"$no_term_output"
grep -Fq '"status":"skipped"' <<<"$output"

while IFS= read -r line; do
  [[ "${line:0:1}" == '{' && "${line: -1}" == '}' ]]
done <<<"$output"

# --fix must reinstall a stale/missing hook in place so plugin registration
# (and everything else theme-set/post-boot drive) stops silently drifting
# after an update. Start from an empty hook_root: neither file exists yet.
fix_hook_root="$(mktemp -d)"

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
  ARANEA_DOCTOR_POLKIT_STATUS=skipped \
  ARANEA_DOCTOR_RUNTIME_ROOT="$hook_root/no-runtime" \
  ARANEA_DOCTOR_QMLLINT_STATUS=ok \
  ARANEA_DOCTOR_INBOX_ROOT="$inbox_root" \
  "$repo_root/scripts/aranea-doctor" --json
)"
grep -Fq '"id":"notifications","status":"ok","message":"inbox holds 1 entries"' <<<"$inbox_output"
grep -Fq '"id":"polkit","status":"skipped"' <<<"$inbox_output"

# A deliberately disabled health plugin is not a broken install.
if grep -Fq 'select(.id == "araneadev.health")' "$repo_root/scripts/aranea-doctor"; then echo "health plugin must be optional in the plugins check" >&2; exit 1; fi

# m9: the pickers are optional like the health plugin (disabling one brings
# the stock picker back; that is a choice, not a broken install).
if grep -Eq 'select\(.id == "araneadev.(clipboard|emojis)"\)' "$repo_root/scripts/aranea-doctor"; then echo "pickers must be optional in the plugins check" >&2; exit 1; fi

# The polkit prompt is optional like the pickers: disabling it brings the
# stock agent back, which is a choice, not a broken install.
if grep -Fq 'select(.id == "araneadev.polkit")' "$repo_root/scripts/aranea-doctor"; then echo "polkit must be optional in the plugins check" >&2; exit 1; fi

# Customised managed targets are reported, not flagged for repair (spec B7).
own_root="$(mktemp -d)"
printf '%s\n' "$own_root/mine.conf" > "$own_root/managed-files"
printf 'user\n' > "$own_root/mine.conf"
own_out="$(ARANEA_DOCTOR_THEME='Aranea Pulse' ARANEA_OWNERSHIP_ROOT="$own_root" ARANEA_DOCTOR_SHELL_STATUS=skipped \
  ARANEA_DOCTOR_PLUGINS_STATUS=skipped ARANEA_DOCTOR_POLKIT_STATUS=skipped ARANEA_DOCTOR_QMLLINT_STATUS=ok \
  ARANEA_DOCTOR_RUNTIME_STATUS=skipped "$repo_root/scripts/aranea-doctor" --json)"
grep -Fq '"id":"ownership","status":"ok"' <<<"$own_out"
grep -Fq '1 customised and left alone' <<<"$own_out"

echo "doctor contract passed"
