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
  rm -rf "$XDG_CONFIG_HOME" "${TMPDIR:?}/bin" "$TMPDIR/reloads" "$TMPDIR/reload-status" "$TMPDIR/configerrors.json" "$TMPDIR/configerrors.after.json" "$TMPDIR/cp.count" "$TMPDIR/PWNED"
  mkdir -p "$XDG_CONFIG_HOME/hypr" "$TMPDIR/bin"
  printf '%s\n' 'o.bind("SUPER + RETURN", "Terminal", "uwsm app -- kitty")' '-- a comment' \
    'o.bind("SUPER + CTRL + SHIFT + D", "Toggle Aranea health", "omarchy-shell shell toggle araneadev.health")' >"$file"
  printf '%s' "$default_binds" >"$TMPDIR/binds.json"
  cat >"$TMPDIR/bin/hyprctl" <<FAKE
#!/bin/bash
case "\$*" in
  "binds -j"|"-j binds") cat "$TMPDIR/binds.json" ;;
  "configerrors -j"|"-j configerrors")
    if [ -f "$TMPDIR/reloads" ] && [ -f "$TMPDIR/configerrors.after.json" ]; then cat "$TMPDIR/configerrors.after.json"
    else cat "$TMPDIR/configerrors.json" 2>/dev/null || echo '[""]'; fi ;;
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
  [[ $(reloads) == 2 ]]
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
  for tool in bash env jq awk cp mv mktemp tr sed grep cat dirname rm chmod tail head cmp wc flock readlink od; do
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
  cmp -n "$(stat -c %s "$TMPDIR/orig")" "$file" "$TMPDIR/orig"
  grep -q -e '^-- o.bind("SUPER + ALT + P", "x", "y") -- aranea:projects-switcher' "$file"
  [[ $(head -c 21 "$file") == 'o.bind("A", "a", "b")' ]]
  run remove
  jq -e '.ok and .data.removed == true' "$result" >/dev/null
  cmp "$file" "$TMPDIR/orig"
}

# Catch a failing rewrite installing a partial file or leaving a temp file.
rewrite_failure_keeps_file() {
  setup
  printf '#!/bin/sh\nexit 2\n' >"$TMPDIR/bin/awk"
  chmod +x "$TMPDIR/bin/awk"
  cp "$file" "$TMPDIR/orig"
  expect_code WRITE_FAILED add --key "SUPER + ALT + P"
  cmp "$file" "$TMPDIR/orig"
  [[ $(find "$(dirname "$file")" -name 'bindings.lua.*' ! -name '*.bak' | wc -l) == 0 ]]
}
# Catch a symlinked bindings file being replaced by a regular file.
symlink_survives() {
  setup
  mkdir -p "$ARANEA_TEST_SANDBOX/dotfiles"
  mv "$file" "$ARANEA_TEST_SANDBOX/dotfiles/bindings.lua"
  ln -s "$ARANEA_TEST_SANDBOX/dotfiles/bindings.lua" "$file"
  cp "$ARANEA_TEST_SANDBOX/dotfiles/bindings.lua" "$TMPDIR/orig"
  run add --key "SUPER + ALT + P"
  jq -e '.ok' "$result" >/dev/null
  [[ -L $file ]]
  grep -q -e "$marker" "$ARANEA_TEST_SANDBOX/dotfiles/bindings.lua"
  [[ -f $file.aranea.bak && ! -e $ARANEA_TEST_SANDBOX/dotfiles/bindings.lua.aranea.bak ]]
  run remove
  [[ -L $file ]]
  cmp "$ARANEA_TEST_SANDBOX/dotfiles/bindings.lua" "$TMPDIR/orig"
  echo 1 >"$TMPDIR/reload-status"
  expect_code RELOAD_FAILED add --key "SUPER + ALT + P"
  [[ -L $file ]]
  cmp "$ARANEA_TEST_SANDBOX/dotfiles/bindings.lua" "$TMPDIR/orig"
}
# Catch a Lua config error that reload does not report being kept.
config_errors_restore() {
  setup
  cp "$file" "$TMPDIR/orig"
  printf '%s' '["", "bindings.lua:4: syntax error"]' >"$TMPDIR/configerrors.after.json"
  expect_code RELOAD_FAILED add --key "SUPER + ALT + P"
  jq -e '.error.message | contains("syntax error")' "$result" >/dev/null
  cmp "$file" "$TMPDIR/orig"
  [[ $(reloads) == 2 ]]
}
# Catch two runs overlapping.
lock_gives_busy() {
  setup
  export ARANEA_KEYBIND_LOCK_WAIT=1
  cp "$file" "$TMPDIR/orig"
  (
    flock 9
    sleep 4
  ) 9>"$XDG_RUNTIME_DIR/aranea-keybind.lock" &
  sleep 0.5
  expect_code BUSY add --key "SUPER + ALT + P"
  expect_code BUSY remove
  cmp "$file" "$TMPDIR/orig"
  wait
}
# Catch a managed line with trailing spaces being missed.
trailing_whitespace_is_managed() {
  setup
  printf '%s  \t\n' "$line_p" >>"$file"
  run status
  jq -e '.data.bound == true' "$result" >/dev/null
  run add --key "SUPER + ALT + O"
  [[ $(managed_count) == 1 ]]
}
# Catch an empty description hiding what a taken key does, and submap binds counting.
conflict_details() {
  setup
  printf '%s' '[{"modmask":72,"key":"P","description":"","dispatcher":"exec","arg":"firefox"}]' >"$TMPDIR/binds.json"
  expect_code KEY_TAKEN add --key "SUPER + ALT + P"
  jq -e '.error.message | contains("firefox")' "$result" >/dev/null
  printf '%s' '[{"modmask":72,"key":"P","submap":"resize","description":"Grow","dispatcher":"exec","arg":"x"}]' >"$TMPDIR/binds.json"
  run add --key "SUPER + ALT + P"
  jq -e '.ok' "$result" >/dev/null
}
# Catch an unknown subcommand reporting a key error.
unknown_subcommand() {
  setup
  expect_code INVALID_REQUEST bogus
}

