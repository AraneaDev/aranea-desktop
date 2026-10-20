#!/usr/bin/env bash
# Native Apps owns a separate layer. Captures must close it without opening
# a closed grid, including before Favorites/Recent/OSD and on early failure.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
capture="$repo_root/scripts/capture-screenshots"
bin="$TMPDIR/bin"
out="$TMPDIR/shots"
mkdir -p "$bin" "$out"
printf 0 >"$ARANEA_TEST_SANDBOX/grid"
printf 0 >"$ARANEA_TEST_SANDBOX/modal"
printf 0 >"$ARANEA_TEST_SANDBOX/osd"

# Model only the relevant ownership boundary: hiding Aranea Menu has no
# effect on Dock's AppGrid, and Dock's sole IPC method toggles that grid.
cat >"$bin/omarchy-shell" <<'STUB'
#!/usr/bin/env bash
printf 'shell %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls"
case "$1 $2 $3" in
  'shell hide araneadev.menu') printf 0 >"$ARANEA_TEST_SANDBOX/modal" ;;
  'shell toggle araneadev.menu' | 'shell summon araneadev.menu')
    case "$4" in
      '{"menu":"apps"}')
        current="$(cat "$ARANEA_TEST_SANDBOX/grid")"
        printf '%s' "$((1 - current))" >"$ARANEA_TEST_SANDBOX/grid"
        ;;
      *) printf 1 >"$ARANEA_TEST_SANDBOX/modal" ;;
    esac
    ;;
  'shell hide araneadev.osd') printf 0 >"$ARANEA_TEST_SANDBOX/osd" ;;
  'shell summon araneadev.osd')
    printf 1 >"$ARANEA_TEST_SANDBOX/osd"
    echo ok
    ;;
esac
if [[ "$1 $2" == 'omarchy.dock apps' && "${CAPTURE_GRID_STUCK:-0}" != 1 ]]; then
  current="$(cat "$ARANEA_TEST_SANDBOX/grid")"
  printf '%s' "$((1 - current))" >"$ARANEA_TEST_SANDBOX/grid"
fi
STUB
cat >"$bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls"
case "$*" in
  '-j layers' | 'layers -j')
    [[ "${CAPTURE_LAYER_FAIL:-0}" != 1 ]] || exit 1
    if [[ -n "${CAPTURE_LAYER_REPLY+x}" ]]; then
      printf '%s\n' "$CAPTURE_LAYER_REPLY"
      exit 0
    fi
    # A similarly named unrelated layer must never trigger the toggle.
    namespace=omarchy-dock-apps-shadow
    [[ "$(cat "$ARANEA_TEST_SANDBOX/grid")" != 1 ]] || namespace=omarchy-dock-apps
    printf '{"eDP-1":{"levels":{"2":[{"namespace":"%s"}]}}}\n' "$namespace"
    ;;
esac
STUB
cat >"$bin/grim" <<'STUB'
#!/usr/bin/env bash
printf 'grim\n' >>"$ARANEA_TEST_SANDBOX/calls"
printf 'grid=%s modal=%s osd=%s\n' \
  "$(cat "$ARANEA_TEST_SANDBOX/grid")" \
  "$(cat "$ARANEA_TEST_SANDBOX/modal")" \
  "$(cat "$ARANEA_TEST_SANDBOX/osd")" >"${@: -1}"
exit "${CAPTURE_GRIM_STATUS:-0}"
STUB
cat >"$bin/sleep" <<'STUB'
#!/usr/bin/env bash
if [[ "${CAPTURE_SLEEP_FAIL_ONCE:-0}" == 1 && ! -f "$ARANEA_TEST_SANDBOX/sleep-failed" ]]; then
  touch "$ARANEA_TEST_SANDBOX/sleep-failed"
  exit 9
