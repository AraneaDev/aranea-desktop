#!/usr/bin/env bash
# Real Qt RHI + layer-shell/input acceptance on a private headless compositor.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Each mode owns a fresh sandbox and must complete; none can be replaced by a skip.
if (($# == 0)); then
  for fixture in bar tray picker; do bash "$0" "$fixture"; done
  exit 0
fi
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/qml-host.sh"
require_qml_host
for dep in sway swaymsg setpriv dbus-run-session python3 magick; do
  if ! command -v "$dep" >/dev/null; then
    echo "SKIP: native rendering needs $dep"
    [[ "$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)" != 1 ]] || exit 1
    exit 0
  fi
done
mode=${1:-bar}
[[ $mode == bar || $mode == tray || $mode == picker ]] || exit 2
# Reject a non-fixture runtime before any pointer socket can be opened.
if XDG_RUNTIME_DIR="$ARANEA_TEST_SANDBOX" WAYLAND_DISPLAY=wayland-0 python3 "$repo_root/tests/lib/private-pointer.py" 1 1 >/dev/null 2>&1; then
  echo "FAIL: virtual pointer accepted a non-fixture runtime"
  exit 1
fi
stage=$(mktemp -d /tmp/aranea-native.XXXXXX)
sway_pid='' qs_pid='' pointer_pid=''
# Stop only the process groups started by this invocation, then remove sockets.
cleanup() {
  if [[ -n $pointer_pid ]]; then
    kill "$pointer_pid" 2>/dev/null || true
    wait "$pointer_pid" 2>/dev/null || true
  fi
  if [[ -n $qs_pid ]]; then
    kill -- "-$qs_pid" 2>/dev/null || true
    sleep .3
    kill -9 -- "-$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  if [[ -n $sway_pid ]]; then
    kill -- "-$sway_pid" 2>/dev/null || true
    sleep .3
    kill -9 -- "-$sway_pid" 2>/dev/null || true
    wait "$sway_pid" 2>/dev/null || true
  fi
  rm -rf "$stage"
}
sandbox_on_exit cleanup
mkdir -p "$stage/runtime" "$stage/cfg/plugins"
chmod 700 "$stage/runtime"
printf '%s' "$UID" >"$stage/private-native-fixture"
ln -s "$qml_shell_dir/Commons" "$stage/cfg/Commons"
ln -s "$qml_shell_dir/Ui" "$stage/cfg/Ui"
ln -s "$repo_root/tests/qml/lib" "$stage/cfg/lib"
ln -s "$repo_root/tests/qml/fixtures/native/bar-host" "$stage/cfg/bar-host"
for plugin in "$repo_root"/plugins/araneadev.*; do ln -s "$plugin" "$stage/cfg/plugins/${plugin##*/}"; done
# Read-only observers are added to a disposable copy; all native surfaces,
# input-region bindings, tooltip lifecycle and renderer code stay production.
rm "$stage/cfg/plugins/araneadev.bar"
cp -r "$repo_root/plugins/araneadev.bar" "$stage/cfg/plugins/"
python3 - "$stage/cfg/plugins/araneadev.bar/Bar.qml" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1]); s=p.read_text()
# Sway keeps Top layers below fullscreen; emulate Hyprland lifting them.
# This changes only stacking at the compositor boundary, never mask logic.
s=s.replace('WlrLayershell.layer: WlrLayer.Top', 'WlrLayershell.layer: WlrLayer.Overlay')
s=s.replace('import Quickshell.Hyprland', 'import "../../bar-host"')
s=s.replace('  id: root\n', '  id: root\n  property var nativeWindows: []\n', 1)
s=s.replace('    id: barWindow\n', '    id: barWindow\n    property alias nativeTooltip: tooltipWindow\n    Component.onCompleted: root.nativeWindows = root.nativeWindows.concat([barWindow])\n', 1)
s=s.replace('      id: tooltipWindow\n', '      id: tooltipWindow\n      property alias nativeBubble: tooltipBubble\n', 1)
p.write_text(s)
PY
if [[ $mode == tray ]]; then
  ln -s "$repo_root/tests/qml/fixtures/native/tray-host" "$stage/cfg/tray-host"
  rm "$stage/cfg/plugins/araneadev.tray"
  cp -r "$repo_root/plugins/araneadev.tray" "$stage/cfg/plugins/"
  # Retain Status enums from Quickshell; replace only the external item model.
  sed -i '/import Quickshell.Services.SystemTray/a import "../../tray-host" as TrayBoundary' "$stage/cfg/plugins/araneadev.tray/Tray.qml"
  sed -i 's/SystemTray.items/TrayBoundary.SystemTray.items/g' "$stage/cfg/plugins/araneadev.tray/Tray.qml"
  for spec in 'dark-symbolic #000000' 'light-symbolic #ffffff' 'color #ed3960'; do
    read -r name color <<<"$spec"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path fill="%s" d="M4 4h16v16H4z"/></svg>\n' "$color" >"$stage/$name"
  done
