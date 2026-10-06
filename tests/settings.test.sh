#!/usr/bin/env bash
# Settings runs real helpers against sandboxed compositor/wallpaper owners.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
sandbox_root="$ARANEA_TEST_SANDBOX"
ctl="$repo_root/scripts/aranea-settings"
export ARANEA_STATE_ROOT="$XDG_STATE_HOME/aranea"
export ARANEA_SYSTEMD_USER_DIR="$XDG_CONFIG_HOME/systemd/user"
export ARANEA_HYPRCTL="$sandbox_root/hyprctl"
export ARANEA_SYSTEMCTL="$sandbox_root/systemctl"
export ARANEA_WALLPAPER_APPLIER="$sandbox_root/applier"
cat >"$ARANEA_HYPRCTL" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$ARANEA_TEST_SANDBOX/hyprctl.log"
if [[ "$*" == 'monitors -j' ]]; then
  [[ "${FAIL_DISPLAY_READ:-0}" != 1 && ! -e "$ARANEA_TEST_SANDBOX/lost-display" ]] || exit 7
  if [[ "${FOCUS_BEFORE_DISPATCH:-0}" == 1 ]]; then
    count="$(cat "$ARANEA_TEST_SANDBOX/display-reads" 2>/dev/null || echo 0)"
    count=$((count + 1))
    echo "$count" >"$ARANEA_TEST_SANDBOX/display-reads"
    if ((count > 1)); then
      jq '.[0].name = "DP-1"' "$ARANEA_TEST_SANDBOX/monitors.json"
      exit
    fi
  fi
  cat "$ARANEA_TEST_SANDBOX/monitors.json"
elif [[ "$*" == reload ]]; then
  [[ "${FAIL_DISPLAY_RELOAD:-0}" != 1 ]] || exit 12
elif [[ "$*" == configerrors ]]; then
  [[ "${FAIL_DISPLAY_CONFIG:-0}" != 1 ]] || echo 'invalid monitor config'
elif [[ "$*" == '-j getoption animations:enabled' ]]; then
  [[ "${FAIL_READ:-0}" != 1 ]] || exit 7
  printf '{"int":%s}\n' "$(cat "$ARANEA_TEST_SANDBOX/live-motion" 2>/dev/null || echo 1)"
else
  [[ "${FAIL_APPLY:-0}" != 1 ]] || { echo 'compositor rejected request' >&2; exit 7; }
  if [[ "$*" == *false* ]]; then echo 0; else echo 1; fi >"$ARANEA_TEST_SANDBOX/live-motion"
fi
STUB
cat >"$ARANEA_SYSTEMCTL" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$ARANEA_TEST_SANDBOX/systemctl.log"
[[ "${FAIL_TIMER:-0}" != 1 ]] || { echo 'timer rejected request' >&2; exit 9; }
if [[ "${FAIL_SYSTEMCTL_COMMAND:-}" == enable && "$*" == *' enable '* ]] ||
  [[ "${FAIL_RELOAD_AFTER_REMOVAL:-0}" == 1 && "$*" == *daemon-reload* && ! -e "$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.timer" ]]; then
  echo 'selective timer request rejected' >&2
  exit 11
fi
case "$*" in
  *is-active*) if [[ "$(cat "$ARANEA_TEST_SANDBOX/live-timer" 2>/dev/null || echo inactive)" == active ]]; then echo active; else echo inactive; exit 3; fi ;;
  *enable*) echo active >"$ARANEA_TEST_SANDBOX/live-timer" ;;
  *disable*) echo inactive >"$ARANEA_TEST_SANDBOX/live-timer" ;;
  *daemon-reload*)
    if [[ "${EXPECT_REMOVED:-0}" == 1 ]]; then
      [[ ! -e "$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.timer" ]] || exit 12
    fi ;;
