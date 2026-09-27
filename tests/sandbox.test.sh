#!/usr/bin/env bash
# Contract for the test sandbox (tests/lib/sandbox.sh): every test runs with
# HOME, the XDG dirs and TMPDIR inside a throwaway root, side-effect commands
# replaced by logging stubs, and nothing left behind. No test may touch the
# real home, the running compositor or the running shell.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_home="$HOME"
real_tmp="${TMPDIR:-/tmp}"
source "$repo_root/tests/lib/sandbox.sh"

# --- every test sources the sandbox before doing anything else
for test_file in "$repo_root"/tests/*.test.sh; do
  if ! head -n 12 "$test_file" | grep -Fq "source \"\$repo_root/tests/lib/sandbox.sh\""; then
    echo "$(basename "$test_file") must source tests/lib/sandbox.sh in its first lines" >&2
    exit 1
  fi
  # Cleanup goes through sandbox_on_exit; a bare EXIT trap would replace the
  # sandbox's own cleanup.
  if grep -nE '^[[:space:]]*trap [^#]*EXIT' "$test_file"; then
    echo "$(basename "$test_file") sets its own EXIT trap; use sandbox_on_exit" >&2
    exit 1
  fi
  # Nothing is written into the repo tree.
  if grep -nE "\"[\$]repo_root/tests/[.][a-z-]+\"" "$test_file"; then
    echo "$(basename "$test_file") writes into the repo tree; use \$ARANEA_TEST_SANDBOX" >&2
    exit 1
  fi
done

# --- inside the sandbox
[[ -d "$ARANEA_TEST_SANDBOX" && "$ARANEA_TEST_SANDBOX" == "$real_tmp"/aranea-test.* ]]
[[ "$HOME" == "$ARANEA_TEST_SANDBOX"/* ]]
for var in XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR TMPDIR; do
  [[ "${!var}" == "$ARANEA_TEST_SANDBOX"/* ]] || { echo "$var escapes the sandbox: ${!var}" >&2; exit 1; }
  [[ -d "${!var}" ]]
done
[[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -z "${WAYLAND_DISPLAY:-}" && -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]
[[ -z "$(compgen -e | grep '^ARANEA_' | grep -v '^ARANEA_TEST_SANDBOX$' || true)" ]]
[[ "$(mktemp -d)" == "$ARANEA_TEST_SANDBOX"/* ]]

# Side-effect commands resolve to logging stubs.
for cmd in omarchy omarchy-shell hyprctl quickshell systemctl gsettings pkexec wtype wl-copy wl-paste \
  grim notify-send uwsm curl omarchy-theme-install omarchy-hyprland-session-locked kvantummanager \
  kitty foot alacritty firefox chromium code nvim xdg-open; do
  [[ "$(command -v "$cmd")" == "$repo_root/tests/guard-bin/$cmd" ]] || { echo "$cmd is not guarded: $(command -v "$cmd" || echo missing)" >&2; exit 1; }
done
hyprctl keyword animations:enabled false
omarchy-shell shell ping
grep -Fxq 'hyprctl keyword animations:enabled false' "$ARANEA_TEST_SANDBOX/guard.log"
grep -Fxq 'omarchy-shell shell ping' "$ARANEA_TEST_SANDBOX/guard.log"

# --- a canary write stays in the sandbox, and cleanup removes it
canary="aranea-sandbox-canary-$$"
sandbox_root="$(
  bash -c '
    set -euo pipefail
    repo_root="$1"
    source "$repo_root/tests/lib/sandbox.sh"
    mkdir -p "$HOME/.local/state/aranea"
    : > "$HOME/.local/state/aranea/$2"
    marker="$(mktemp)"
    sandbox_on_exit "rm -f \"$marker\""
    printf "%s\n" "$ARANEA_TEST_SANDBOX"
  ' _ "$repo_root" "$canary"
)"
[[ ! -e "$real_home/.local/state/aranea/$canary" ]] || { echo "canary reached the real home" >&2; exit 1; }
[[ ! -e "$sandbox_root" ]] || { echo "sandbox not removed: $sandbox_root" >&2; exit 1; }

# A failing test keeps its exit status through the sandbox cleanup.
status=0
bash -c 'repo_root="$1"; source "$repo_root/tests/lib/sandbox.sh"; exit 7' _ "$repo_root" || status=$?
[[ "$status" -eq 7 ]] || { echo "exit status lost: $status" >&2; exit 1; }

echo "sandbox contract passed"
