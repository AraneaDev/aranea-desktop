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
snapshot='{"opened":true,"section":"schedule","ui":{"draft":["07:00"]},"showcase":true}'
ready='{"ready":true,"readOnly":true}'
case "$2" in
  captureSnapshot) echo "${CAPTURE_SETTINGS_SNAPSHOT-$snapshot}" ;;
  captureBegin) echo "${CAPTURE_SETTINGS_ANSWER-ok}" ;;
  captureState) echo "${CAPTURE_SETTINGS_READY-$ready}" ;;
  captureRestore) echo "${CAPTURE_SETTINGS_RESTORE-ok}" ;;
esac
STUB
cat >"$bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls"
case "$1" in
  dispatch) [[ "$2" != focuswindow ]] || exit 7 ;;
  activeworkspace) echo '{"id":7}' ;;
  activewindow) echo '{"address":"0xabc"}' ;;
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
for answer in busy invalid 'Function not found.' ''; do
  : >"$log"
  rc=0
  CAPTURE_SETTINGS_ANSWER="$answer" "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 3 && ! -e "$out/settings.png" ]]
  if grep -Eq 'grim|captureRestore|dispatch' "$log"; then exit 1; fi
done
for surface in settings settings-scaling; do
  : >"$log"
  "$capture" --surface "$surface" --output "$out" >/dev/null
  [[ -f "$out/$surface.png" ]]
  [[ "$(grep -n captureSnapshot "$log" | cut -d: -f1)" -lt "$(grep -n captureBegin "$log" | cut -d: -f1)" ]]
  [[ "$(grep -n captureState "$log" | head -1 | cut -d: -f1)" -lt "$(grep -n '^grim$' "$log" | cut -d: -f1)" ]]
  [[ "$(grep -n '^grim$' "$log" | cut -d: -f1)" -lt "$(grep -n captureRestore "$log" | cut -d: -f1)" ]]
  grep -Fq 'captureRestore {"opened":true,"section":"schedule","ui":{"draft":["07:00"]},"showcase":true}' "$log"
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
done
: >"$log"
printf old >"$out/settings.png"
rc=0
CAPTURE_GRIM_FAIL=1 "$capture" --surface settings --output "$out" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 3 && "$(cat "$out/settings.png")" == old ]]
grep -Fq captureRestore "$log"
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
done
echo 'Settings capture contract passed'
