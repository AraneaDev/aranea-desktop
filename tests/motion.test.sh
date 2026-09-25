#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_root="$(mktemp -d)"
trap 'rm -rf "$state_root"' EXIT
hyprctl_log="$state_root/hyprctl.log"
test_path="$repo_root/tests/fake-bin:$PATH"

output="$(ARANEA_STATE_ROOT="$state_root" "$repo_root/scripts/aranea-motion" status)"
grep -Fxq 'motion: on' <<<"$output"

PATH="$test_path" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" set off >/dev/null
grep -Fxq off "$state_root/motion"
grep -Fxq 'motion: off' < <(ARANEA_STATE_ROOT="$state_root" "$repo_root/scripts/aranea-motion" status)

PATH="$test_path" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" toggle >/dev/null
grep -Fxq on "$state_root/motion"
grep -Fq 'keyword animations:enabled true' "$hyprctl_log"
grep -Fq 'popin 94%' "$hyprctl_log"
grep -Fq 'slidefade 12%' "$hyprctl_log"

: > "$hyprctl_log"
PATH="$test_path" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" set off >/dev/null
grep -Fq 'keyword animations:enabled false' "$hyprctl_log"

deferred="$(PATH="$test_path" ARANEA_HYPRCTL="$state_root/missing-hyprctl" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" apply)"
grep -Fq 'Hyprland apply deferred' <<<"$deferred"

: > "$hyprctl_log"
PATH="$test_path" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-wallpaper" motion on >/dev/null
grep -Fxq on "$state_root/motion"
grep -Fq 'keyword animations:enabled true' "$hyprctl_log"

grep -Fq 'aranea-motion" apply' "$repo_root/hooks/theme-set"
grep -Fq 'aranea-motion" apply' "$repo_root/hooks/post-boot"
grep -Fq 'motionStatePath' "$repo_root/plugins/araneadev.menu/Menu.qml"
grep -Fq 'motionStatePath' "$repo_root/plugins/araneadev.bar/Bar.qml"
grep -Fq 'root.motionEnabled && root.foregroundAnimationEnabled' "$repo_root/plugins/araneadev.bar/Bar.qml"

echo "motion contract passed"
