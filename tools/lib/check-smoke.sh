#!/usr/bin/env bash
# smoke stage for tools/check: loads every plugin entry point at runtime in
# Quickshell, inside an invisible headless sway (wlroots headless backend),
# with Omarchy's Commons/Ui, and fails on runtime errors (TypeError,
# ReferenceError, failed component loads, binding loops).
#
# Isolation from the running session: sway and Quickshell get a throwaway
# runtime dir, HOME, config, state and cache and their own D-Bus session bus
# (dbus-run-session). The system bus is shared, so the polkit agent, which
# would register with the user's real login session there, is left out of
# local runs; the Arch CI job (no login session) loads it too. sway runs in
# the foreground and starts the harness through its own config.
# Known messages are listed in tools/baselines/smoke-allow.txt, which can
# only shrink (like the qmllint baseline).
check_root="${check_root:?tools/check sets check_root}"
repo_root="${repo_root:?tools/check sets repo_root}"
update_baselines="${update_baselines:-0}"

# Prints the absolute path of every plugin entry point (from the manifests).
smoke_entry_points() {
  local manifest
  while IFS= read -r manifest; do
    [[ -n "$manifest" ]] || continue
    if [[ "${ARANEA_CHECK_REQUIRE_ALL:-0}" != 1 ]] && [[ "$(jq -r '.id // ""' "$check_root/$manifest" 2>/dev/null)" == araneadev.polkit ]]; then
      continue
    fi
    jq -r '.entryPoints[]? // empty' "$check_root/$manifest" 2>/dev/null |
      while IFS= read -r entry; do
        [[ "$entry" == *.qml ]] && printf '%s/%s\n' "$check_root/$(dirname "$manifest")" "$entry"
      done
  done < <(check_files '^plugins/[^/]+/manifest\.json$')
}

# Writes the harness (shell.qml + Commons/Ui links) into DIR.
smoke_write_harness() {
  local dir="$1" shell_dir="$2"
  mkdir -p "$dir"
  ln -s "$shell_dir/Commons" "$dir/Commons"
  ln -s "$shell_dir/Ui" "$dir/Ui"
  cat >"$dir/shell.qml" <<'EOF'
import QtQuick
import Quickshell

// Loads each file in SMOKE_FILES (colon-separated), reports load errors,
// lets bindings settle for a moment, then quits.
ShellRoot {
  id: harness
  property var files: Quickshell.env("SMOKE_FILES").split(":").filter(function (f) {
    return f.length > 0
  })
  Component.onCompleted: {
    for (var i = 0; i < files.length; i++) {
      var component = Qt.createComponent("file://" + files[i])
      if (component.status === Component.Error) {
        console.warn("SMOKE-ERROR " + files[i] + ": " + component.errorString())
        continue
      }
      var object = component.createObject(harness)
      console.log("SMOKE-LOADED " + files[i] + " " + (object !== null))
    }
    quitTimer.start()
  }
  Timer {
    id: quitTimer
    interval: 2000
    onTriggered: Qt.quit()
  }
}
EOF
}

# Prints the runtime problems in a Quickshell log, normalized for the
# allowlist: repo-relative paths, no line or column numbers. Entries that
# create their window or agent at runtime only warn "failed to load" when it
# breaks, so that counts as a problem too.
smoke_problems() {
  sed 's/\x1b\[[0-9;]*m//g' "$1" |
    grep -E 'SMOKE-ERROR|TypeError|ReferenceError|Unable to assign|is not a function|Cannot read property|Binding loop|failed to load|Required property' |
    sed -E "s#file://##g; s#${check_root}/##g; s#:[0-9]+(:-?[0-9]+)?:#:#g; s#\[[0-9]+:-?[0-9]+\]##g; s/^[[:space:]]*(WARN|ERROR|DEBUG)[[:space:]]+[a-z.]*:?[[:space:]]*//" |
    LC_ALL=C sort -u
}

