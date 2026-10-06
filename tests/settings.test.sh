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
if [[ "$*" == '-j getoption animations:enabled' ]]; then
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
