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
grep -Fq 'root.motionEnabled && root.foregroundAnimationEnabled' "$repo_root/plugins/araneadev.bar/Bar.qml"

# --- 4b: every QML consumer reads the shared motion singleton.
for qml in \
  plugins/araneadev.bar/Bar.qml \
  plugins/araneadev.menu/MenuStyle.qml \
  plugins/araneadev.notifications/Service.qml \
  plugins/araneadev.osd/Osd.qml \
  plugins/araneadev.clipboard/Clipboard.qml \
  plugins/araneadev.emojis/Emojis.qml \
  plugins/araneadev.polkit/PolkitAgent.qml; do
  file="$repo_root/$qml"
  grep -Eq '(Aranea\.)?MotionState\.motionEnabled' "$file" || {
    echo "$qml: motion must come from the shared MotionState singleton" >&2
    exit 1
  }
  # Only araneadev.shared knows where the motion preference is stored.
  if grep -Eq 'motionStatePath|aranea/motion' "$file"; then
    echo "$qml: the motion file belongs to MotionState.qml; bind MotionState.motionEnabled only" >&2
    exit 1
  fi
done

# JSON status separates configured motion from unavailable live observation.
ARANEA_HYPRCTL="$state_root/missing-hyprctl" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" status --json | jq -e '.configured == "on" and .applied == null and .application == "deferred"' >/dev/null

# Current Hyprland exposes boolean options as .bool; older hosts used .int.
observer="$state_root/motion-observer"
cat >"$observer" <<'EOF'
#!/usr/bin/env bash
# Isolated compositor JSON observation, never a live mutation.
[[ "$*" == '-j getoption animations:enabled' ]] || exit 3
printf '%s\n' "$ARANEA_MOTION_OBSERVATION"
EOF
chmod +x "$observer"
for observation in '{"option":"animations:enabled","bool":true,"set":true}' '{"int":1}'; do
  ARANEA_MOTION_OBSERVATION="$observation" ARANEA_HYPRCTL="$observer" ARANEA_STATE_ROOT="$state_root" \
    "$repo_root/scripts/aranea-motion" status --json | jq -e '.configured == "on" and .applied == "on" and .application == "applied"' >/dev/null
done
for observation in '{"option":"animations:enabled","bool":false,"set":true}' '{"int":0}'; do
  ARANEA_MOTION_OBSERVATION="$observation" ARANEA_HYPRCTL="$observer" ARANEA_STATE_ROOT="$state_root" \
    "$repo_root/scripts/aranea-motion" status --json | jq -e '.configured == "on" and .applied == "off" and .application == "pending"' >/dev/null
done
for observation in '{"bool":"false"}' '{"bool":null}' '{"int":2}' '{}'; do
  ARANEA_MOTION_OBSERVATION="$observation" ARANEA_HYPRCTL="$observer" ARANEA_STATE_ROOT="$state_root" \
    "$repo_root/scripts/aranea-motion" status --json | jq -e '.applied == null and .application == "unavailable"' >/dev/null
done

echo "motion contract passed"
