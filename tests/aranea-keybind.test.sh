#!/usr/bin/env bash
# aranea-keybind against a sandboxed bindings.lua and a fake hyprctl.
# Cases are invoked by name in the loop below.
# shellcheck disable=SC2329
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
helper="$repo_root/scripts/aranea-keybind"
export XDG_CONFIG_HOME="$ARANEA_TEST_SANDBOX/cfg"
file="$XDG_CONFIG_HOME/hypr/bindings.lua"
result="$TMPDIR/result.json"
marker='-- aranea:projects-switcher'
line_p='o.bind("SUPER + ALT + P", "Aranea project switcher", "omarchy-shell shell toggle araneadev.projects '"'"'{\"mode\":\"switcher\"}'"'"'") -- aranea:projects-switcher'
default_binds='[{"modmask":64,"key":"Return","description":"Terminal","dispatcher":"exec","arg":"uwsm app -- kitty"},{"modmask":69,"key":"D","description":"Toggle Aranea health","dispatcher":"exec","arg":"omarchy-shell shell toggle araneadev.health"}]'
failures=0
# Fresh bindings file, fake hyprctl first on PATH, default bind list.
setup() {
  rm -rf "$XDG_CONFIG_HOME" "${TMPDIR:?}/bin" "$TMPDIR/reloads" "$TMPDIR/reload-status" "$TMPDIR/PWNED"
  mkdir -p "$XDG_CONFIG_HOME/hypr" "$TMPDIR/bin"
  printf '%s\n' 'o.bind("SUPER + RETURN", "Terminal", "uwsm app -- kitty")' '-- a comment' \
    'o.bind("SUPER + CTRL + SHIFT + D", "Toggle Aranea health", "omarchy-shell shell toggle araneadev.health")' >"$file"
  printf '%s' "$default_binds" >"$TMPDIR/binds.json"
  cat >"$TMPDIR/bin/hyprctl" <<FAKE
#!/bin/bash
case "\$*" in
  "binds -j"|"-j binds") cat "$TMPDIR/binds.json" ;;
  reload) echo x >>"$TMPDIR/reloads"; exit "\$(cat "$TMPDIR/reload-status" 2>/dev/null || echo 0)" ;;
esac
FAKE
  chmod +x "$TMPDIR/bin/hyprctl"
  PATH="$TMPDIR/bin:$PATH"
}
# Run the helper and save its envelope; the exit code is the helper's.
run() { "$helper" "$@" --json >"$result"; }
# Assert the helper fails with this error code and a recovery hint.
expect_code() { ! run "${@:2}" && jq -e --arg c "$1" '.ok == false and .data == null and .error.code == $c and (.error.recovery|length > 0)' "$result" >/dev/null; }
# Number of reload calls so far.
reloads() { if [[ -f $TMPDIR/reloads ]]; then wc -l <"$TMPDIR/reloads"; else echo 0; fi; }
# Count of lines carrying the marker.
managed_count() { grep -c -e "$marker" "$file" || true; }

