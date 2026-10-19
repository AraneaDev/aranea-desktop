#!/usr/bin/env bash
# Installed Aranea reloads over an unchanged stock host, including bar remounts.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/tests/lib/qml-host.sh"
require_qml_host
for dependency in sway dbus-run-session inotifywait; do
  if ! command -v "$dependency" >/dev/null; then
    printf 'SKIP: stock-host reload test needs %s\n' "$dependency"
    [[ "$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)" != 1 ]] || exit 1
    exit 0
  fi
done
source_root="$repo_root"
stock_root="$(dirname "$qml_shell_dir")"
stage=$(mktemp -d /tmp/aranea-overlay-ui.XXXXXX)
sway_pid='' qs_pid=''
# Stops only the private compositor and its shell process group.
cleanup() {
  if [[ -n "$qs_pid" ]]; then
    kill -- "-$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  if [[ -n "$sway_pid" ]]; then
    kill "$sway_pid" 2>/dev/null || true
    wait "$sway_pid" 2>/dev/null || true
  fi
  rm -rf "$stage"
}
sandbox_on_exit cleanup
mkdir -p "$stage/runtime" "$stage/home/.config/omarchy/plugins" "$stage/stock"
chmod 700 "$stage/runtime"
cp -a "$qml_shell_dir" "$stage/stock/shell"
for path in bin config default; do ln -s "$stock_root/$path" "$stage/stock/$path"; done
printf 'output HEADLESS-1 mode 1000x600\nseat seat0 fallback true\n' >"$stage/sway.conf"
export XDG_RUNTIME_DIR="$stage/runtime" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset WAYLAND_DISPLAY DISPLAY SWAYSOCK HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
sway -c "$stage/sway.conf" >"$stage/sway.log" 2>&1 &
sway_pid=$!
for ((attempt = 0; attempt < 60; attempt++)); do
  socket=$(find "$stage/runtime" -maxdepth 1 -type s -name 'wayland-*' -print -quit)
  [[ -n $socket ]] && break
  sleep 0.1
