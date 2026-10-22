#!/usr/bin/env bash
# Normal Settings captures require acknowledged inert fixtures and restore UI/focus on every exit.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
bin="$ARANEA_TEST_SANDBOX/bin"
out="$ARANEA_TEST_SANDBOX/shots"
log="$ARANEA_TEST_SANDBOX/calls"
mkdir -p "$bin" "$out"
cat >"$bin/omarchy-shell" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls"
snapshot='{"opened":true,"section":"schedule","ui":{"scheduleDraft":[{"time":"07:00","wallpaper":"day"}]},"showcase":true}'
ready='{"ready":true,"readOnly":true}'
case "$2" in
  captureSnapshot) echo "${CAPTURE_SETTINGS_SNAPSHOT-$snapshot}" ;;
  captureBegin) echo "${CAPTURE_SETTINGS_ANSWER-ok}" ;;
  captureState)
    if [[ -n "${CAPTURE_SETTINGS_READY_AFTER:-}" ]]; then
      count=$(cat "$ARANEA_TEST_SANDBOX/ready-count" 2>/dev/null || echo 0)
      count=$((count + 1))
      echo "$count" >"$ARANEA_TEST_SANDBOX/ready-count"
      if ((count < CAPTURE_SETTINGS_READY_AFTER)); then ready='{"ready":false,"readOnly":true}'; fi
    fi
    echo "${CAPTURE_SETTINGS_READY-$ready}"
    ;;
  captureRestore) echo "${CAPTURE_SETTINGS_RESTORE-ok}" ;;
esac
STUB
cat >"$bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls"
case "$1" in
  dispatch) [[ "$2" != focuswindow ]] || exit 7 ;;
  activeworkspace)
    workspace='{"id":7}'
    echo "${CAPTURE_WORKSPACE_JSON-$workspace}"
    exit "${CAPTURE_WORKSPACE_STATUS:-0}"
    ;;
  activewindow)
    focus='{"address":"0xabc"}'
    echo "${CAPTURE_FOCUS_JSON-$focus}"
    exit "${CAPTURE_FOCUS_STATUS:-0}"
    ;;
