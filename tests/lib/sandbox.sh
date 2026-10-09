#!/usr/bin/env bash
# Test sandbox, sourced by every tests/*.test.sh right after it sets
# repo_root. It gives the test a throwaway root and points HOME, the XDG dirs
# and TMPDIR into it, so nothing a test (or a script it runs) writes can reach
# the real home. Inherited ARANEA_* variables are cleared so scripts start
# from their defaults, the session sockets are unset so no real compositor,
# Wayland session or D-Bus is reachable, and tests/guard-bin is put first on
# PATH so side-effect commands (hyprctl, omarchy-shell, systemctl, …) only log
# their arguments to "$ARANEA_TEST_SANDBOX/guard.log". Tests that need a
# command to answer something specific put tests/fake-bin in front.
#
# The root is removed on exit, with the test's exit status kept. Every
# mktemp lands inside the root (TMPDIR), so temp files need no cleanup of
# their own; register anything else with sandbox_on_exit instead of
# `trap … EXIT`.

sandbox_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Start from the defaults: no inherited ARANEA_* overrides. The values are
# kept for a test that deliberately honours one (see sandbox_inherited_value).
declare -gA sandbox_inherited=()
for sandbox_var in $(compgen -e | grep '^ARANEA_' || true); do
  sandbox_inherited[$sandbox_var]="${!sandbox_var}"
  unset "$sandbox_var"
done
unset sandbox_var

ARANEA_TEST_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aranea-test.XXXXXX")"
export ARANEA_TEST_SANDBOX

export HOME="$ARANEA_TEST_SANDBOX/home"
# Provider adapters must never follow an inherited host configuration root.
export CODEX_HOME="$HOME/.codex"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="$ARANEA_TEST_SANDBOX/run"
export TMPDIR="$ARANEA_TEST_SANDBOX/tmp"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$TMPDIR" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS

sandbox_guard_bin="$(cd "$sandbox_lib_dir/../guard-bin" && pwd)"
export PATH="$sandbox_guard_bin:$PATH"

sandbox_exit_commands=()

# Prints the value NAME (an ARANEA_* variable) had before the sandbox cleared
# it, or nothing; for tests that deliberately honour a setting (the QML
# behaviour runner reads ARANEA_QML_SHELL_DIR and ARANEA_CHECK_REQUIRE_ALL).
sandbox_inherited_value() {
  printf '%s' "${sandbox_inherited[$1]:-}"
}

# Registers a command to run when the test exits, before the sandbox root is
# removed. Commands run in registration order.
sandbox_on_exit() {
  sandbox_exit_commands+=("$1")
}

# EXIT handler: runs the registered cleanup, removes the root and keeps the
# test's exit status.
sandbox_cleanup() {
  local status=$?
  local command
  for command in "${sandbox_exit_commands[@]}"; do
    eval "$command" || true
  done
  rm -rf "$ARANEA_TEST_SANDBOX"
  return "$status"
}
trap sandbox_cleanup EXIT