fi
export ARANEA_NATIVE_CAPTURE="$stage"
cp "$repo_root/tests/qml/fixtures/native/NativeClock.qml" "$stage/cfg/NativeClock.qml"
cp "$repo_root/tests/qml/fixtures/native/$mode.qml" "$stage/cfg/shell.qml"
printf 'output HEADLESS-1 mode 1200x900 scale 1.5\nseat seat0 fallback true\n' >"$stage/sway.conf"
export XDG_RUNTIME_DIR="$stage/runtime" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset WAYLAND_DISPLAY DISPLAY SWAYSOCK HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
setsid setpriv --no-new-privs sway -c "$stage/sway.conf" >"$stage/sway.log" 2>&1 &
sway_pid=$!
for ((i = 0; i < 60; i++)); do
  socket=$(find "$stage/runtime" -maxdepth 1 -type s -name 'wayland-*' -print -quit)
  [[ -n $socket ]] && break
  sleep .1
done
[[ -n $socket ]] || {
  cat "$stage/sway.log"
  exit 1
}
export WAYLAND_DISPLAY="${socket##*/}"
export QT_QPA_PLATFORM=wayland QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 QT_QUICK_BACKEND=rhi QT_NO_XDG_DESKTOP_PORTAL=1
setsid dbus-run-session -- "$quickshell_bin" -p "$stage/cfg" --no-color >"$stage/client.log" 2>&1 &
qs_pid=$!
# Wait for an observable fixture milestone, with a bounded failure log.
wait_log() {
  for ((i = 0; i < 100; i++)); do
    rg -q "$1" "$stage/client.log" && return 0
    rg -q 'Failed to load configuration|QMLTEST FAIL' "$stage/client.log" && break
    sleep .1
  done
  cat "$stage/client.log"
  return 1
}
# Address only this temporary Quickshell config on the private runtime.
ipc() { "$quickshell_bin" ipc --any-display -p "$stage/cfg" call native.fixture "$@"; }
wait_log 'NATIVE READY'
if [[ $mode == bar ]]; then
  # This is a private virtual pointer, never uinput or a physical seat.
  for pointer_x in 400 700; do
    python3 "$repo_root/tests/lib/private-pointer.py" "$pointer_x" 10 &
    pointer_pid=$!
    sleep .2
    ipc checkPeek false
    wait "$pointer_pid"
    pointer_pid=''
    sleep .2
  done
  python3 "$repo_root/tests/lib/private-pointer.py" 100 10 &
  pointer_pid=$!
  sleep .2
  ipc checkPeek true
  wait "$pointer_pid"
  pointer_pid=''
  sleep .2
  sway_socket=$(find "$stage/runtime" -maxdepth 1 -type s -name "sway-ipc*" -print -quit)
  swaymsg -s "$sway_socket" '[title="Aranea native click sink"] fullscreen enable' >/dev/null
  ipc fullscreen true
  sleep .2
  python3 "$repo_root/tests/lib/private-pointer.py" 700 10 click
  sleep .2
  ipc finish
fi
wait_log 'QMLTEST DONE'
cat "$stage/client.log"
rg -q 'QMLTEST DONE 0' "$stage/client.log"
if rg -q 'QMLTEST FAIL|TypeError|ReferenceError|Binding loop detected|Unable to assign' "$stage/client.log"; then
  exit 1
fi
if [[ $mode == tray ]]; then python3 "$repo_root/tests/lib/check-tray-pixels.py" "$stage"; fi
if [[ $mode == picker ]]; then python3 "$repo_root/tests/lib/check-picker-pixels.py" "$stage"; fi
echo "PASS: native $mode rendering and input"