esac
STUB
cat >"$bin/grim" <<'STUB'
#!/usr/bin/env bash
printf 'grim\n' >>"$ARANEA_TEST_SANDBOX/calls"
[[ "${CAPTURE_GRIM_FAIL:-0}" != 1 ]] || exit 1
printf frame >"${@: -1}"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/sleep"
chmod +x "$bin"/*
export PATH="$bin:$PATH"
capture="$repo_root/scripts/capture-screenshots"
# Failed compositor commands and malformed snapshots must refuse before accepting fixtures.
printf old >"$out/settings.png"
for failure in workspace-command focus-command; do
  : >"$log"
  rc=0
  case "$failure" in
    workspace-command) CAPTURE_WORKSPACE_STATUS=1 "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$? ;;
    focus-command) CAPTURE_FOCUS_STATUS=1 "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$? ;;
  esac
  [[ "$rc" == 3 && "$(cat "$out/settings.png")" == old ]]
  if grep -Eq 'captureBegin|captureRestore|dispatch|^grim$' "$log"; then exit 1; fi
done
for response in '' invalid '[]' null '{}' '{"id":null}' '{"id":"7"}' '{"id":0}' '{"id":-1}' '{"id":7.5}' $'{"id":7}\n{"id":8}'; do
  : >"$log"
  rc=0
  CAPTURE_WORKSPACE_JSON="$response" "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 3 && "$(cat "$out/settings.png")" == old ]]
  if grep -Eq 'captureBegin|captureRestore|dispatch|^grim$' "$log"; then exit 1; fi
done
for response in '' invalid '[]' null '{"address":null}' '{"address":42}' '{"address":""}' '{"address":"not-an-address"}' '{"title":"missing-address"}' $'{}\n{}'; do
  : >"$log"
  rc=0
  CAPTURE_FOCUS_JSON="$response" "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 3 && "$(cat "$out/settings.png")" == old ]]
  if grep -Eq 'captureBegin|captureRestore|dispatch|^grim$' "$log"; then exit 1; fi
done
# A successfully read empty activewindow object is a legitimate unfocused desktop.
: >"$log"
CAPTURE_FOCUS_JSON='{}' "$capture" --surface settings --output "$out" >/dev/null
[[ "$(cat "$out/settings.png")" == frame ]]
grep -Fq captureRestore "$log"
grep -Fq 'workspace = "7"' "$log"
if grep -Fq 'window = ' "$log"; then exit 1; fi
rm "$out/settings.png"
for answer in busy invalid 'Function not found.' ''; do
  : >"$log"
  rc=0
  CAPTURE_SETTINGS_ANSWER="$answer" "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 3 && ! -e "$out/settings.png" ]]
  if grep -Eq 'grim|captureRestore|dispatch' "$log"; then exit 1; fi
done
for surface in settings settings-scaling settings-screensavers; do
  : >"$log"
  "$capture" --surface "$surface" --output "$out" >/dev/null
  [[ -f "$out/$surface.png" ]]
  [[ "$(grep -n captureSnapshot "$log" | cut -d: -f1)" -lt "$(grep -n captureBegin "$log" | cut -d: -f1)" ]]
  [[ "$(grep -n captureState "$log" | head -1 | cut -d: -f1)" -lt "$(grep -n '^grim$' "$log" | cut -d: -f1)" ]]
  [[ "$(grep -n '^grim$' "$log" | cut -d: -f1)" -lt "$(grep -n captureRestore "$log" | cut -d: -f1)" ]]
  grep -Fq 'captureRestore {"opened":true,"section":"schedule","ui":{"scheduleDraft":[{"time":"07:00","wallpaper":"day"}]},"showcase":true}' "$log"
  grep -Fq 'workspace = "7"' "$log"
  grep -Fq 'window = "address:0xabc"' "$log"
  if grep -Eq 'aranea-settings.*close| set | refresh| summon' "$log"; then exit 1; fi
  rm "$out/$surface.png"
done
for ready in '{"ready":true,"readOnly":false}' invalid; do
  : >"$log"
  rc=0
  CAPTURE_SETTINGS_READY="$ready" "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 3 && ! -e "$out/settings.png" ]]
  if grep -Fxq grim "$log"; then exit 1; fi
  grep -Fq captureRestore "$log"
  grep -Fq 'workspace = "7"' "$log"
  grep -Fq 'window = "address:0xabc"' "$log"
done
: >"$log"
printf old >"$out/settings.png"
rc=0
CAPTURE_GRIM_FAIL=1 "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 3 && "$(cat "$out/settings.png")" == old ]]
grep -Fq captureRestore "$log"
grep -Fq 'workspace = "7"' "$log"
grep -Fq 'window = "address:0xabc"' "$log"
for failure in snapshot restore timeout; do
  : >"$log"
  rc=0
  case "$failure" in
    snapshot) CAPTURE_SETTINGS_SNAPSHOT=invalid "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$? ;;
    restore) CAPTURE_SETTINGS_RESTORE=invalid "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$? ;;
    timeout) CAPTURE_SETTINGS_READY='{"ready":false,"readOnly":true}' "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$? ;;
  esac
  [[ "$rc" == 3 && "$(cat "$out/settings.png")" == old ]]
  [[ "$failure" == restore ]] || ! grep -Fxq grim "$log"
  if [[ "$failure" != snapshot ]]; then
    grep -Fq captureRestore "$log"
    grep -Fq 'workspace = "7"' "$log"
    grep -Fq 'window = "address:0xabc"' "$log"
  fi
done
# Schedule uses the same guarded production window with entry-based fixtures.
: >"$log"
"$capture" --surface settings-schedule --output "$out" >/dev/null
test -f "$out/settings-schedule.png"
grep -Fq '"section":"schedule"' "$log"
grep -Fq '"wallpaper":"silken-vault"' "$log"
grep -Fq captureRestore "$log"
# A cold expanded artwork catalog can take longer than the first 30 polls.
CAPTURE_SETTINGS_READY_AFTER=40 "$capture" --surface settings-schedule --output "$out" >/dev/null
[[ "$(cat "$ARANEA_TEST_SANDBOX/ready-count")" == 40 ]]
# Screensavers uses production Settings with inert catalog/timing, never a live owner read.
: >"$log"
"$capture" --surface settings-screensavers --output "$out" >/dev/null
[[ "$(cat "$out/settings-screensavers.png")" == frame ]]
payload="$(sed -n 's/^aranea.settings.capture captureBegin //p' "$log")"
jq -e --arg root "$repo_root" '
  .fixture.state.screensaver as $s |
  .section == "screensavers" and
  $s.availability == "available" and $s.catalogAvailable == true and
  $s.selectedId == "silk-journey" and $s.mode == "single" and
  $s.idle == {screensaverSeconds:900,lockSeconds:1200,stayAwake:false,screensaverOff:false,error:null} and
  $s.session.running == false and $s.session.ready == false and
  [$s.choices[].id] == ["silk-journey","neon-weaver","spiderfall","kanji-drift","silken-flow","neon-depths"] and
  [$s.choices[].available] == [true,true,true,true,true,true] and
  [$s.choices[].shuffleEligible] == [true,true,true,true,true,true] and
  [$s.choices[].thumbnail] == [$root + "/branding/3d/live/preview.png",$root + "/branding/3d/collection/spider/neon-weaver.png",$root + "/branding/3d/collection/spider/spiderfall.png",$root + "/branding/3d/collection/ambient/kanji-drift.png",$root + "/branding/3d/collection/ambient/silken-flow.png",$root + "/branding/3d/collection/ambient/neon-depths.png"]
' <<<"$payload" >/dev/null
if grep -Eq '^(aranea-screensaver |aranea.settings (configure|preview)|shell reloadConfig|idle )' "$log"; then exit 1; fi
# A failed Screensavers transaction retains its prior PNG and restores the snapshot.
for failure in readiness restore; do
  : >"$log"
  printf previous >"$out/settings-screensavers.png"
  rc=0
  case "$failure" in
    readiness) CAPTURE_SETTINGS_READY='{"ready":true,"readOnly":false}' "$capture" --surface settings-screensavers --output "$out" >/dev/null 2>&1 || rc=$? ;;
    restore) CAPTURE_SETTINGS_RESTORE=invalid "$capture" --surface settings-screensavers --output "$out" >/dev/null 2>&1 || rc=$? ;;
  esac
  [[ "$rc" == 3 && "$(cat "$out/settings-screensavers.png")" == previous ]]
  grep -Fq captureRestore "$log"
  grep -Fq 'window = "address:0xabc"' "$log"
done
echo 'Settings capture contract passed'
