#!/usr/bin/env bash
# Real notification keyboard grab/release acceptance on a private Wayland seat.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/qml-host.sh"
require_qml_host
for dep in sway swaymsg setpriv dbus-run-session python3; do
  if ! command -v "$dep" >/dev/null; then
    echo "SKIP: native notifications needs $dep"
    [[ "$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)" != 1 ]] || exit 1
    exit 0
  fi
done
# Bypass the general side-effect guard only for our private Wayland display.
wtype_bin=''
while IFS= read -r candidate; do
  [[ "$candidate" == */tests/guard-bin/* ]] && continue
  wtype_bin=$candidate
  break
done < <(type -ap wtype 2>/dev/null || true)
if [[ -z $wtype_bin ]]; then
  echo 'SKIP: native notifications needs real wtype'
  [[ "$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)" != 1 ]] || exit 1
  exit 0
fi
stage=$(mktemp -d /tmp/aranea-native.XXXXXX)
sway_pid='' qs_pid='' keyboard_pid=''
# Stop only the process groups started by this invocation, then remove sockets.
cleanup() {
  local result=${status:-0}
  if ((result != 0)); then
    [[ ! -f "$stage/client.log" ]] || cat "$stage/client.log"
  fi
  if [[ -n $keyboard_pid ]]; then
    kill "$keyboard_pid" 2>/dev/null || true
    wait "$keyboard_pid" 2>/dev/null || true
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
mkdir -p "$XDG_STATE_HOME/omarchy/current/theme/branding"
cp "$repo_root/branding/brand.svg" "$XDG_STATE_HOME/omarchy/current/theme/branding/"
ln -s "$qml_shell_dir/Commons" "$stage/cfg/Commons"
ln -s "$qml_shell_dir/Ui" "$stage/cfg/Ui"
ln -s "$repo_root/tests/qml/lib" "$stage/cfg/lib"
ln -s "$repo_root/tests/qml/fixtures/notification-hyprland" "$stage/cfg/notification-hyprland"
ln -s "$repo_root/plugins/araneadev.shared" "$stage/cfg/plugins/araneadev.shared"
cp -r "$repo_root/plugins/araneadev.notifications" "$stage/cfg/plugins/"
# Only replace external Hyprland window records; native Wayland surfaces stay real.
for file in Service.qml Toasts.qml; do
  sed -i 's|import Quickshell.Hyprland|import "../../notification-hyprland"|' "$stage/cfg/plugins/araneadev.notifications/$file"
done
cp "$repo_root/tests/qml/fixtures/native/notifications.qml" "$stage/cfg/shell.qml"
printf 'output HEADLESS-1 mode 1200x900\noutput HEADLESS-2 mode 1200x900 pos 1200 0\nseat seat0 fallback true\n' >"$stage/sway.conf"
export WLR_HEADLESS_OUTPUTS=2
export XDG_RUNTIME_DIR="$stage/runtime" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset WAYLAND_DISPLAY DISPLAY SWAYSOCK HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
setsid setpriv --no-new-privs sway -c "$stage/sway.conf" >"$stage/sway.log" 2>&1 &
sway_pid=$!
for ((i = 0; i < 60; i++)); do
  socket=$(find "$stage/runtime" -maxdepth 1 -type s -name 'wayland-*' -print -quit)
  [[ -n $socket ]] && break
  kill -0 "$sway_pid" 2>/dev/null || break
  sleep .1
done
[[ -n $socket ]] || {
  cat "$stage/sway.log"
  echo "FAIL: private compositor did not expose a Wayland socket"
  exit 1
}
export WAYLAND_DISPLAY="${socket##*/}"
# Keep a keyboard capability on this otherwise device-free private seat.
"$wtype_bin" -s 60000 &
keyboard_pid=$!
sleep .2
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
sway_socket=$(find "$stage/runtime" -maxdepth 1 -type s -name 'sway-ipc*' -print -quit)
swaymsg -s "$sway_socket" '[title="Aranea native keyboard sink"] move to output HEADLESS-2' >/dev/null
swaymsg -s "$sway_socket" focus output HEADLESS-2 >/dev/null
# Both qs and wtype resolve only this private runtime; no inherited display/bus.
notification() { "$quickshell_bin" ipc --any-display -p "$stage/cfg" call notifications "$@"; }
# Inject real keys after the private keyboard has joined the seat.
key() {
  "$wtype_bin" -s 100 "$@" -s 100
  sleep .2
}
key initial
ipc typedText initial
[[ $(notification keyboard) == on ]]
ipc held enter
sleep .2
ipc paused
key -k Down -k Return
ipc action enter
ipc seed 82
[[ $(notification keyboard) == on ]]
ipc held number
key 1
ipc action number
ipc seed 83
[[ $(notification keyboard) == on ]]
ipc held escape
key -k Escape
ipc escaped
sleep .2
ipc resumed
key released
ipc typedText released
[[ $(notification keyboard) == on ]]
ipc removeSelected
key 1
ipc stale
ipc typedText 1
[[ $(notification keyboard) == on ]]
ipc openCenter
sleep .3
# Production primes Exclusive, then uses Hyprland-specific OnDemand retention.
# Sway delivers the prime (asserted), but needs a pointer refocus at OnDemand.
# This click hits the real center card; it never changes its keyboard policy.
ipc handoff
python3 "$repo_root/tests/lib/private-pointer.py" 80 30 click
key -k Down
ipc centerKey
key -k Escape
ipc centerClosed
key handedoff
ipc typedText handedoff
[[ $(notification keyboard) == on ]]
swaymsg -s "$sway_socket" output HEADLESS-2 unplug >/dev/null
sleep .3
ipc outputLost
[[ $(notification keyboard) == on ]]
ipc teardown
wait_log 'NATIVE TEARDOWN'
key teardown
ipc typedText teardown
ipc finish
wait_log 'QMLTEST DONE'
cat "$stage/client.log"
rg -q 'QMLTEST DONE 0' "$stage/client.log"
if rg -q 'QMLTEST FAIL|TypeError|ReferenceError|Binding loop detected|Unable to assign' "$stage/client.log"; then exit 1; fi
echo 'PASS: native notification keyboard ownership, actions, center handoff and release'