fi
STUB
chmod +x "$bin"/*
export PATH="$bin:$PATH"

# Apps may show the grid in its own frame, then must release its separate
# owner before the next modal or OSD capture is opened.
"$capture" --surface apps --output "$out" >/dev/null
[[ "$(cat "$out/apps.png")" == 'grid=1 modal=0 osd=0' ]]
[[ "$(cat "$ARANEA_TEST_SANDBOX/grid")" == 0 ]] || {
  echo 'Apps capture left its native app-grid layer open' >&2
  exit 1
}
for surface in favorites recent; do
  "$capture" --surface "$surface" --output "$out" >/dev/null
  [[ "$(cat "$out/$surface.png")" == 'grid=0 modal=1 osd=0' ]]
  [[ "$(cat "$ARANEA_TEST_SANDBOX/modal")" == 0 ]]
done
"$capture" --surface osd --output "$out" >/dev/null
[[ "$(cat "$out/osd.png")" == 'grid=0 modal=0 osd=1' ]]

# Standalone captures also clear a previously open native grid. Detecting
# only an exact namespace keeps a closed grid closed on ordinary captures.
for surface in favorites recent osd; do
  printf 1 >"$ARANEA_TEST_SANDBOX/grid"
  "$capture" --surface "$surface" --output "$out" >/dev/null
  [[ "$(cat "$out/$surface.png")" == grid=0* ]]
  [[ "$(cat "$ARANEA_TEST_SANDBOX/grid")" == 0 ]]
done

# grim can report a terminal warning after writing a valid frame. Keep that
# frame only when the menu/grid cleanup also succeeds.
CAPTURE_GRIM_STATUS=9 "$capture" --surface favorites --output "$out" >/dev/null
[[ "$(cat "$out/favorites.png")" == 'grid=0 modal=1 osd=0' ]]
[[ "$(cat "$ARANEA_TEST_SANDBOX/grid")" == 0 ]]

# An early error after opening Apps must still close the native grid and
# preserve the last good screenshot, even before normal post-grab cleanup.
printf old >"$out/apps.png"
rc=0
CAPTURE_SLEEP_FAIL_ONCE=1 "$capture" --surface apps --output "$out" >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 && "$(cat "$out/apps.png")" == old ]]
[[ "$(cat "$ARANEA_TEST_SANDBOX/grid")" == 0 ]] || {
  echo 'failed Apps capture left its native app-grid layer open' >&2
  exit 1
}

# Failure to close Apps after the grab must discard the new frame too.
printf old >"$out/apps.png"
: >"$ARANEA_TEST_SANDBOX/calls"
rc=0
CAPTURE_GRID_STUCK=1 "$capture" --surface apps --output "$out" >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 && "$(cat "$out/apps.png")" == old ]]
grep -Fxq grim "$ARANEA_TEST_SANDBOX/calls"

# A toggle that did not dismiss the layer cannot authorize another frame.
printf 1 >"$ARANEA_TEST_SANDBOX/grid"
printf old >"$out/favorites.png"
: >"$ARANEA_TEST_SANDBOX/calls"
rc=0
CAPTURE_GRID_STUCK=1 "$capture" --surface favorites --output "$out" >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 && "$(cat "$out/favorites.png")" == old ]]
if grep -Fxq grim "$ARANEA_TEST_SANDBOX/calls"; then
  echo 'capture grabbed a frame while the native app grid remained open' >&2
  exit 1
fi

# Unknown compositor state must fail closed, rather than blindly toggling
# the grid or publishing a screenshot whose background was not verified.
printf 0 >"$ARANEA_TEST_SANDBOX/grid"
for reply in '' invalid '[]' null; do
  : >"$ARANEA_TEST_SANDBOX/calls"
  rc=0
  CAPTURE_LAYER_REPLY="$reply" "$capture" --surface favorites --output "$out" >/dev/null 2>&1 || rc=$?
  [[ "$rc" != 0 && "$(cat "$out/favorites.png")" == old ]]
  if grep -Eq '^grim$|^shell omarchy\.dock apps$' "$ARANEA_TEST_SANDBOX/calls"; then
    echo 'unknown layer state allowed a grab or a blind grid toggle' >&2
    exit 1
  fi
done
rc=0
CAPTURE_LAYER_FAIL=1 "$capture" --surface favorites --output "$out" >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 && "$(cat "$out/favorites.png")" == old ]]
[[ ! -s "$ARANEA_TEST_SANDBOX/guard.log" ]]
echo 'menu capture app-grid cleanup contract passed'
