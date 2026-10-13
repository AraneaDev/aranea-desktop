#!/usr/bin/env bash
# Flexible schedule adapter validates before mutation and confirms owner readback.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
export ARANEA_SYSTEMCTL="$ARANEA_TEST_SANDBOX/systemctl"
export ARANEA_HYPRCTL="$ARANEA_TEST_SANDBOX/hyprctl"
export ARANEA_STATE_ROOT="$XDG_STATE_HOME/aranea"
export ARANEA_SYSTEMD_USER_DIR="$XDG_CONFIG_HOME/systemd/user"
cat >"$ARANEA_SYSTEMCTL" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ARANEA_TEST_SANDBOX/timer-calls"
if [[ "$*" == *is-active* ]]; then echo inactive; exit 3; fi
exit 0
SH
cat >"$ARANEA_HYPRCTL" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == '-j getoption animations:enabled' ]]; then echo '{"int":1}'; else echo '[]'; fi
SH
chmod +x "$ARANEA_SYSTEMCTL" "$ARANEA_HYPRCTL"
ctl="$repo_root/scripts/aranea-settings"
entries='[{"time":"21:15","wallpaper":"signal-shrine"},{"time":"07:30","wallpaper":"day"},{"time":"13:00","wallpaper":"deep-current"},{"time":"17:45","wallpaper":"violet-pursuit"},{"time":"10:00","wallpaper":"aranea-core"}]'
"$ctl" configure schedule --entries "$entries" --json >"$ARANEA_TEST_SANDBOX/result"
jq -e '.ok and .state.schedule.enabled == false and (.state.schedule.entries|length)==5 and .state.schedule.entries[0]=={time:"07:30",wallpaper:"day"} and .state.schedule.entries[-1]=={time:"21:15",wallpaper:"signal-shrine"}' "$ARANEA_TEST_SANDBOX/result" >/dev/null
config="$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"
cp "$config" "$ARANEA_TEST_SANDBOX/saved"
# Invalid drafts preserve both the saved list and disabled timer state.
for draft in '[{"time":"09:00","wallpaper":"day"}] [{"time":"10:00","wallpaper":"day"}]' '[]' 'null' '[{"time":"07:30","wallpaper":"day"},{"time":"07:30","wallpaper":"night"}]' '[{"time":"25:00","wallpaper":"day"}]' '[{"time":"09:00"}]'; do
  rc=0
  "$ctl" configure schedule --entries "$draft" --json >"$ARANEA_TEST_SANDBOX/result" || rc=$?
  [[ "$rc" == 2 ]]
  jq -e '.ok == false and .error.code == "INVALID_SCHEDULE"' "$ARANEA_TEST_SANDBOX/result" >/dev/null
  cmp -s "$config" "$ARANEA_TEST_SANDBOX/saved"
done
rc=0
"$ctl" configure schedule --entries '[{"time":"09:00","wallpaper":"unknown"}]' --json >"$ARANEA_TEST_SANDBOX/result" || rc=$?
[[ "$rc" == 2 ]]
jq -e '.error.code == "UNKNOWN_ID"' "$ARANEA_TEST_SANDBOX/result" >/dev/null
cmp -s "$config" "$ARANEA_TEST_SANDBOX/saved"
# One entry is a valid daily schedule and saving does not activate the timer.
"$ctl" configure schedule --entries '[{"time":"00:00","wallpaper":"signal-shrine"}]' --json | jq -e '.ok and (.state.schedule.entries|length)==1 and .state.schedule.enabled==false' >/dev/null
if rg -q '^--user (enable|daemon-reload|restart|start|stop|disable)( |$)' "$ARANEA_TEST_SANDBOX/timer-calls"; then
  echo 'Saving a disabled schedule changed the timer' >&2
  exit 1
fi
echo 'flexible schedule settings adapter passed'
