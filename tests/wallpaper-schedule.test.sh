#!/usr/bin/env bash
# Daily schedules support arbitrary manifest-backed entries and safe migration.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/state"
export ARANEA_SYSTEMD_USER_DIR="$ARANEA_TEST_SANDBOX/units"
export ARANEA_WALLPAPER_DRY_RUN=1
export ARANEA_SYSTEMCTL=/bin/true
ctl="$repo_root/scripts/aranea-wallpaper"
config="$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"
# Asserts the command's output holds LINE. The output is captured first: with
# pipefail, `cmd | grep -q` fails with 141 whenever grep exits on the
# "wallpaper:" line before the command has written its "path:" line.
expect_output() {
  local line="$1" out
  shift
  out="$("$@")"
  grep -Fq -- "$line" <<<"$out"
}
entries='[{"time":"21:30","wallpaper":"monochrome"},{"time":"09:15","wallpaper":"day"},{"time":"06:00","wallpaper":"dawn"}]'
"$ctl" schedule configure --entries "$entries" >/dev/null
jq -e '.version == 2 and (.entries | length == 3) and .entries[0].time == "06:00" and .entries[2].wallpaper == "monochrome"' "$config" >/dev/null
"$ctl" schedule status --json | jq -e '.enabled == false and .entries[1].wallpaper == "day" and .dawn == "06:00" and .night == null' >/dev/null
for now in 00:00 05:59 21:30 23:59; do
  ARANEA_NOW="$now" expect_output 'wallpaper: monochrome' "$ctl" set-scheduled
done
ARANEA_NOW=06:00 expect_output 'wallpaper: dawn' "$ctl" set-phase
ARANEA_NOW=10:00 expect_output 'wallpaper: day' "$ctl" set-day-night
# Save while disabled never enables scheduling or writes timer units.
test ! -e "$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.timer"
"$ctl" schedule on >/dev/null
"$ctl" schedule configure --entries '[{"time":"03:00","wallpaper":"night"}]' >/dev/null
[[ "$(cat "$ARANEA_STATE_ROOT/wallpaper-schedule")" == on ]]
[[ "$(rg -c '^OnCalendar=' "$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.timer")" == 1 ]]
rg -q 'set-scheduled$' "$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.service"
ARANEA_NOW=02:59 expect_output 'wallpaper: night' "$ctl" set-scheduled
# No artificial count cap: every minute may contain one transition.
many="$(jq -cn '[range(0;1440) | {time:((./60|floor|tostring|if length == 1 then "0"+. else . end)+":"+(.%60|tostring|if length == 1 then "0"+. else . end)),wallpaper:"day"}]')"
"$ctl" schedule configure --entries "$many" >/dev/null
[[ "$(rg -c '^OnCalendar=' "$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.timer")" == 1440 ]]
cp "$config" "$ARANEA_TEST_SANDBOX/before"
# Reject invalid entries and confirm the saved configuration is unchanged.
reject() {
  if "$ctl" schedule configure --entries "$1" >"$ARANEA_TEST_SANDBOX/out" 2>"$ARANEA_TEST_SANDBOX/error"; then
    echo "unexpected valid schedule: $1" >&2
    exit 1
  fi
  cmp "$config" "$ARANEA_TEST_SANDBOX/before"
}
for invalid in '[]' '{}' 'null' 'garbage' '[] []' '[{"time":"25:00","wallpaper":"day"}]' '[{"time":"6:00","wallpaper":"day"}]' '[{"time":"06:00","wallpaper":"day"},{"time":"06:00","wallpaper":"night"}]' '[{"time":"06:00","wallpaper":"unknown"}]' '[{"time":"06:00"}]' '[{"time":null,"wallpaper":"day"}]'; do reject "$invalid"; done
# A known ID with a missing asset is also rejected before any writes.
cat >"$ARANEA_TEST_SANDBOX/manifest.toml" <<'MANIFEST'
[[wallpapers]]
id = "missing"
path = "backgrounds/absent.png"
MANIFEST
ARANEA_WALLPAPER_MANIFEST="$ARANEA_TEST_SANDBOX/manifest.toml" reject '[{"time":"06:00","wallpaper":"missing"}]'
# Two entries may reuse one image; ambiguous legacy fields remain null.
"$ctl" schedule configure --entries '[{"time":"20:00","wallpaper":"day"},{"time":"08:00","wallpaper":"day"}]' >/dev/null
"$ctl" schedule status --json | jq -e '(.entries | length == 2) and .day == null' >/dev/null
# Legacy reads are safe, support defaults, and never rewrite the source.
printf '# old format\ndawn="05:30" # first\nday=08:00\ndusk=18:30\nnight=21:00\n' >"$config"
cp "$config" "$ARANEA_TEST_SANDBOX/legacy"
"$ctl" schedule status --json | jq -e '.entries[0] == {time:"05:30",wallpaper:"dawn"} and .night == "21:00"' >/dev/null
cmp "$config" "$ARANEA_TEST_SANDBOX/legacy"
"$ctl" schedule configure 05:00 08:00 18:00 22:00 >/dev/null
jq -e '.version == 2 and .entries[0].time == "05:00"' "$config" >/dev/null
# Malformed persisted sources report unavailable without executing shell.
# shellcheck disable=SC2016
for invalid in '{"version":3,"entries":[]}' '{"version":2,"entries":[]}' '{"version":2,"entries":[{"time":"08:00","wallpaper":"unknown"}]}' 'dawn=25:00' 'dawn=$(touch "'"$ARANEA_TEST_SANDBOX/should-not-exist"'")'; do
  printf '%s\n' "$invalid" >"$config"
  if "$ctl" schedule status --json >"$ARANEA_TEST_SANDBOX/status" 2>/dev/null; then exit 1; fi
  jq -e '.availability == "unavailable" and .entries == [] and .dawn == null' "$ARANEA_TEST_SANDBOX/status" >/dev/null
  if "$ctl" set-scheduled >/dev/null 2>&1; then exit 1; fi