esac
STUB
cat >"$ARANEA_WALLPAPER_APPLIER" <<'STUB'
#!/usr/bin/env bash
set -eu
[[ $# == 1 ]] || exit 8
printf '%s\n' "$1" >"$ARANEA_TEST_SANDBOX/applier.log"
mkdir -p "$HOME/.local/state/omarchy/current"
ln -sfn "$1" "$HOME/.local/state/omarchy/current/background"
STUB
chmod +x "$ARANEA_HYPRCTL" "$ARANEA_SYSTEMCTL" "$ARANEA_WALLPAPER_APPLIER"
# A single JSON object, accurate defaults, catalog paths, unavailable owner.
"$ctl" status --json >"$sandbox_root/status.json"
jq -e '.schemaVersion == 1 and .operation == "status" and .ok
  and (.state.integrations | type == "array")
  and .state.motion.configured == "on" and .state.motion.applied == "on"
  and .state.wallpaper.activeId == null and .state.wallpaper.availability == "unavailable"
  and .state.schedule.enabled == false and .state.schedule.dawn == "06:00"
  and (.state.wallpapers | length == 8)
  and (.state.wallpapers[] | (.path | startswith("/")) and (.available | type == "boolean"))' "$sandbox_root/status.json" >/dev/null
[[ "$(jq -s length "$sandbox_root/status.json")" == 1 ]]
test ! -e "$ARANEA_STATE_ROOT" # Reads do not create state.
# Real adapter exposes persisted defaults and validates the font boundary.
"$ctl" configure fonts '' '' --json >"$sandbox_root/fonts.json"
jq -e '.ok and .operation == "configure fonts" and .state.fonts.uiFamily == "" and .state.fonts.technicalFamily == "" and .state.fonts.availability == "available"' "$sandbox_root/fonts.json" >/dev/null
rm "$XDG_CONFIG_HOME/aranea/fonts.json"
# Exact argv validation prevents additional arguments, IDs, and shell text.
reject() {
  local want="$1" rc=0
  shift
  "$ctl" "$@" >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
  [[ $rc != 0 ]]
  jq -e --arg want "$want" '.ok == false and .error.code == $want' "$sandbox_root/result.json" >/dev/null
}
reject UNKNOWN_OPERATION surprise --json
reject INVALID_ARGUMENTS set motion on extra --json
reject INVALID_ARGUMENTS status extra --json
reject INVALID_ARGUMENTS set motion maybe --json
reject UNKNOWN_ID set wallpaper 'day;touch /tmp/settings-injection' --json
reject UNKNOWN_ID set integration nope active --json
reject INVALID_SCHEDULE configure schedule 25:00 08:00 18:00 20:00 --json
reject INVALID_SCHEDULE configure schedule 08:00 06:00 18:00 20:00 --json
test ! -e "$ARANEA_STATE_ROOT"
test ! -e "$ARANEA_SYSTEMD_USER_DIR"
# Real helpers apply via argv and adapter refreshes owner readback.
"$ctl" set motion off --json >"$sandbox_root/result.json"
jq -e '.ok and .state.motion.configured == "off" and .state.motion.applied == "off"' "$sandbox_root/result.json" >/dev/null
"$ctl" set wallpaper day --json >"$sandbox_root/result.json"
jq -e '.ok and .state.wallpaper.activeId == "day"' "$sandbox_root/result.json" >/dev/null
grep -Fxq "$repo_root/backgrounds/background-day.png" "$sandbox_root/applier.log"
# External changes read the authoritative symlink, including custom images.
ln -sfn "$repo_root/backgrounds/variants/dusk.png" "$HOME/.local/state/omarchy/current/background"
"$ctl" status --json | jq -e '.state.wallpaper.activeId == "dusk"' >/dev/null
printf custom >"$sandbox_root/custom.png"
ln -sfn "$sandbox_root/custom.png" "$HOME/.local/state/omarchy/current/background"
"$ctl" status --json | jq -e '.state.wallpaper.activeId == null and .state.wallpaper.availability == "available"' >/dev/null
# Failure preserves persisted-vs-observed distinction and helper exit/diagnostic.
rc=0
FAIL_APPLY=1 "$ctl" set motion on --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 7 ]]
jq -e '.ok == false and .error.code == "HELPER_FAILED"
  and .state.motion.configured == "on" and .state.motion.applied == "off"' "$sandbox_root/result.json" >/dev/null