# smoke stage entry point.
stage_smoke() {
  local shell_dir="${ARANEA_QML_SHELL_DIR:-/usr/share/omarchy/shell}" missing=()
  command -v quickshell >/dev/null || missing+=(quickshell)
  command -v sway >/dev/null || missing+=("sway (headless compositor)")
  command -v dbus-run-session >/dev/null || missing+=("dbus-run-session (dbus)")
  [[ -f "$shell_dir/Commons/qmldir" && -f "$shell_dir/Ui/qmldir" ]] || missing+=("Omarchy shell at $shell_dir")
  if ((${#missing[@]})); then
    printf 'SKIP: runtime QML smoke needs %s\n' "${missing[*]}"
    return 77
  fi

  local files
  mapfile -t files < <(smoke_entry_points)
  ((${#files[@]})) || return 0

  # Short path: Wayland socket paths are limited to 108 bytes.
  local run
  run="$(mktemp -d /tmp/aranea-smoke.XXXXXX)"
  chmod 700 "$run"
  mkdir -p "$run/home"
  smoke_write_harness "$run/harness" "$shell_dir"
  local joined
  joined="$(printf '%s:' "${files[@]}")"
  cat >"$run/client" <<EOF
#!/usr/bin/env bash
# Started by the headless sway below: run the harness, then stop sway.
SMOKE_FILES='${joined%:}' QT_QPA_PLATFORM=wayland timeout 30 quickshell -p '$run/harness/shell.qml' >'$run/client.log' 2>&1
echo "exit \$?" >>'$run/client.log'
swaymsg exit
EOF
  chmod +x "$run/client"
  printf 'exec %s\n' "$run/client" >"$run/sway.conf"
  env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    XDG_RUNTIME_DIR="$run" HOME="$run/home" XDG_CACHE_HOME="$run/cache" \
    XDG_STATE_HOME="$run/home/.local/state" XDG_CONFIG_HOME="$run/home/.config" \
    WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
    timeout 90 dbus-run-session -- sway -c "$run/sway.conf" >"$run/sway.log" 2>&1
  local sway_status=$?

  local status=0
  if [[ ! -s "$run/client.log" ]] || ! grep -q 'SMOKE-LOADED\|SMOKE-ERROR' "$run/client.log"; then
    echo "smoke harness did not run (sway exit $sway_status); logs kept in $run (rm -rf it when done)"
    return 1
  fi
  local client_exit
  client_exit="$(sed -n 's/^exit \([0-9]*\)$/\1/p' "$run/client.log" | tail -n1)"
  if [[ "$client_exit" != 0 ]]; then
    echo "quickshell exited ${client_exit:-without a status} (crash or timeout); logs kept in $run (rm -rf it when done)"
    return 1
  fi
  echo "smoke: ${#files[@]} entry points"
  local allow="$repo_root/tools/baselines/smoke-allow.txt" current
  current="$(mktemp)"
  smoke_problems "$run/client.log" >"$current"
  touch "$allow"
  if ((update_baselines)); then
    LC_ALL=C comm -12 <(LC_ALL=C sort -u "$allow") "$current" >"$allow.new"
    mv "$allow.new" "$allow"
  fi
  local new stale line
  new="$(LC_ALL=C comm -13 <(LC_ALL=C sort -u "$allow") "$current")"
  stale="$(LC_ALL=C comm -23 <(LC_ALL=C sort -u "$allow") "$current")"
  if [[ -n "$new" ]]; then
    while IFS= read -r line; do printf 'new runtime problem: %s\n' "$line"; done <<<"$new"
    status=1
  fi
  if [[ -n "$stale" ]]; then
    while IFS= read -r line; do printf 'stale smoke-allow entry: %s\n' "$line"; done <<<"$stale"
    status=1
  fi
  rm -f "$current"
  rm -rf "$run"
  return "$status"
}