done
[[ -n $socket ]] || {
  cat "$stage/sway.log"
  exit 1
}
export WAYLAND_DISPLAY="${socket##*/}"
plugin_dir="$stage/home/.config/omarchy/plugins"
cp -a "$source_root/plugins/araneadev.bar" "$source_root/plugins/araneadev.shared" "$plugin_dir/"
mkdir -p "$plugin_dir/fixture.widget" "$plugin_dir/fixture.auth"
python3 - "$stage/stock" "$stage/home/.config/omarchy/shell.json" <<'PY'
import pathlib,json,sys
root=pathlib.Path(sys.argv[1]); manifests=list((root/'shell/plugins').glob('**/manifest.json'))+list((root/'shell/plugins').glob('**/*.manifest.json'))
ids=[json.loads(p.read_text())['id'] for p in manifests]
pathlib.Path(sys.argv[2]).write_text(json.dumps({'version':1,'bar':{'id':'araneadev.bar','position':'top','layout':{'left':[{'id':'fixture.widget'}],'center':[],'right':[]}},'plugins':[{'id':'fixture.auth'}],'disabledPlugins':ids,'idle':{'screensaver':0,'lock':0}}))
PY
cat >"$plugin_dir/fixture.widget/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"fixture.widget","name":"Reload marker","version":"1","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"},"barWidget":{"displayName":"Reload marker"}}
JSON
cat >"$plugin_dir/fixture.widget/Widget.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import "Logic.js" as Logic
Item {
  id: widget
  property var bar: null
  implicitWidth: 250
  implicitHeight: 30
  property string marker: "QML one / " + Logic.marker()
  Text { anchors.centerIn: parent; text: widget.marker; textFormat: Text.PlainText; color: '#a5f5d2'; font.pixelSize: 18 }
  IpcHandler {
    target: 'overlay.marker'
    function state(): string { return JSON.stringify({marker: widget.marker, pid: Quickshell.processId, watchFiles: Quickshell.watchFiles}) }
  }
}
QML
printf 'function marker() { return "JS one" }\n' >"$plugin_dir/fixture.widget/Logic.js"
cat >"$plugin_dir/fixture.auth/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"fixture.auth","name":"Authentication activity stand-in","version":"1","kinds":["service"],"keepLoaded":true,"omarchy":{"clonedFrom":"omarchy.lock"},"entryPoints":{"service":"Service.qml"}}
JSON
cat >"$plugin_dir/fixture.auth/Service.qml" <<'QML'
import QtQuick
import Quickshell.Io
import "../araneadev.shared" as Aranea
Item {
  id: auth
  property bool locked: false
  property bool authenticating: false
  Aranea.PluginReloadGuard { kind: 'lock'; busy: auth.locked }
  Aranea.PluginReloadGuard { kind: 'polkit'; busy: auth.authenticating }
  IpcHandler {
    target: 'overlay.auth'
    function setLocked(value: bool): void { auth.locked = value }
    function setPrompt(value: bool): void { auth.authenticating = value }
  }
}
QML
setsid env HOME="$stage/home" XDG_CONFIG_HOME="$stage/home/.config" XDG_STATE_HOME="$stage/home/.local/state" XDG_CACHE_HOME="$stage/home/.cache" OMARCHY_PATH="$stage/stock" PATH="$stage/stock/bin:$PATH" QS_NO_RELOAD_POPUP=1 dbus-run-session -- "$quickshell_bin" -p "$stage/stock/shell" --no-color >"$stage/shell.log" 2>&1 &
qs_pid=$!
# Calls the isolated stock shell on its private display.
ipc() { "$quickshell_bin" ipc --any-display -p "$stage/stock/shell" call "$@"; }
# Waits for the expected source generation or prints host diagnostics.
wait_marker() {
  local expected=$1 result=''
  for ((attempt = 0; attempt < 100; attempt++)); do
    result=$(ipc overlay.marker state 2>/dev/null || true)
    if jq -e --arg marker "$expected" '.marker == $marker' <<<"$result" >/dev/null 2>&1; then return 0; fi
    sleep 0.1
  done
  printf 'Expected %s, got %s\n' "$expected" "$result"
  tail -70 "$stage/shell.log"
  exit 1
}
wait_marker 'QML one / JS one'
initial_pid=$(ipc overlay.marker state | jq -r '.pid')
ipc overlay.auth setLocked true
sed -i 's/QML one/QML two/g' "$plugin_dir/fixture.widget/Widget.qml"
printf 'function marker() { return "JS two" }\n' >"$plugin_dir/fixture.widget/Logic.js"
sleep 1
wait_marker 'QML one / JS one'
printf 'Stock Omarchy + installed Aranea, lock deferred: %s\n' "$(ipc aranea.reload status)"
ipc overlay.auth setLocked false
wait_marker 'QML two / JS two'
[[ $(ipc overlay.marker state | jq -r '.pid') == "$initial_pid" ]]
printf 'Overlay watcher refreshed QML + JS: %s\n' "$(ipc overlay.marker state)"
ipc overlay.auth setPrompt true
printf 'function marker() { return "JS three" }\n' >"$plugin_dir/fixture.widget/Logic.js"
sleep 1
wait_marker 'QML two / JS two'
ipc overlay.auth setPrompt false
wait_marker 'QML two / JS three'
[[ $(ipc overlay.marker state | jq -r '.pid') == "$initial_pid" ]]
printf 'Repeated JS-only edit applied after authentication: %s\n' "$(ipc overlay.marker state)"
diff -qr "$qml_shell_dir" "$stage/stock/shell" >/dev/null
printf 'PASS: stock Omarchy source unchanged\n'
"$quickshell_bin" kill --any-display -p "$stage/stock/shell" >/dev/null
wait "$qs_pid" || true