grep -Fq 'compositor rejected request' "$sandbox_root/error"
ARANEA_HYPRCTL="$sandbox_root/missing" "$ctl" set motion off --json | jq -e '.ok and .state.motion.configured == "off" and .state.motion.applied == null and .state.motion.application == "deferred"' >/dev/null
# Enable/configure use the schedule helper and validate before changing files.
"$ctl" set schedule on --json >"$sandbox_root/result.json"
jq -e '.ok and .state.schedule.enabled == true' "$sandbox_root/result.json" >/dev/null
"$ctl" configure schedule 05:30 08:00 18:30 21:00 --json >"$sandbox_root/result.json"
jq -e '.ok and .state.schedule.dawn == "05:30" and .state.schedule.night == "21:00"' "$sandbox_root/result.json" >/dev/null
cp -a "$XDG_CONFIG_HOME/aranea" "$sandbox_root/config-before"
cp -a "$ARANEA_SYSTEMD_USER_DIR" "$sandbox_root/units-before"
reject INVALID_SCHEDULE configure schedule 05:30 05:30 18:00 20:00 --json
diff -r "$sandbox_root/config-before" "$XDG_CONFIG_HOME/aranea"
diff -r "$sandbox_root/units-before" "$ARANEA_SYSTEMD_USER_DIR"
rc=0
FAIL_TIMER=1 "$ctl" configure schedule 04:00 07:00 17:00 22:00 --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 9 ]]
jq -e '.ok == false and .state.schedule.dawn == "05:30"' "$sandbox_root/result.json" >/dev/null
diff -r "$sandbox_root/config-before" "$XDG_CONFIG_HOME/aranea"
diff -r "$sandbox_root/units-before" "$ARANEA_SYSTEMD_USER_DIR"
[[ "$(cat "$ARANEA_STATE_ROOT/wallpaper-schedule")" == on ]]
# Both heredoc writes must fail before replacing either existing unit.
write_fail_bin="$(mktemp -d)"
ARANEA_REAL_CAT="$(command -v cat)"
export ARANEA_REAL_CAT
cat >"$write_fail_bin/cat" <<'STUB'
#!/usr/bin/env bash
set -eu
if [[ $# == 0 ]]; then
  count="$("$ARANEA_REAL_CAT" "$ARANEA_TEST_SANDBOX/unit-write-count" 2>/dev/null || echo 0)"
  count=$((count + 1))
  echo "$count" >"$ARANEA_TEST_SANDBOX/unit-write-count"
  if [[ "$count" == "${FAIL_UNIT_WRITE:-0}" ]]; then
    echo 'partial unit content'
    echo 'unit content write rejected' >&2
    exit 23
  fi
fi
exec "$ARANEA_REAL_CAT" "$@"
STUB
chmod +x "$write_fail_bin/cat"
for failed_write in 1 2; do
  rm -f "$sandbox_root/unit-write-count"
  : >"$sandbox_root/systemctl.log"
  rc=0
  PATH="$write_fail_bin:$PATH" FAIL_UNIT_WRITE="$failed_write" "$ctl" configure schedule 04:00 07:00 17:00 22:00 --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
  [[ $rc == 23 ]]
  jq -e '.ok == false and .error.code == "HELPER_FAILED" and .state.schedule.dawn == "05:30"' "$sandbox_root/result.json" >/dev/null
  grep -Fq 'unit content write rejected' "$sandbox_root/error"
  diff -r "$sandbox_root/config-before" "$XDG_CONFIG_HOME/aranea"
  diff -r "$sandbox_root/units-before" "$ARANEA_SYSTEMD_USER_DIR"
  [[ "$(cat "$ARANEA_STATE_ROOT/wallpaper-schedule")" == on ]]
  if grep -Eq -- '--user (enable|disable)' "$sandbox_root/systemctl.log"; then exit 1; fi
  [[ -z "$(find "$ARANEA_SYSTEMD_USER_DIR" -name '.wallpaper-*' -print)" ]]
done
# Enable failure after a successful reload restores configured files.
: >"$sandbox_root/systemctl.log"
rc=0
FAIL_SYSTEMCTL_COMMAND=enable "$ctl" configure schedule 04:00 07:00 17:00 22:00 --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 11 ]]
mapfile -t timer_calls < <(sed '/--user is-active/d' "$sandbox_root/systemctl.log")
[[ "${timer_calls[0]}" == '--user daemon-reload' && "${timer_calls[1]}" == '--user enable --now aranea-wallpaper-day-night.timer' ]]
jq -e '.ok == false and .state.schedule.enabled == true and .state.schedule.applied == true' "$sandbox_root/result.json" >/dev/null
diff -r "$sandbox_root/config-before" "$XDG_CONFIG_HOME/aranea"
diff -r "$sandbox_root/units-before" "$ARANEA_SYSTEMD_USER_DIR"
# Reload failure after disable/removal restores files but reports inactive live timer.
: >"$sandbox_root/systemctl.log"
rc=0
FAIL_RELOAD_AFTER_REMOVAL=1 "$ctl" set schedule off --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 11 ]]
mapfile -t timer_calls < <(sed '/--user is-active/d' "$sandbox_root/systemctl.log")
[[ "${timer_calls[0]}" == '--user disable --now aranea-wallpaper-day-night.timer' && "${timer_calls[1]}" == '--user daemon-reload' ]]
jq -e '.ok == false and .state.schedule.enabled == true and .state.schedule.applied == false' "$sandbox_root/result.json" >/dev/null
diff -r "$sandbox_root/units-before" "$ARANEA_SYSTEMD_USER_DIR"
[[ "$(cat "$ARANEA_STATE_ROOT/wallpaper-schedule")" == on ]]
"$ctl" set schedule on --json >/dev/null
# Failed disable remains configured on; no files removed on failed live apply.
rc=0
FAIL_TIMER=1 "$ctl" set schedule off --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 9 ]]
diff -r "$sandbox_root/units-before" "$ARANEA_SYSTEMD_USER_DIR"
[[ "$(cat "$ARANEA_STATE_ROOT/wallpaper-schedule")" == on ]]
# Failed initial enable restores the absence of schedule config/state/units.
fresh="$(mktemp -d)"
rc=0
ARANEA_CONFIG_HOME="$fresh/config" ARANEA_STATE_ROOT="$fresh/state" ARANEA_SYSTEMD_USER_DIR="$fresh/units" FAIL_TIMER=1 \
  "$ctl" set schedule on --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 9 ]]
