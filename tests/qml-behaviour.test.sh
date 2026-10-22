#!/usr/bin/env bash
# Runs the offscreen QML behaviour tests (tests/qml/*.qml) under quickshell
# with QT_QPA_PLATFORM=offscreen; passes when a test prints "QMLTEST DONE 0",
# no "QMLTEST FAIL", no runtime error or binding loop, and loads cleanly.
# "QMLTEST SKIP" lines (checks this environment cannot run) are listed.
# Skips (exit 0; 1 with ARANEA_CHECK_REQUIRE_ALL=1) without quickshell or the
# Omarchy shell.
#
# Usage: tests/qml-behaviour.test.sh [name...]
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Each test is the shell.qml of a throwaway config next to links to the
# host's Commons/Ui, the test helpers and every Aranea plugin.
shell_dir="$(sandbox_inherited_value ARANEA_QML_SHELL_DIR)"
timeout_s="$(sandbox_inherited_value ARANEA_QMLTEST_TIMEOUT)"
require_all="$(sandbox_inherited_value ARANEA_CHECK_REQUIRE_ALL)"
shell_dir="${shell_dir:-/usr/share/omarchy/shell}"
timeout_s="${timeout_s:-30}"
# The real quickshell: the sandbox puts guard stubs (one is named quickshell)
# first on PATH, possibly already in a caller's sandbox too.
quickshell_bin=""
while IFS= read -r candidate; do
  [[ "$candidate" == */tests/guard-bin/* ]] && continue
  quickshell_bin="$candidate"
  break
done < <(type -ap quickshell 2>/dev/null || true)

if [[ -z "$quickshell_bin" || ! -f "$shell_dir/Commons/qmldir" ]]; then
  echo "SKIP: QML behaviour tests need quickshell and the Omarchy shell at $shell_dir"
  [[ "$require_all" == 1 ]] && exit 1
  exit 0
fi

run_dir=""
qs_pid=""
# Stops quickshell and every process it started (it leads its own process
# group, see run_test) and removes the current run directory.
cleanup() {
  if [[ -n "$qs_pid" ]]; then
    kill -- "-$qs_pid" 2>/dev/null || true
    sleep 0.5
    kill -9 -- "-$qs_pid" 2>/dev/null || true
  fi
  qs_pid=""
  [[ -n "$run_dir" ]] && rm -rf "$run_dir"
  run_dir=""
}
sandbox_on_exit cleanup

# Runs one test file; prints its result and returns non-zero when it failed.
run_test() {
  local test_file="$1" name plugin waited=0 status=0
  local state_home="$XDG_STATE_HOME"
  name="$(basename "$test_file" .qml)"
  # Short path: the quickshell IPC socket path is limited to 108 bytes.
  run_dir="$(mktemp -d /tmp/aranea-qt.XXXXXX)"
  mkdir -p "$run_dir/cfg/plugins" "$run_dir/run"
  chmod 700 "$run_dir/run"
  ln -s "$shell_dir/Commons" "$run_dir/cfg/Commons"
  ln -s "$shell_dir/Ui" "$run_dir/cfg/Ui"
  ln -s "$repo_root/tests/qml/lib" "$run_dir/cfg/lib"
  ln -s "$repo_root/tests/qml/fixtures" "$run_dir/cfg/fixtures"
  for plugin in "$repo_root"/plugins/araneadev.*; do
    [[ -d "$plugin" ]] || continue
    if [[ "$plugin" == */araneadev.shared && ("$name" == agent-tasks-panel || "$name" == agents-provider-selection || "$name" == spring-panel || "$name" == vpn-embedded || "$name" == bluetooth-embedded || "$name" == system-embedded || "$name" == display-persistent-commands || "$name" == network-telemetry-panel || "$name" == health-alerts || "$name" == clock-civil-dates || "$name" == worldclock-panel || ("$name" == clock-embedded-controllers || "$name" == unified-clock || "$name" == clock-production-loader) || "$name" == updates-production-host || "$name" == production-widget-panels) ]]; then
      # Adapt only native windows/attached layer-shell state. Placement, mask,
      # motion, coordinator, focus timer and production panel content stay real.
      mkdir -p "$run_dir/cfg/plugins/araneadev.shared"
      for shared in "$plugin"/*; do
        [[ "${shared##*/}" == SpringPanel.qml ]] && continue
        ln -s "$shared" "$run_dir/cfg/plugins/araneadev.shared/${shared##*/}"
      done
      python - "$plugin/SpringPanel.qml" "$run_dir/cfg/plugins/araneadev.shared/SpringPanel.qml" <<'PYBOUNDARY'
import pathlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
source = source.replace('import QtQuick', 'import QtQuick\nimport "../../fixtures/agent-panel-host"')
source = re.sub(r'\bPanelWindow\s*\{', 'NativePanelWindow {', source)
source = source.replace('WlrLayershell.', 'nativeLayer.')
# These are native window anchors, never Item anchors in content.
source = re.sub(r'(?m)^(  |        )anchors \{', r'\1nativeAnchors {', source)
pathlib.Path(sys.argv[2]).write_text(source)
PYBOUNDARY
    elif [[ "$plugin" == */araneadev.clock && ("$name" == unified-clock || "$name" == clock-production-loader) ]]; then
      # Native windows ignore ancestor Item visibility; the Item boundary must too.
      mkdir -p "$run_dir/cfg/plugins/araneadev.clock"
      for source in "$plugin"/*; do
        [[ "${source##*/}" == BarWidget.qml ]] && continue
        ln -s "$source" "$run_dir/cfg/plugins/araneadev.clock/${source##*/}"
      done
      sed 's/visible: false/visible: true/' "$plugin/BarWidget.qml" >"$run_dir/cfg/plugins/araneadev.clock/BarWidget.qml"
    elif [[ "$plugin" == */araneadev.settings && "$name" == settings-window-geometry ]]; then
      # Keep the production window's geometry/content bindings; only replace
      # its compositor boundary with the same inert host used by panel tests.
      mkdir -p "$run_dir/cfg/plugins/araneadev.settings"
      for source in "$plugin"/*; do
        [[ "${source##*/}" == SettingsWindow.qml ]] && continue
        ln -s "$source" "$run_dir/cfg/plugins/araneadev.settings/${source##*/}"
      done
      python - "$plugin/SettingsWindow.qml" "$run_dir/cfg/plugins/araneadev.settings/SettingsWindow.qml" <<'PYSETTINGSWINDOW'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
source = source.replace('import QtQuick', 'import QtQuick\nimport "../../fixtures/agent-panel-host"', 1)
source = source.replace('PanelWindow {', 'NativePanelWindow {', 1)
source = source.replace('WlrLayershell.', 'nativeLayer.')
pathlib.Path(sys.argv[2]).write_text(source)
PYSETTINGSWINDOW
    elif [[ "$plugin" == */araneadev.osd && "$name" == osd-messages ]]; then
      # Keep OSD state, layout and real presentation; replace only its native
      # layer-shell window so session-message checks never need a compositor.
      mkdir -p "$run_dir/cfg/plugins/araneadev.osd"
      for source in "$plugin"/*; do
        [[ "${source##*/}" == Osd.qml ]] && continue
        ln -s "$source" "$run_dir/cfg/plugins/araneadev.osd/${source##*/}"
      done
      python - "$plugin/Osd.qml" "$run_dir/cfg/plugins/araneadev.osd/Osd.qml" <<'PYOSDWINDOW'
import pathlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
source = source.replace('import QtQuick', 'import QtQuick\nimport "../../fixtures/agent-panel-host"')
source = re.sub(r'\bPanelWindow\s*\{', 'NativePanelWindow {', source)
source = source.replace('WlrLayershell.', 'nativeLayer.')
source = source.replace('    anchors {', '    nativeAnchors {')
pathlib.Path(sys.argv[2]).write_text(source)
PYOSDWINDOW
    elif [[ "$plugin" == */araneadev.bar && ("$name" == sudo-relay || "$name" == clock-aliases || "$name" == bar-foreground) ]]; then
      mkdir -p "$run_dir/cfg/plugins/araneadev.bar"
      for source in "$plugin"/*; do
        [[ "${source##*/}" == Bar.qml ]] && continue
        ln -s "$source" "$run_dir/cfg/plugins/araneadev.bar/${source##*/}"
      done
      python - "$plugin/Bar.qml" "$run_dir/cfg/plugins/araneadev.bar/Bar.qml" <<'PYBARWINDOW'
import pathlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
# Keep the real root owner, registry, module slots and methods. Only its
# compositor-owned window delegates become inert types with no outputs.
source = source.replace("model: Quickshell.screens", "model: []")
tokens = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`(?:\\.|[^`\\])*`|[{}]')
for name in ("BarPanel", "DragGhostPanel", "BarMoveGhostPanel"):
    start = source.index("  component " + name + ": PanelWindow {")
    opening = source.index("{", start)
    depth = 0
    for token in tokens.finditer(source, opening):
        if token[0] == "{":
            depth += 1
        elif token[0] == "}":
            depth -= 1
            if depth == 0:
                end = token.end()
                break
    replacement = "  component " + name + ": Item { property var screen; property var ghostScreen }"
    source = source[:start] + replacement + source[end:]
pathlib.Path(sys.argv[2]).write_text(source)
PYBARWINDOW
    else
      ln -s "$plugin" "$run_dir/cfg/plugins/${plugin##*/}"
    fi
  done
  if [[ ("$name" == clock-embedded-controllers || "$name" == unified-clock || "$name" == clock-production-loader) ]]; then
    # Count every main frame, including transient standalone construction.
    # SpringPanel also creates legitimate per-output dismissal surfaces on open.
    sed -i '/^  id: root$/a\  Component.onCompleted: console.log("QMLTEST CLOCK NATIVE FRAME")' "$run_dir/cfg/plugins/araneadev.shared/SpringPanel.qml"
  fi
  if [[ "$name" == clock-production-loader ]]; then
    # Registry entry points live outside the scanned shell, just as installed
    # plugins do. Never import their directories from the test shell.
    mkdir -p "$run_dir/external/calendar-plugins"
    mv "$run_dir/cfg/plugins" "$run_dir/external/plugins"
    cp -a "$run_dir/external/plugins/araneadev.clock" "$run_dir/external/plugins/araneadev.shared" "$run_dir/external/calendar-plugins/"
    ln -s "$repo_root/tests/qml/fixtures" "$run_dir/external/fixtures"
    ln -s "$shell_dir/services" "$run_dir/cfg/services"
  fi
  if [[ "$name" == screensaver-idle ]]; then
    # Preserve upstream Service/IdleModel verbatim except native IdleMonitor.
    mkdir -p "$run_dir/cfg/upstream-idle"
    ln -s "$shell_dir/plugins/services/idle/IdleModel.js" "$run_dir/cfg/upstream-idle/IdleModel.js"
    python3 - "$shell_dir/plugins/services/idle/Service.qml" "$run_dir/cfg/upstream-idle/Service.qml" <<'PYIDLE'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
assert source.count("  IdleMonitor {") == 1
source = source.replace('import QtQuick', 'import QtQuick\nimport "../fixtures/idle-host"', 1)
source = source.replace("  IdleMonitor {", "  NativeIdleMonitor {")
pathlib.Path(sys.argv[2]).write_text(source)
PYIDLE
  fi
  ln -s "$repo_root/shell.toml" "$run_dir/cfg/theme-shell.toml"
  cp "$test_file" "$run_dir/cfg/shell.qml"
  # Fixed Display command boundary: controllers and hosted System tests never
  # discover host devices or execute desktop mutations. Other ls calls delegate.
  mkdir -p "$run_dir/display-bin" "$run_dir/display-state"
  local display_command
  for display_command in display-fixture omarchy-display-text-size omarchy-toggle-nightlight brightnessctl omarchy-brightness-keyboard omarchy-monitor-state omarchy-battery-status omarchy-powerprofiles-list upower ls; do
    ln -s "$repo_root/tests/qml/fixtures/display-command.py" "$run_dir/display-bin/$display_command"
  done
  if [[ ("$name" == clock-embedded-controllers || "$name" == unified-clock || "$name" == clock-production-loader) ]]; then
    # Record only controller commands; Commons Style has unrelated startup probes.
    : >"${ARANEA_TEST_SANDBOX:?}/clock-calls.log"
    cat >"$run_dir/display-bin/clock-command" <<'CLOCKCOMMAND'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")${*:+ $*}" >>"${ARANEA_TEST_SANDBOX:?}/clock-calls.log"
CLOCKCOMMAND
    chmod +x "$run_dir/display-bin/clock-command"
    for display_command in curl omarchy-weather-location timedatectl; do
      ln -s "$run_dir/display-bin/clock-command" "$run_dir/display-bin/$display_command"
    done
  fi
  if [[ "$name" == network-telemetry-panel || "$name" == network-telemetry ]]; then
    # Fake only command I/O; production telemetry and host lifecycle remain real.
    for display_command in network-fixture omarchy-network-status omarchy-network-band omarchy-dns nmcli ip busctl; do
      ln -s "$repo_root/tests/qml/fixtures/network-command.py" "$run_dir/display-bin/$display_command"
    done
  fi
  if [[ "$name" == bar-foreground || "$name" == bar-foreground-controller ]]; then
    # Exercise real Process/Timer/FileView ownership with only command I/O faked.
    # This watcher needs a file where other fixtures expect a directory.
    state_home="$run_dir/state"
    mkdir -p "$state_home/omarchy"
    printf 'initial\n' >"$state_home/omarchy/current"
    for display_command in omarchy-bar-text-color bar-foreground-fixture; do
      ln -s "$repo_root/tests/qml/fixtures/bar-foreground-command.py" "$run_dir/display-bin/$display_command"
    done
  fi
  if [[ "$name" == screensaver-idle ]]; then
    : >"${ARANEA_TEST_SANDBOX:?}/idle-effects"
    # Login-shell setup is an external boundary; preserve Process commands and
    # route their fixed actions into this private PATH, never the host session.
    cat >"$run_dir/display-bin/bash" <<'IDLEBASH'
#!/usr/bin/python3
import os, sys
args = ["-c" if value == "-lc" else value for value in sys.argv[1:]]
os.execv("/usr/bin/bash", ["bash", *args])
IDLEBASH
    cat >"$run_dir/display-bin/idle-action" <<'IDLEACTION'
#!/usr/bin/python3
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with (pathlib.Path(os.environ["ARANEA_TEST_SANDBOX"]) / "idle-effects").open("a") as stream:
    stream.write(name + " " + " ".join(sys.argv[1:]) + "\n")
if name == "omarchy-shell":
    print("false")
IDLEACTION
    chmod +x "$run_dir/display-bin/bash" "$run_dir/display-bin/idle-action"
    for display_command in omarchy-shell omarchy-launch-screensaver omarchy-system-lock omarchy-system-wake; do
      ln -s "$run_dir/display-bin/idle-action" "$run_dir/display-bin/$display_command"
    done
  fi
  # Replace the entire native sudo helper; never execute a grant or policy command.
  mkdir -p "$run_dir/sudo-bin" "$run_dir/sudo-state"
  if [[ "$name" == sudo-widget || "$name" == sudo-relay ]]; then
    printf '0\n' >"$run_dir/sudo-state/active"
    ln -s "$repo_root/tests/qml/fixtures/sudo-bin/omarchy-sudo-passwordless" "$run_dir/sudo-bin/omarchy-sudo-passwordless"
    ln -s "$repo_root/tests/qml/fixtures/sudo-bin/omarchy-sudo-passwordless" "$run_dir/sudo-bin/omarchy-notification-send"
  fi
  # No display, compositor, session bus or desktop platform theme (the gtk3
  # theme aborts without a display).
  # From the run directory, so a relative path in a test can never write
  # into the repository; setsid makes it lead its own process group, so
  # cleanup also stops the commands a test started.
  (cd "$run_dir" && exec setsid env -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u HYPRLAND_INSTANCE_SIGNATURE \
    -u QT_QPA_PLATFORMTHEME -u QT_STYLE_OVERRIDE QT_QPA_PLATFORM=offscreen \
    PATH="$run_dir/sudo-bin:$run_dir/display-bin:$PATH" OMARCHY_PATH="${shell_dir%/shell}" ARANEA_SUDO_FIXTURE_ROOT="$run_dir/sudo-state" ARANEA_DISPLAY_FIXTURE_ROOT="$run_dir/display-state" \
    ARANEA_CLOCK_TEST_PLUGIN_ROOT="$run_dir/external/plugins" XDG_RUNTIME_DIR="$run_dir/run" XDG_CACHE_HOME="$run_dir/cache" XDG_STATE_HOME="$state_home" \
    "$quickshell_bin" -p "$run_dir/cfg") >"$run_dir/log" 2>&1 &
  qs_pid=$!
  while ((waited < timeout_s * 5)); do
    grep -q 'QMLTEST DONE' "$run_dir/log" && break
    grep -q 'Failed to load configuration' "$run_dir/log" && break
    kill -0 "$qs_pid" 2>/dev/null || break
    sleep 0.2
    waited=$((waited + 1))
  done
  local log
  log="$(sed 's/\x1b\[[0-9;]*m//g' "$run_dir/log")"
  cleanup
  if [[ "$name" == clock-embedded-controllers ]] && grep -q 'QMLTEST CLOCK NATIVE FRAME' <<<"$log"; then
    echo "  QMLTEST FAIL embedded construction created a native frame"
    status=1
  fi
  if [[ ("$name" == unified-clock || "$name" == clock-production-loader) ]] && [[ "$(grep -c 'QMLTEST CLOCK NATIVE FRAME' <<<"$log")" != 2 ]]; then
    echo "  QMLTEST FAIL unified clock must construct exactly two cumulative native frames for two clocks"
    status=1
  fi
  if grep -q 'Failed to load configuration' <<<"$log"; then
    echo "qmltest: $name FAILED (did not load)"
    grep -E 'ERROR' <<<"$log" | grep -v 'quickshell.ipc' | sed 's/^/  /'
    return 1
  fi
  grep -E 'QMLTEST FAIL' <<<"$log" | sed 's/^.*QMLTEST FAIL/  QMLTEST FAIL/' && status=1
  if ! grep -q 'QMLTEST DONE' <<<"$log"; then
    echo "qmltest: $name FAILED (no QMLTEST DONE within ${timeout_s}s)"
    grep -E 'ERROR|TypeError|ReferenceError' <<<"$log" | grep -v 'quickshell.ipc' | sed 's/^/  /' | head -20
    return 1
  fi
  # A runtime error fails the test even when every check passed: it means
  # some code path the test drove threw. So does a binding loop: Qt only
  # warns, and keeps the stale value.
  local errors
  errors="$(grep -E 'TypeError|ReferenceError|is not a function|Cannot read property|Unable to assign|Binding loop detected' <<<"$log" | grep -v 'quickshell.ipc' || true)"
  if [[ -n "$errors" ]]; then
    echo "qmltest: $name FAILED (runtime error or binding loop)"
    head -20 <<<"$errors" | sed 's/^/  /'
    return 1
  fi
  if ((status)); then
    echo "qmltest: $name FAILED"
    return 1
  fi
  # A skipped check (QmlTest.skip: this environment cannot run it) is named,
  # so the gap is visible in the stage output.
  local skipped suffix=""
  skipped="$(grep -c 'QMLTEST SKIP' <<<"$log" || true)"
  ((skipped)) && suffix=", $skipped skipped"
  echo "qmltest: $name ok ($(grep -c 'QMLTEST PASS' <<<"$log") checks$suffix)"
  grep -E 'QMLTEST SKIP' <<<"$log" | sed 's/^.*QMLTEST SKIP/  QMLTEST SKIP/' || true
}

tests=()
if (($#)); then
  for name in "$@"; do tests+=("$repo_root/tests/qml/$name.qml"); done
else
  for file in "$repo_root"/tests/qml/*.qml; do [[ -f "$file" ]] && tests+=("$file"); done
fi
failed=0
for file in "${tests[@]}"; do
  run_test "$file" || failed=1
done
exit "$failed"