done
test ! -e "$ARANEA_TEST_SANDBOX/should-not-exist"
# Failure restores exact symlinks and bytes, and the previous timer runtime.
"$ctl" schedule configure --entries "$entries" >/dev/null
cp "$config" "$ARANEA_TEST_SANDBOX/original-config"
cp "$config" "$ARANEA_TEST_SANDBOX/linked-config"
rm "$config"
ln -s "$ARANEA_TEST_SANDBOX/linked-config" "$config"
timer="$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.timer"
cp "$timer" "$ARANEA_TEST_SANDBOX/original-timer"
cp "$timer" "$ARANEA_TEST_SANDBOX/linked-timer"
rm "$timer"
ln -s "$ARANEA_TEST_SANDBOX/linked-timer" "$timer"
cat >"$ARANEA_TEST_SANDBOX/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls"
case "$2" in
  is-active) echo active ;;
  is-enabled) echo enabled ;;
  restart) [[ -e "$ARANEA_TEST_SANDBOX/failed-once" ]] || { touch "$ARANEA_TEST_SANDBOX/failed-once"; exit 1; } ;;
esac
SYSTEMCTL
chmod +x "$ARANEA_TEST_SANDBOX/systemctl"
export ARANEA_SYSTEMCTL="$ARANEA_TEST_SANDBOX/systemctl"
if "$ctl" schedule configure --entries '[{"time":"01:00","wallpaper":"night"}]' >/dev/null 2>&1; then exit 1; fi
test -L "$config" && test -L "$timer"
[[ "$(readlink "$config")" == "$ARANEA_TEST_SANDBOX/linked-config" ]]
cmp "$config" "$ARANEA_TEST_SANDBOX/original-config"
cmp "$ARANEA_TEST_SANDBOX/linked-config" "$ARANEA_TEST_SANDBOX/original-config"
cmp "$timer" "$ARANEA_TEST_SANDBOX/original-timer"
cmp "$ARANEA_TEST_SANDBOX/linked-timer" "$ARANEA_TEST_SANDBOX/original-timer"
[[ "$(rg -c -- '--user restart' "$ARANEA_TEST_SANDBOX/calls")" == 2 ]]
# If enable succeeds but restart fails initially, no newly enabled link remains.
export ARANEA_CONFIG_HOME="$ARANEA_TEST_SANDBOX/fresh/config"
export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/fresh/state"
export ARANEA_SYSTEMD_USER_DIR="$ARANEA_TEST_SANDBOX/fresh/units"
cat >"$ARANEA_SYSTEMCTL" <<'SYSTEMCTL'
#!/usr/bin/env bash
case "$2" in
  is-active) echo inactive; exit 3 ;;
  is-enabled) echo not-found; exit 4 ;;
  enable)
    mkdir -p "$ARANEA_SYSTEMD_USER_DIR/timers.target.wants"
    ln -s ../aranea-wallpaper-day-night.timer "$ARANEA_SYSTEMD_USER_DIR/timers.target.wants/aranea-wallpaper-day-night.timer"
    ;;
  restart) exit 1 ;;
  disable) rm -f "$ARANEA_SYSTEMD_USER_DIR/timers.target.wants/aranea-wallpaper-day-night.timer" ;;
esac
SYSTEMCTL
if "$ctl" schedule on >/dev/null 2>&1; then exit 1; fi
test ! -e "$ARANEA_CONFIG_HOME/aranea/wallpaper-schedule.conf"
test ! -e "$ARANEA_STATE_ROOT/wallpaper-schedule"
test ! -e "$ARANEA_SYSTEMD_USER_DIR/aranea-wallpaper-day-night.timer"
test ! -L "$ARANEA_SYSTEMD_USER_DIR/timers.target.wants/aranea-wallpaper-day-night.timer"
echo 'flexible wallpaper schedule contract passed'