test ! -e "$fresh/config/aranea/wallpaper-schedule.conf"
test ! -e "$fresh/state/wallpaper-schedule"
test ! -e "$fresh/units/aranea-wallpaper-day-night.timer"
# Rollback must retain symlinks without modifying their original targets.
cp "$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf" "$sandbox_root/original-config"
cp "$sandbox_root/original-config" "$sandbox_root/linked-config"
ln -sfn "$sandbox_root/linked-config" "$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"
rc=0
FAIL_TIMER=1 "$ctl" configure schedule 04:00 07:00 17:00 22:00 --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 9 ]]
test -L "$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"
cmp "$sandbox_root/original-config" "$sandbox_root/linked-config"
rm "$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"
cp "$sandbox_root/original-config" "$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"
# Legitimate quoted/time assignments remain compatible and never execute text.
cat >"$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf" <<'CONFIG'
# Existing hand-edited config.
dawn = "05:30"
day='08:00' # Morning
dusk=18:30
night=21:00
CONFIG
"$ctl" status --json | jq -e '.ok and .state.schedule.dawn == "05:30" and .state.schedule.day == "08:00"' >/dev/null
# shellcheck disable=SC2016 # Literal malicious config must never execute.
printf 'dawn=$(touch "%s")\n' "$sandbox_root/should-not-exist" >"$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"
reject STATE_UNAVAILABLE status --json
test ! -e "$sandbox_root/should-not-exist"
jq -e '.state.schedule.dawn == null and .state.motion.configured == "off"' "$sandbox_root/result.json" >/dev/null
cp "$sandbox_root/original-config" "$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"
# Missing assets remain visible but cannot be applied; no owner call is made.
cat >"$sandbox_root/manifest.toml" <<'MANIFEST'
[[wallpapers]]
id = "absent-image"
path = "backgrounds/does-not-exist.png"
MANIFEST
ARANEA_WALLPAPER_MANIFEST="$sandbox_root/manifest.toml" "$ctl" status --json | jq -e '.state.wallpapers[0].id == "absent-image" and .state.wallpapers[0].label == "Absent image" and .state.wallpapers[0].available == false' >/dev/null
cp "$sandbox_root/applier.log" "$sandbox_root/applier-before"
ARANEA_WALLPAPER_MANIFEST="$sandbox_root/manifest.toml" reject ASSET_UNAVAILABLE set wallpaper absent-image --json
cmp "$sandbox_root/applier-before" "$sandbox_root/applier.log"
# Read failure in an observation never erases the configured preference.
FAIL_READ=1 "$ctl" status --json | jq -e '.state.motion.configured == "off" and .state.motion.applied == null and .state.motion.application == "unavailable"' >/dev/null
# Disabling removes units before reload and reads actual inactive timer state.
EXPECT_REMOVED=1 "$ctl" set schedule off --json | jq -e '.ok and .state.schedule.enabled == false and .state.schedule.applied == false' >/dev/null
test ! -e "$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.timer"
# Broken preference symlinks are unavailable, not defaulted silently.
rm "$ARANEA_STATE_ROOT/motion"
ln -s "$sandbox_root/not-present" "$ARANEA_STATE_ROOT/motion"
reject STATE_UNAVAILABLE status --json
jq -e '.state.motion.configured == null' "$sandbox_root/result.json" >/dev/null
rm "$ARANEA_STATE_ROOT/motion"
printf off >"$ARANEA_STATE_ROOT/motion"
# Integration operations use the real ownership ledger and their JSONL status.
"$ctl" set integration session active --json | jq -e '.ok and any(.state.integrations[]; .id == "session" and .status == "active")' >/dev/null
test -L "$XDG_CONFIG_HOME/omarchy/session/aranea.css"
"$ctl" set integration session inactive --json | jq -e '.ok and any(.state.integrations[]; .id == "session" and .status == "inactive")' >/dev/null
test ! -e "$XDG_CONFIG_HOME/omarchy/session/aranea.css"
# A registry read failure must not masquerade as an available empty catalog.
registry_bin="$(mktemp -d)"
ARANEA_REAL_AWK="$(command -v awk)"
export ARANEA_REAL_AWK
cat >"$registry_bin/awk" <<'STUB'
#!/usr/bin/env bash
set -eu
for argument in "$@"; do
  if [[ "$argument" == */theme-manifest.toml ]]; then
    if [[ "${REGISTRY_MODE:-}" == fail ]]; then echo 'registry read rejected' >&2; exit 24; fi
    if [[ "${REGISTRY_MODE:-}" == empty ]]; then
      argv=("$@")
      argv[$(($# - 1))]="$ARANEA_TEST_SANDBOX/empty-registry.toml"
      exec "$ARANEA_REAL_AWK" "${argv[@]}"
    fi
  fi
done
exec "$ARANEA_REAL_AWK" "$@"
STUB
chmod +x "$registry_bin/awk"
rc=0
PATH="$registry_bin:$PATH" REGISTRY_MODE=fail "$repo_root/scripts/aranea-integrations" status --json >"$sandbox_root/owner-status" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 24 ]]
rc=0
PATH="$registry_bin:$PATH" REGISTRY_MODE=fail "$ctl" status --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 1 ]]
jq -e '.ok == false and .error.code == "STATE_UNAVAILABLE" and .state.integrations == [] and .state.integrationsAvailability == "unavailable" and .state.motion.configured == "off" and .state.schedule.dawn == "05:30"' "$sandbox_root/result.json" >/dev/null
grep -Fq 'registry read rejected' "$sandbox_root/error"
# A successfully read registry containing no IDs remains a valid empty catalog.
printf '# A valid empty integration registry.\n' >"$sandbox_root/empty-registry.toml"
PATH="$registry_bin:$PATH" REGISTRY_MODE=empty "$ctl" status --json | jq -e '.ok and .state.integrations == [] and .state.integrationsAvailability == "available"' >/dev/null
# Custom fractions delegate exact argv; silent owner failures need live evidence.
export ARANEA_DISPLAY_OWNER="$sandbox_root/display-owner"
mkdir -p "$HOME/.config/hypr"
printf 'local omarchy_monitor_scale = 2\nlocal omarchy_gdk_scale = 2\n' >"$HOME/.config/hypr/monitors.lua"
# Restore the sandbox focused-display observation for each isolated case.
reset_display() {
  printf '[{"name":"eDP-1","focused":true,"scale":2,"width":3840,"height":2160}]\n' >"$sandbox_root/monitors.json"
}
reset_display
cat >"$ARANEA_DISPLAY_OWNER" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >"$ARANEA_TEST_SANDBOX/display-argv"
[[ "$1 $2 $3" == 'hyprland monitor scaling' && $# == 4 ]] || exit 13
[[ "${SCALE_MODE:-}" != fail ]] || { echo 'scale owner failed' >&2; exit 19; }
scale="$4"
[[ "$scale" != 2.667 ]] || scale=2.666667
[[ "${SCALE_MODE:-}" != wrong ]] || scale=3
if [[ "${SCALE_MODE:-}" != silent ]]; then
  jq --argjson scale "$scale" '.[0].scale = $scale' "$ARANEA_TEST_SANDBOX/monitors.json" >"$ARANEA_TEST_SANDBOX/next.json"
  mv "$ARANEA_TEST_SANDBOX/next.json" "$ARANEA_TEST_SANDBOX/monitors.json"
fi
if [[ "${SCALE_MODE:-}" == focus ]]; then
  jq '.[0].focused = false | . + [{name:"DP-1",focused:true,scale:3.5,width:3840,height:2160}]' "$ARANEA_TEST_SANDBOX/monitors.json" >"$ARANEA_TEST_SANDBOX/next.json"
  mv "$ARANEA_TEST_SANDBOX/next.json" "$ARANEA_TEST_SANDBOX/monitors.json"
fi
if [[ "${SCALE_MODE:-}" != persistfail ]]; then
  sed -i -E "s/^local omarchy_monitor_scale = .*/local omarchy_monitor_scale = $scale/" "$HOME/.config/hypr/monitors.lua"
fi
[[ "${SCALE_MODE:-}" != lost ]] || touch "$ARANEA_TEST_SANDBOX/lost-display"
echo 'Scaling applied successfully'
STUB
chmod +x "$ARANEA_DISPLAY_OWNER"
"$ctl" status --json | jq -e '.state.display.monitor == "eDP-1" and .state.display.scale == 2 and .state.display.persistenceSupport == "supported" and .state.display.availability == "available"' >/dev/null
for scale in 2.5 2.667; do
  reset_display
  "$ctl" set display-scale "$scale" --monitor eDP-1 --json >"$sandbox_root/result.json"
  printf 'hyprland\nmonitor\nscaling\n%s\n' "$scale" >"$sandbox_root/expected-argv"
  cmp "$sandbox_root/expected-argv" "$sandbox_root/display-argv"
  jq -e --arg scale "$scale" '.ok and .result.displayScale.requested == $scale and .result.displayScale.confirmed and .result.displayScale.persistence == "persisted" and .result.displayScale.monitor == "eDP-1" and ((.result.displayScale.expectedScale - .state.display.scale) | fabs) < 0.00001' "$sandbox_root/result.json" >/dev/null
done
cp "$sandbox_root/display-argv" "$sandbox_root/argv-before"
for scale in 0 4.1 2e0 '2;touch /tmp/scale-injection' nan -2 '' ' 2.5'; do
  reject INVALID_ARGUMENTS set display-scale "$scale" --json
  cmp "$sandbox_root/argv-before" "$sandbox_root/display-argv"
done
reject INVALID_ARGUMENTS set display-scale 2.5 --monitor 'hostile"' --json
reset_display
reject FOCUS_CHANGED set display-scale 2.5 --monitor DP-1 --json
cmp "$sandbox_root/argv-before" "$sandbox_root/display-argv"
# Missing executable, malformed observations, multiple focus and unsafe connectors
# cannot invoke an owner, even if other settings remain readable.
for observation in 'invalid' '[]' '[{"name":"unsafe\\\"","focused":true,"scale":2,"width":3840,"height":2160}]' '[{"name":"eDP-1","focused":true,"scale":2,"width":3840,"height":2160},{"name":"DP-1","focused":true,"scale":2,"width":3840,"height":2160}]'; do
  printf '%s\n' "$observation" >"$sandbox_root/monitors.json"
  reject STATE_UNAVAILABLE set display-scale 2.5 --json
  cmp "$sandbox_root/argv-before" "$sandbox_root/display-argv"
done
ARANEA_HYPRCTL="$sandbox_root/missing-compositor" reject STATE_UNAVAILABLE set display-scale 2.5 --json
reset_display
rm -f "$sandbox_root/display-reads"
FOCUS_BEFORE_DISPATCH=1 reject FOCUS_CHANGED set display-scale 2.5 --monitor eDP-1 --json
jq -e '.state.display.monitor == "DP-1"' "$sandbox_root/result.json" >/dev/null
cmp "$sandbox_root/argv-before" "$sandbox_root/display-argv"
reset_display
SCALE_MODE=lost reject APPLICATION_NOT_CONFIRMED set display-scale 2.5 --json
jq -e '.result.displayScale.confirmed == false and .result.displayScale.effectiveScale == null' "$sandbox_root/result.json" >/dev/null
rm "$sandbox_root/lost-display"
for mode in silent wrong focus; do
  reset_display
  code=APPLICATION_NOT_CONFIRMED
  [[ "$mode" != focus ]] || code=FOCUS_CHANGED
  SCALE_MODE="$mode" reject "$code" set display-scale 2.5 --json
  jq -e '.result.displayScale.confirmed == false' "$sandbox_root/result.json" >/dev/null
  if [[ "$mode" == focus ]]; then jq -e '.result.displayScale.effectiveScale == 2.5 and .state.display.scale == 3.5' "$sandbox_root/result.json" >/dev/null; fi
done
reset_display
rc=0
SCALE_MODE=fail "$ctl" set display-scale 2.5 --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ "$rc" == 19 ]]
jq -e '.error.code == "HELPER_FAILED" and .state.display.scale == 2' "$sandbox_root/result.json" >/dev/null
reset_display
printf 'local omarchy_monitor_scale = 2\n' >"$HOME/.config/hypr/monitors.lua"
SCALE_MODE=persistfail "$ctl" set display-scale 2.5 --json | jq -e '.ok and .result.displayScale.persistence == "unconfirmed"' >/dev/null
printf 'hl.monitor({ output = "DP-1", scale = 2 })\n' >"$HOME/.config/hypr/monitors.lua"
reset_display
"$ctl" set display-scale 2.667 --json | jq -e '.ok and .state.display.persistenceSupport == "unsupported" and .result.displayScale.persistence == "session-only"' >/dev/null
# Owner-recognized generic config retains saving support with trailing Lua comments.
for generic in 'local omarchy_monitor_scale = 2 -- standard Lua comment' 'local omarchy_monitor_scale = 2.667  -- custom fraction' 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 }) -- standard Lua comment'; do
  printf '%s\n' "$generic" >"$HOME/.config/hypr/monitors.lua"
  literal=2
  [[ "$generic" != *2.667* ]] || literal=2.667
  "$ctl" status --json | jq -e --argjson literal "$literal" '.state.display.persistenceSupport == "supported" and .state.display.configuredScale == $literal' >/dev/null || {
    echo 'commented generic config must remain save-capable with its literal scale' >&2
    exit 1
  }
