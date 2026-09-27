#!/usr/bin/env bash
set -euo pipefail

# Removes Aranea from this user account: its hooks, shell plugins and
# wallpaper timer, the files it manages (restoring what they replaced), the
# desktop settings it changed and its state. The theme folder stays; remove
# it with `omarchy theme remove aranea`. Asks first when interactive unless
# --yes; every step tolerates a missing target, so running it twice is safe.
#
# Usage: scripts/uninstall.sh [--dry-run] [--yes]

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/ownership.sh"

dry_run=0
assume_yes=0
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
state_root="$(aranea_ownership_root)"
hook_files=("$HOME/.config/omarchy/hooks/theme-set.d/theme-set" "$HOME/.config/omarchy/hooks/post-boot.d/post-boot")
unit_files=("$config_root/systemd/user/aranea-wallpaper-day-night.timer" "$config_root/systemd/user/aranea-wallpaper-day-night.service")

# Prints the usage text.
usage() {
  cat <<'USAGE'
Usage: scripts/uninstall.sh [--dry-run] [--yes]

Removes Aranea's hooks, shell plugins, wallpaper timer, managed files
(restoring what they replaced), saved desktop settings and state. The theme
folder stays: remove it with `omarchy theme remove aranea`.
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes) assume_yes=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# Whether HOOK is Aranea's copy (it carries the Aranea header); a user's own
# hook with the same name is left alone.
is_aranea_hook() {
  [[ -f "$1" ]] && grep -q '^# Aranea theme:' "$1"
}

# Removes Aranea's theme-set and post-boot hooks, so a later theme switch or
# login does not install Aranea again.
remove_hooks() {
  local hook
  for hook in "${hook_files[@]}"; do
    is_aranea_hook "$hook" && rm -f -- "$hook"
  done
  return 0
}

# Hands bar, menu, lock, OSD, polkit and notifications back to Omarchy,
# removes the araneadev.* plugin folders and restarts the shell.
remove_plugins() {
  "$repo_root/scripts/release-shell-config" "$config_root/omarchy/shell.json" >/dev/null 2>&1 || true
  rm -rf -- "$config_root/omarchy/plugins"/araneadev.*
  omarchy restart shell >/dev/null 2>&1 || true
}

# Stops and removes the wallpaper day/night timer and its service.
remove_timer() {
  systemctl --user disable --now aranea-wallpaper-day-night.timer >/dev/null 2>&1 || true
  rm -f -- "${unit_files[@]}"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# Writes back the desktop settings saved before Aranea first changed them.
restore_gsettings() {
  local saved name schema key
  command -v gsettings >/dev/null 2>&1 || return 0
  for saved in "$state_root/gsettings"/*; do
    [[ -f "$saved" ]] || continue
    name="${saved##*/}"
    schema="${name%.*}"
    key="${name##*.}"
    gsettings set "$schema" "$key" "$(<"$saved")" >/dev/null 2>&1 || true
  done
}

# Prints what a real run would do.
describe() {
  local hook plugin
  printf '%s\n' 'would remove Aranea:'
  for hook in "${hook_files[@]}"; do
    is_aranea_hook "$hook" && printf '  remove hook %s\n' "$hook"
  done
  for plugin in "$config_root/omarchy/plugins"/araneadev.*; do
    [[ -e "$plugin" ]] && printf '  remove plugin %s\n' "$plugin"
  done
  printf '  hand the shell back to Omarchy (release-shell-config)\n'
  printf '  stop and remove the wallpaper timer\n'
  if [[ -f "$(ownership_record)" ]]; then
    printf '  restore managed files:\n'
    sed 's/^/    /' "$(ownership_record)"
  fi
  printf '  restore saved desktop settings and remove %s\n' "$state_root"
  return 0
}

if ((dry_run)); then
  describe
  exit 0
fi

if ((! assume_yes)) && [[ -t 0 ]]; then
  read -r -p 'Remove Aranea from this account? [y/N] ' answer
  [[ "$answer" =~ ^[Yy]$ ]] || {
    printf '%s\n' 'Cancelled.'
    exit 0
  }
fi

remove_hooks
remove_plugins
remove_timer
[[ -f "$(ownership_record)" ]] && restore_managed_files
restore_gsettings
find "$data_root/icons/Aranea" "$data_root/icons/Aranea-icons" -depth -type d -empty -delete 2>/dev/null || true
rm -rf -- "$state_root"
printf '%s\n' 'Aranea removed. The theme folder stays; remove it with: omarchy theme remove aranea'