# Catch a failed restore exiting silently, or skipping the second reload.
restore_failure_reports() {
  setup
  # shellcheck disable=SC2016
  printf '#!/bin/sh\nn=$(cat "%s" 2>/dev/null || echo 0)\necho $((n+1)) >"%s"\n[ "$n" -ge 1 ] && exit 1\nexec %s "$@"\n' "$TMPDIR/cp.count" "$TMPDIR/cp.count" "$(command -v cp)" >"$TMPDIR/bin/cp"
  chmod +x "$TMPDIR/bin/cp"
  echo 1 >"$TMPDIR/reload-status"
  expect_code RELOAD_FAILED add --key "SUPER + ALT + P"
  jq -e --arg b "$file.aranea.bak" '.error.message | contains($b)' "$result" >/dev/null
  [[ $(reloads) == 2 ]]
  [[ $(find "$(dirname "$file")" -name 'bindings.lua.*' ! -name '*.bak' | wc -l) == 0 ]]
}
# Catch errors that existed before the change blocking it, or being unreported.
preexisting_errors_do_not_block() {
  setup
  printf '%s' '["", "old problem"]' >"$TMPDIR/configerrors.json"
  run add --key "SUPER + ALT + P"
  jq -e '.ok and .data.preexistingErrors == 1' "$result" >/dev/null
  run remove
  jq -e '.ok and .data.preexistingErrors == 1' "$result" >/dev/null
}
# Catch unreadable config errors being treated as success.
unreadable_config_errors_fail() {
  setup
  cp "$file" "$TMPDIR/orig"
  printf '%s' 'not json' >"$TMPDIR/configerrors.after.json"
  expect_code RELOAD_FAILED add --key "SUPER + ALT + P"
  jq -e '.error.message | contains("could not read config errors")' "$result" >/dev/null
  cmp "$file" "$TMPDIR/orig"
  [[ $(reloads) == 2 ]]
}
# Catch the lock landing in /tmp, or an unusable lock path exiting silently.
lock_location() {
  setup
  (
    unset XDG_RUNTIME_DIR
    run add --key "SUPER + ALT + P"
    jq -e '.ok' "$result" >/dev/null
  )
  [[ -f $XDG_STATE_HOME/aranea/aranea-keybind.lock && $(stat -c %a "$XDG_STATE_HOME/aranea") == 700 ]]
  XDG_RUNTIME_DIR="$ARANEA_TEST_SANDBOX/nowhere" expect_code BUSY add --key "SUPER + ALT + O"
}
# Catch an unknown add option reporting a key error.
unknown_add_option() {
  setup
  expect_code INVALID_REQUEST add --bogus
}

cases=(add_writes_one_marked_line readd_replaces remove_deletes_only_ours status_reports conflict_detection_normalises invalid_keys reload_failure_restores missing_file_creates_nothing no_hyprctl odd_files_keep_their_bytes rewrite_failure_keeps_file symlink_survives config_errors_restore lock_gives_busy trailing_whitespace_is_managed conflict_details unknown_subcommand restore_failure_reports preexisting_errors_do_not_block unreadable_config_errors_fail lock_location unknown_add_option)
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