# Catch add changing anything but one exact managed line.
add_writes_one_marked_line() {
  setup
  grep -v -e "$marker" "$file" >"$TMPDIR/before"
  run add --key "SUPER + ALT + P"
  jq -e '.ok and .data.bound == true and .data.key == "SUPER + ALT + P"' "$result" >/dev/null
  [[ $(managed_count) == 1 ]]
  [[ $(grep -e "$marker" "$file") == "$line_p" ]]
  grep -v -e "$marker" "$file" | cmp - "$TMPDIR/before"
  [[ $(reloads) == 1 ]]
}
# Catch a second add leaving two managed lines.
readd_replaces() {
  setup
  run add --key "SUPER + ALT + P"
  run add --key "SUPER + ALT + O"
  [[ $(managed_count) == 1 ]]
  grep -e "$marker" "$file" | grep -q 'SUPER + ALT + O'
}
# Catch remove touching user lines, or reloading when nothing was removed.
remove_deletes_only_ours() {
  setup
  cp "$file" "$TMPDIR/orig"
  run add --key "SUPER + ALT + P"
  run remove
  jq -e '.ok and .data.removed == true' "$result" >/dev/null
  cmp "$file" "$TMPDIR/orig"
  local n
  n=$(reloads)
  run remove
  jq -e '.ok and .data.removed == false' "$result" >/dev/null
  [[ $(reloads) == "$n" ]]
}
# Catch status disagreeing with the file.
status_reports() {
  setup
  run status
  jq -e '.ok and .data.bound == false and .data.key == null' "$result" >/dev/null
  run add --key "SUPER + ALT + P"
  run status
  jq -e '.ok and .data.bound == true and .data.key == "SUPER + ALT + P"' "$result" >/dev/null
}
# Catch a conflict missed because of case, spacing or modmask bits, or our own bind blocking us.
conflict_detection_normalises() {
  setup
  printf '%s' '[{"modmask":72,"key":"p","description":"Something","dispatcher":"exec","arg":"x"}]' >"$TMPDIR/binds.json"
  cp "$file" "$TMPDIR/orig"
  expect_code KEY_TAKEN add --key "super+alt+p"
  jq -e '.error.message | contains("Something")' "$result" >/dev/null
  cmp "$file" "$TMPDIR/orig"
  printf '%s' '[{"modmask":72,"key":"P","description":"Aranea project switcher","dispatcher":"exec","arg":"omarchy-shell shell toggle araneadev.projects x"}]' >"$TMPDIR/binds.json"
  run add --key "SUPER + ALT + P"
  jq -e '.ok' "$result" >/dev/null
}
# Catch keys outside the grammar being accepted, or reaching a shell.
invalid_keys() {
  setup
  local key
  # shellcheck disable=SC2016
  for key in "P" "SUPER + " "SUPER + ALT + P + Q" "HYPER + P" "SUPER + ;" 'SUPER + $(touch PWNED)'; do
    expect_code INVALID_KEY add --key "$key"
  done
  [[ ! -e PWNED && ! -e $TMPDIR/PWNED ]]
}
# Catch a failed reload leaving the new file in place.
reload_failure_restores() {
  setup
  local before
  before=$(sha256sum <"$file")
  echo 1 >"$TMPDIR/reload-status"
  expect_code RELOAD_FAILED add --key "SUPER + ALT + P"
  [[ $(sha256sum <"$file") == "$before" ]]
  [[ -f $file.aranea.bak ]]
}
# Catch the helper creating a bindings file.
missing_file_creates_nothing() {
  setup
  rm "$file"
  expect_code NO_BINDINGS_FILE add --key "SUPER + ALT + P"
  [[ ! -e $file ]]
}
# Catch a missing hyprctl being ignored.
no_hyprctl() {
  setup
  local bare="$TMPDIR/bare" tool
  mkdir -p "$bare"
  for tool in bash env jq awk cp mv mktemp tr sed grep cat dirname rm chmod tail head cmp wc; do
    ln -s "$(command -v "$tool")" "$bare/$tool"
  done
  cp "$file" "$TMPDIR/orig"
  if PATH="$bare" "$helper" add --key "SUPER + ALT + P" --json >"$result"; then return 1; fi
  jq -e '.ok == false and .error.code == "HYPRCTL_UNAVAILABLE"' "$result" >/dev/null
  cmp "$file" "$TMPDIR/orig"
}
# Catch CRLF, a missing final newline or a commented copy being mangled.
odd_files_keep_their_bytes() {
  setup
  printf 'o.bind("A", "a", "b")\r\n-- o.bind("SUPER + ALT + P", "x", "y") -- aranea:projects-switcher\r\nlast line' >"$file"
  cp "$file" "$TMPDIR/orig"
  run add --key "SUPER + ALT + P"
  jq -e '.ok' "$result" >/dev/null
  [[ $(grep -c -e '^o\.bind.*-- aranea:projects-switcher' "$file") == 1 ]]
  [[ $(head -c "$(stat -c %s "$TMPDIR/orig")" "$file" | tr -d '\r\n') == "$(tr -d '\r\n' <"$TMPDIR/orig")" ]]
  grep -q -e '^-- o.bind("SUPER + ALT + P", "x", "y") -- aranea:projects-switcher' "$file"
  [[ $(head -c 21 "$file") == 'o.bind("A", "a", "b")' ]]
  run remove
  jq -e '.ok and .data.removed == true' "$result" >/dev/null
  cmp "$file" "$TMPDIR/orig"
}

cases=(add_writes_one_marked_line readd_replaces remove_deletes_only_ours status_reports conflict_detection_normalises invalid_keys reload_failure_restores missing_file_creates_nothing no_hyprctl odd_files_keep_their_bytes)
if (($#)); then cases=("$@"); fi
for case_name in "${cases[@]}"; do
  set +e
  (
    set -e
    "$case_name"
  )
  status=$?
  set -e
  if ((status == 0)); then printf 'PASS %s\n' "$case_name"; else
    printf 'FAIL %s\n' "$case_name"
    failures=$((failures + 1))
  fi
done
exit "$((failures > 0))"