done
# Recognized saving support does not permit guessing or evaluating arbitrary Lua.
printf 'local omarchy_monitor_scale = 2 + 1\n' >"$HOME/.config/hypr/monitors.lua"
"$ctl" status --json | jq -e '.state.display.persistenceSupport == "supported" and .state.display.configuredScale == null' >/dev/null
printf 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 }) ; os.execute("touch %s")\n' "$sandbox_root/lua-executed" >"$HOME/.config/hypr/monitors.lua"
"$ctl" status --json | jq -e '.state.display.persistenceSupport == "supported" and .state.display.configuredScale == null' >/dev/null
printf 'hl.monitor({ output = "DP-1", scale = 2 }) -- custom monitor rule\n' >"$HOME/.config/hypr/monitors.lua"
"$ctl" status --json | jq -e '.state.display.persistenceSupport == "unsupported" and .state.display.configuredScale == null' >/dev/null
# Nonliteral Lua is never interpreted or executed by the adapter.
printf 'local omarchy_monitor_scale = os.execute("touch %s")\n' "$sandbox_root/lua-executed" >"$HOME/.config/hypr/monitors.lua"
"$ctl" status --json | jq -e '.state.display.persistenceSupport == "supported" and .state.display.configuredScale == null' >/dev/null
test ! -e "$sandbox_root/lua-executed"
printf 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })\n' >"$HOME/.config/hypr/monitors.lua"
"$ctl" status --json | jq -e '.state.display.persistenceSupport == "supported" and .state.display.configuredScale == null' >/dev/null
# Changed config must reload and validate, even when the owner swallowed errors.
printf 'local omarchy_monitor_scale = 2\n' >"$HOME/.config/hypr/monitors.lua"
reset_display
FAIL_DISPLAY_CONFIG=1 reject CONFIG_VALIDATION_FAILED set display-scale 2.5 --json
printf 'local omarchy_monitor_scale = 2\n' >"$HOME/.config/hypr/monitors.lua"
reset_display
FAIL_DISPLAY_RELOAD=1 reject CONFIG_VALIDATION_FAILED set display-scale 2.5 --json
ARANEA_DISPLAY_OWNER="$sandbox_root/missing-owner" reject STATE_UNAVAILABLE set display-scale 2.5 --json
FAIL_DISPLAY_READ=1 reject STATE_UNAVAILABLE set display-scale 2.5 --json
ARANEA_DISPLAY_OWNER="$sandbox_root/missing-owner" "$ctl" status --json | jq -e '.ok and .state.display.availability == "unavailable" and .state.motion.availability == "available"' >/dev/null
# Unreadable/corrupt preferences produce partial state, never a guessed value.
printf corrupt >"$ARANEA_STATE_ROOT/motion"
reject STATE_UNAVAILABLE status --json
jq -e '.state.motion.configured == null and .state.schedule.dawn == "05:30" and (.state.integrations | length > 0)' "$sandbox_root/result.json" >/dev/null
# Missing jq cannot mutate anything; dependency result is still valid JSON.
nojq_bin="$(mktemp -d)"
for tool in bash dirname; do ln -s "$(command -v "$tool")" "$nojq_bin/$tool"; done
rc=0
PATH="$nojq_bin" "$ctl" set motion on --json >"$sandbox_root/result.json" 2>"$sandbox_root/error" || rc=$?
[[ $rc == 2 ]]
jq -e '.ok == false and .error.code == "DEPENDENCY_MISSING"' "$sandbox_root/result.json" >/dev/null
[[ "$(cat "$ARANEA_STATE_ROOT/motion")" == corrupt ]]
echo 'settings contract passed'
