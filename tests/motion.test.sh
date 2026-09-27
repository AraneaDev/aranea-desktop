#!/usr/bin/env bash
# Contract for scripts/aranea-motion: status/set/toggle persist to the state
# file and drive hyprctl's animations keyword and named animation curves,
# a missing hyprctl defers instead of failing, aranea-wallpaper motion
# forwards to the same state, and the hooks/plugins read the same state path.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
state_root="$(mktemp -d)"
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

: >"$hyprctl_log"
PATH="$test_path" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" set off >/dev/null
grep -Fq 'keyword animations:enabled false' "$hyprctl_log"

deferred="$(PATH="$test_path" ARANEA_HYPRCTL="$state_root/missing-hyprctl" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" apply)"
grep -Fq 'Hyprland apply deferred' <<<"$deferred"

: >"$hyprctl_log"
PATH="$test_path" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-wallpaper" motion on >/dev/null
grep -Fxq on "$state_root/motion"
grep -Fq 'keyword animations:enabled true' "$hyprctl_log"

grep -Fq 'aranea-motion" apply' "$repo_root/hooks/theme-set"
grep -Fq 'aranea-motion" apply' "$repo_root/hooks/post-boot"
grep -Fq 'motionStatePath' "$repo_root/plugins/araneadev.menu/Menu.qml"
grep -Fq 'motionStatePath' "$repo_root/plugins/araneadev.bar/Bar.qml"
grep -Fq 'root.motionEnabled && root.foregroundAnimationEnabled' "$repo_root/plugins/araneadev.bar/Bar.qml"

# --- 4b: one motion rule in every plugin: env 1 wins, else the file's "off",
# read with text() (text is a function), and a missing file falls back to env.
for qml in \
  plugins/araneadev.bar/Bar.qml \
  plugins/araneadev.menu/Menu.qml \
  plugins/araneadev.notifications/Service.qml \
  plugins/araneadev.osd/Osd.qml \
  plugins/araneadev.clipboard/Clipboard.qml \
  plugins/araneadev.emojis/Emojis.qml \
  plugins/araneadev.polkit/PolkitAgent.qml; do
  file="$repo_root/$qml"
  if grep -Fq 'String(text ||' "$file"; then
    echo "$qml reads the motion file with text instead of text()" >&2
    exit 1
  fi
  grep -Eq 'onLoaded: (root|service)\.motionEnabled = Quickshell\.env\("ARANEA_REDUCED_MOTION"\) !== "1" && String\(text\(\) \|\| ""\)\.trim\(\) !== "off"' "$file" || {
    echo "$qml: motion onLoaded must apply the env and the file" >&2
    exit 1
  }
  grep -Eq 'onLoadFailed: (root|service)\.motionEnabled = Quickshell\.env\("ARANEA_REDUCED_MOTION"\) !== "1"$' "$file" || {
    echo "$qml: motion onLoadFailed must fall back to the env" >&2
    exit 1
  }
done

echo "motion contract passed"
