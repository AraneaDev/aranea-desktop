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

# Inspect the real script's compositor payload: a missing/misordered curve
# must fail, as must inherited movement easing or an overshooting close/fade.
awk '
  function require(ok, message) {
    if (!ok) {
      failed = 1
      print "motion: " message > "/dev/stderr"
      exit 1
    }
  }
  /^--batch / {
    batches++
    sub(/^--batch /, "")
    count = split($0, commands, ";")
    for (i = 1; i <= count; i++) {
      command = commands[i]
      sub(/^[[:space:]]+/, "", command)
      if (command ~ /^keyword bezier /) {
        sub(/^keyword bezier /, "", command)
        split(command, curve, /,[[:space:]]*/)
        # Sample the cubic near its end: Y above 1 gives spatial overshoot.
        require(curve[2] >= 0 && curve[2] <= 1 && curve[4] >= 0 && curve[4] <= 1,
                "spring curve must have valid time control points")
        y = 3 * 0.2 * 0.2 * 0.8 * curve[3] + 3 * 0.2 * 0.8 * 0.8 * curve[5] + 0.8 * 0.8 * 0.8
        if (y > 1 && y < 1.1) spring[curve[1]] = 1
      } else if (command ~ /^keyword animation /) {
        sub(/^keyword animation /, "", command)
        split(command, animation, /,[[:space:]]*/)
        leaf = animation[1]
        require(leaf !~ /^layers/ && leaf !~ /^fade/,
                "shell layers and opacity must keep their own motion policy")
        if (leaf == "windowsIn" || leaf == "windowsMove") {
          require(spring[animation[4]], leaf " must reference a previously defined subtle overshoot curve")
          require(animation[2] == 1 && animation[3] > 1.4 && animation[3] <= 4,
                  leaf " must use a short enabled spring transition")
          windowCurve[leaf] = animation[4]
          if (leaf == "windowsIn") require(animation[5] == "popin 94%", "window opening must start at 94%")
        } else if (leaf == "windowsOut") {
          require(animation[2] == 1 && animation[3] == 1.4 && animation[4] == "linear" && animation[5] == "popin 96%",
                  "window closing must remain quick and monotonic")
          closeSeen = 1
        } else if (leaf == "workspaces") {
          require(command == "workspaces, 1, 2.4, easeInOutCubic, slidefade 12%", "workspace policy must be preserved")
          workspaceSeen = 1
        } else if (leaf == "specialWorkspace") {
          require(command == "specialWorkspace, 1, 2.6, easeInOutCubic, slidefadevert 10%", "special workspace policy must be preserved")
          specialSeen = 1
        }
      }
    }
  }
  END {
    if (failed) exit 1
    if (batches != 1 || !windowCurve["windowsIn"] || !windowCurve["windowsMove"] ||
        windowCurve["windowsIn"] != windowCurve["windowsMove"] || !closeSeen || !workspaceSeen || !specialSeen) {
      print "motion: expected one complete matching window spring batch" > "/dev/stderr"
      exit 1
    }
  }
' "$hyprctl_log"

: >"$hyprctl_log"
PATH="$test_path" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" set off >/dev/null
grep -Fxq 'keyword animations:enabled false' "$hyprctl_log"
[[ "$(wc -l <"$hyprctl_log")" -eq 1 ]]

# Lua-configured Hyprland rejects legacy keywords with a textual response
# even when hyprctl exits successfully. Replay the same policy through eval.
lua_hyprctl="$state_root/lua-hyprctl"
cat >"$lua_hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${ARANEA_HYPRCTL_LOG:?}"
if [[ "$1" == eval ]]; then
  printf '%s\n' "${ARANEA_EVAL_RESPONSE:-ok}"
else
  printf '%s\n' "keyword can't work with non-legacy parsers. Use eval."
fi
EOF
chmod +x "$lua_hyprctl"
: >"$hyprctl_log"
PATH="$test_path" ARANEA_HYPRCTL="$lua_hyprctl" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" set on >/dev/null
lua_request="$(sed -n '2p' "$hyprctl_log")"
[[ "$(wc -l <"$hyprctl_log")" -eq 2 ]] || {
  echo 'motion: Lua compositor requires an eval fallback' >&2
  exit 1
}
grep -Fq 'eval hl.config({ animations = { enabled = true } })' <<<"$lua_request"
grep -Fq 'hl.curve("araneaSpring", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1.14 } } })' <<<"$lua_request"
grep -Fq 'hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.8, bezier = "araneaSpring", style = "popin 94%" })' <<<"$lua_request"
grep -Fq 'hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.8, bezier = "araneaSpring" })' <<<"$lua_request"
grep -Fq 'hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.4, bezier = "linear", style = "popin 96%" })' <<<"$lua_request"
grep -Fq 'hl.animation({ leaf = "workspaces", enabled = true, speed = 2.4, bezier = "easeInOutCubic", style = "slidefade 12%" })' <<<"$lua_request"
grep -Fq 'hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.6, bezier = "easeInOutCubic", style = "slidefadevert 10%" })' <<<"$lua_request"
[[ "$lua_request" == *'hl.curve('*'hl.animation('* ]]
[[ "$lua_request" != *'leaf = "layers'* && "$lua_request" != *'leaf = "fade'* ]]

: >"$hyprctl_log"
PATH="$test_path" ARANEA_HYPRCTL="$lua_hyprctl" ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" set off >/dev/null
grep -Fxq 'eval hl.config({ animations = { enabled = false } })' "$hyprctl_log"
[[ "$(wc -l <"$hyprctl_log")" -eq 2 ]]

# A rejected Lua apply must not report success just because hyprctl exits 0.
if PATH="$test_path" ARANEA_HYPRCTL="$lua_hyprctl" ARANEA_EVAL_RESPONSE='bad animation' \
  ARANEA_HYPRCTL_LOG="$hyprctl_log" ARANEA_STATE_ROOT="$state_root" \
  "$repo_root/scripts/aranea-motion" apply >"$state_root/rejected-output" 2>"$state_root/rejected-error"; then
  echo 'motion: compositor rejection must fail apply' >&2
  exit 1
fi
grep -Fq 'bad animation' "$state_root/rejected-error"
[[ ! -s "$state_root/rejected-output" ]]

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
