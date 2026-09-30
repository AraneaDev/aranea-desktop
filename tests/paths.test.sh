#!/usr/bin/env bash
# Contract for scripts/lib/paths.sh: the XDG base directories fall back to
# their standard defaults, Aranea's state directory honours ARANEA_STATE_ROOT,
# and no script or tool outside the library spells out its own XDG fallback.
# hooks/ are exempt: Omarchy runs the installed hook copies even when the
# theme directory (and so the library) is gone.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/paths.sh"

# --- the sandbox sets every XDG variable
[[ "$(xdg_state_home)" == "$XDG_STATE_HOME" ]]
[[ "$(xdg_config_home)" == "$XDG_CONFIG_HOME" ]]
[[ "$(xdg_data_home)" == "$XDG_DATA_HOME" ]]
[[ "$(aranea_state_root)" == "$XDG_STATE_HOME/aranea" ]]
[[ "$(ARANEA_STATE_ROOT=/elsewhere aranea_state_root)" == /elsewhere ]]

# --- unset or empty XDG variables fall back to the standard directories
[[ "$(XDG_STATE_HOME='' xdg_state_home)" == "$HOME/.local/state" ]]
[[ "$(XDG_CONFIG_HOME='' xdg_config_home)" == "$HOME/.config" ]]
[[ "$(XDG_DATA_HOME='' xdg_data_home)" == "$HOME/.local/share" ]]
# shellcheck disable=SC2016 # the inner script expands $1 itself
[[ "$(env -u XDG_STATE_HOME bash -c 'source "$1"; aranea_state_root' _ "$repo_root/scripts/lib/paths.sh")" == "$HOME/.local/state/aranea" ]]

# --- one definition: no other script or tool spells out an XDG fallback
if grep -rnE '\$\{XDG_(STATE|CONFIG|DATA)_HOME:-' "$repo_root/scripts" "$repo_root/tools" "$repo_root/installer" |
  grep -v "^$repo_root/scripts/lib/paths.sh:"; then
  echo "use scripts/lib/paths.sh instead of a local XDG fallback" >&2
  exit 1
fi

echo "paths contract passed"
