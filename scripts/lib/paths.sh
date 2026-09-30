#!/usr/bin/env bash
# Directory roots shared by Aranea's scripts, so every script honours the same
# overrides: the XDG base directory variables with their standard fallbacks,
# and ARANEA_STATE_ROOT for Aranea's own state directory. Sourced, not run.

# Prints the XDG state directory ($XDG_STATE_HOME, else ~/.local/state).
xdg_state_home() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# Prints the XDG config directory ($XDG_CONFIG_HOME, else ~/.config).
xdg_config_home() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# Prints the XDG data directory ($XDG_DATA_HOME, else ~/.local/share).
xdg_data_home() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

# Prints Aranea's state directory ($ARANEA_STATE_ROOT, else <state>/aranea).
aranea_state_root() {
  printf '%s\n' "${ARANEA_STATE_ROOT:-$(xdg_state_home)/aranea}"
}
