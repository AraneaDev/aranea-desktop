#!/usr/bin/env bash
# Desktop font projection follows logical body pixels without double text scaling.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
ctl="$repo_root/scripts/aranea-sync-desktop-font"
export ARANEA_OWNERSHIP_ROOT="$ARANEA_TEST_SANDBOX/ownership"
mkdir -p "$XDG_STATE_HOME/omarchy/current"
printf aranea >"$XDG_STATE_HOME/omarchy/current/theme.name"
cat >"$ARANEA_TEST_SANDBOX/gsettings" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
file="$ARANEA_TEST_SANDBOX/$3"
case "$1" in
 get) cat "$file" ;;
 set) printf '%s\n' "$4" >"$file"; printf '%s\n' "$*" >>"$ARANEA_TEST_SANDBOX/writes" ;;
 *) exit 2 ;;
esac
STUB
chmod +x "$ARANEA_TEST_SANDBOX/gsettings"
export PATH="$ARANEA_TEST_SANDBOX:$PATH"
printf "'Adwaita Sans 11'\n" >"$ARANEA_TEST_SANDBOX/font-name"
printf '0.9091\n' >"$ARANEA_TEST_SANDBOX/text-scaling-factor"
"$ctl" 'Inter' 12
[[ $(cat "$ARANEA_TEST_SANDBOX/font-name") == "'Inter 9'" ]]
[[ $(cat "$ARANEA_TEST_SANDBOX/text-scaling-factor") == 1.0 ]]
"$ctl" 'Source Sans 3' 17
[[ $(cat "$ARANEA_TEST_SANDBOX/font-name") == "'Source Sans 3 12.75'" ]]
[[ $(cat "$ARANEA_OWNERSHIP_ROOT/gsettings/org.gnome.desktop.interface.font-name") == "'Adwaita Sans 11'" ]]
[[ $(cat "$ARANEA_OWNERSHIP_ROOT/gsettings/org.gnome.desktop.interface.text-scaling-factor") == 0.9091 ]]
count=$(wc -l <"$ARANEA_TEST_SANDBOX/writes")
"$ctl" 'Source Sans 3' 17
[[ $(wc -l <"$ARANEA_TEST_SANDBOX/writes") == "$count" ]]
printf '1.3333\n' >"$ARANEA_TEST_SANDBOX/text-scaling-factor"
"$ctl" 'Source Sans 3' 17
[[ $(cat "$ARANEA_TEST_SANDBOX/text-scaling-factor") == 1.0 ]]
count=$(wc -l <"$ARANEA_TEST_SANDBOX/writes")
for bad in 0 -1 NaN '12; echo bad'; do
  if "$ctl" Inter "$bad"; then exit 1; fi
done
if "$ctl" $'Inter\nBad' 12; then exit 1; fi
printf tokyo-night >"$XDG_STATE_HOME/omarchy/current/theme.name"
"$ctl" Inter 20
[[ $(wc -l <"$ARANEA_TEST_SANDBOX/writes") == "$count" ]]
printf aranea >"$XDG_STATE_HOME/omarchy/current/theme.name"
"$ctl" --restore
[[ $(cat "$ARANEA_TEST_SANDBOX/font-name") == "'Adwaita Sans 11'" ]]
[[ $(cat "$ARANEA_TEST_SANDBOX/text-scaling-factor") == 0.9091 ]]
# Theme deactivation preserves a subsequent independent desktop font edit.
"$ctl" Inter 14
printf "'User Font 18'\n" >"$ARANEA_TEST_SANDBOX/font-name"
"$ctl" --restore
[[ $(cat "$ARANEA_TEST_SANDBOX/font-name") == "'User Font 18'" ]]
