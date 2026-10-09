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
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/paths.sh"
# shellcheck disable=SC1091
source "$repo_root/branding/brand.env"
source "$repo_root/scripts/lib/ownership.sh"
source "$repo_root/scripts/lib/json-events.sh"

dry_run=0
assume_yes=0
json_mode=0
scope=integration
replacement_theme=''
json_started_sent=0
config_root="$(xdg_config_home)"
# Omarchy, its hooks and deploy-plugins-safely use this fixed path.
omarchy_config="$HOME/.config/omarchy"
data_root="$(xdg_data_home)"
state_root="$(aranea_ownership_root)"
hook_files=("$omarchy_config/hooks/theme-set.d/theme-set" "$omarchy_config/hooks/post-boot.d/post-boot")
# The desktop settings Aranea changes (install-integration save_gsetting).
gsetting_keys=("org.gnome.desktop.interface cursor-theme" "org.gnome.desktop.interface icon-theme")
unit_files=("$config_root/systemd/user/aranea-wallpaper-day-night.timer" "$config_root/systemd/user/aranea-wallpaper-day-night.service")

# Prints the usage text.
usage() {
  cat <<'USAGE'
Usage: scripts/uninstall.sh [--dry-run] [--yes] [--json]
  [--scope integration|complete] [--replacement-theme THEME]

Removes Aranea's hooks, shell plugins, wallpaper timer, managed files
(restoring what they replaced), saved desktop settings and state. The theme
folder stays by default; use --scope complete to also remove it.
Both scopes remove project registrations, preserving repository folders
and applications opened from them.
USAGE
}

# Emits a machine-readable failure or the existing human error and exits.
fail_uninstall() {
  local status="$1"
  local code="$2"
  local message="$3"
  if ((json_mode && json_started_sent)); then
    json_completed uninstall failed "$code" "$message"
  else
    printf '%s\n' "$message" >&2
  fi
  exit "$status"
}

while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes) assume_yes=1 ;;
    --json) json_mode=1 ;;
    --scope)
      (($# >= 2)) || fail_uninstall 2 invalid_usage '--scope requires integration or complete'
      scope="$2"
      shift
      ;;
    --replacement-theme)
      (($# >= 2)) || fail_uninstall 2 invalid_usage '--replacement-theme requires a theme name'
      replacement_theme="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      if ((json_mode)); then
        fail_uninstall 2 invalid_usage "Unknown option: $1"
      fi
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if ((json_mode)) && ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "$BRAND_NAME uninstall: --json requires jq." >&2
  exit 4
fi

case "$scope" in
  integration | complete) ;;
  *) fail_uninstall 2 invalid_scope "Unknown uninstall scope: $scope" ;;
esac

if ((json_mode)); then
  dry_run_json=false
  assume_yes_json=false
  ((dry_run)) && dry_run_json=true
  ((assume_yes)) && assume_yes_json=true
  start_data="$(jq -cn \
    --arg scope "$scope" \
    --arg replacement_theme "$replacement_theme" \
    --argjson dry_run "$dry_run_json" \
    --argjson assume_yes "$assume_yes_json" \
    '{scope: $scope, replacement_theme: $replacement_theme, dry_run: $dry_run, assume_yes: $assume_yes}')"
  json_started uninstall "$start_data"
  json_started_sent=1
fi

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
# removes the araneadev.* plugin folders and restarts the shell (only when
# there was an Aranea plugin to remove).
remove_plugins() {
  local plugin found=0
  "$repo_root/scripts/release-shell-config" "$omarchy_config/shell.json" >/dev/null 2>&1 || true
  for plugin in "$omarchy_config/plugins"/araneadev.*; do
    [[ -e "$plugin" ]] || continue
    rm -rf -- "$plugin"
    found=1
  done
  ((found)) && { omarchy restart shell >/dev/null 2>&1 || true; }
  return 0
}

# Stops and removes the wallpaper day/night timer and its service, when
# Aranea installed them.
remove_timer() {
  local unit found=0
  for unit in "${unit_files[@]}"; do
    [[ -e "$unit" ]] && found=1
  done
  ((found)) || return 0
  systemctl --user disable --now aranea-wallpaper-day-night.timer >/dev/null 2>&1 || true
  rm -f -- "${unit_files[@]}"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# Writes back the desktop settings saved before Aranea first changed them;
# a setting with no saved value that still names Aranea's theme is reset to
# its default (an install from before values were saved).
restore_gsettings() {
  local entry schema key saved current
  command -v gsettings >/dev/null 2>&1 || return 0
  for entry in "${gsetting_keys[@]}"; do
    read -r schema key <<<"$entry"
    saved="$state_root/gsettings/$schema.$key"
    if [[ -f "$saved" && "$(<"$saved")" != "'Aranea'" && "$(<"$saved")" != "'Aranea-icons'" ]]; then
      gsettings set "$schema" "$key" "$(<"$saved")" >/dev/null 2>&1 || true
      continue
    fi
    current="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
    if [[ -f "$saved" || "$current" == "'Aranea'" || "$current" == "'Aranea-icons'" ]]; then
      gsettings reset "$schema" "$key" >/dev/null 2>&1 || true
    fi
  done
}

# Removes Aranea's state. Files the user customised stay in the ledger with
# their backups (restore_managed_files keeps them), so those are kept.
remove_state() {
  local entry
  if [[ -s "$(ownership_record)" ]]; then
    for entry in "$state_root"/* "$state_root"/.[!.]*; do
      [[ -e "$entry" ]] || continue
      [[ "$entry" == "$(ownership_record)" || "$entry" == "$state_root/backups" ]] && continue
      rm -rf -- "$entry"
    done
    printf 'kept the originals of files you changed in %s\n' "$state_root/backups"
  else
    rm -rf -- "$state_root"
  fi
}

# Prints what a real run would do.
describe() {
  local hook plugin
  printf '%s\n' 'would remove Aranea:'
  for hook in "${hook_files[@]}"; do
    is_aranea_hook "$hook" && printf '  remove hook %s\n' "$hook"
  done
  for plugin in "$omarchy_config/plugins"/araneadev.*; do
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
  if ((json_mode)); then
    json_step uninstall ok remove-hooks 'would remove Aranea hooks'
    json_step uninstall ok remove-plugins 'would remove Aranea plugins'
    json_step uninstall ok remove-timer 'would stop and remove the wallpaper timer'
    json_step uninstall ok restore-managed-files 'would restore managed files'
    json_step uninstall ok restore-settings 'would restore saved desktop settings'
    json_step uninstall ok remove-state 'would remove Aranea state'
    if [[ "$scope" == complete ]]; then
      json_step uninstall ok remove-theme 'would remove the aranea theme directory'
    fi
    json_completed uninstall ok '' 'dry-run completed'
  else
    describe
  fi
  exit 0
fi

if ((! assume_yes)) && [[ -t 0 ]]; then
  read -r -p 'Remove Aranea from this account? [y/N] ' answer
  [[ "$answer" =~ ^[Yy]$ ]] || {
    printf '%s\n' 'Cancelled.'
    exit 0
  }
fi

if ((json_mode)); then json_step uninstall running remove-hooks 'remove Aranea hooks'; fi
remove_hooks
if ((json_mode)); then json_step uninstall ok remove-hooks 'Aranea hooks removed'; fi
if ((json_mode)); then json_step uninstall running remove-plugins 'remove Aranea plugins'; fi
remove_plugins
if ((json_mode)); then json_step uninstall ok remove-plugins 'Aranea plugins removed'; fi
if ((json_mode)); then json_step uninstall running remove-timer 'remove wallpaper timer'; fi
remove_timer
if ((json_mode)); then json_step uninstall ok remove-timer 'wallpaper timer removed'; fi
if ((json_mode)); then json_step uninstall running restore-managed-files 'restore managed files'; fi
[[ -f "$(ownership_record)" ]] && restore_managed_files
if ((json_mode)); then json_step uninstall ok restore-managed-files 'managed files restored'; fi
if ((json_mode)); then json_step uninstall running restore-settings 'restore desktop settings'; fi
restore_gsettings
if ((json_mode)); then json_step uninstall ok restore-settings 'desktop settings restored'; fi
find "$data_root/icons/Aranea" "$data_root/icons/Aranea-icons" -depth -type d -empty -delete 2>/dev/null || true
remove_teams_override /usr/share/applications/teams-for-linux.desktop "$data_root/applications/teams-for-linux.desktop"
# Aranea's own settings (the wallpaper schedule).
rm -rf -- "$config_root/aranea"
if ((json_mode)); then json_step uninstall running remove-state 'remove Aranea state'; fi
remove_state
if ((json_mode)); then json_step uninstall ok remove-state 'Aranea state removed'; fi

if [[ "$scope" == complete ]]; then
  current_theme="$(omarchy theme current 2>/dev/null || true)"
  if [[ "$current_theme" == Aranea || "$current_theme" == aranea ]]; then
    if [[ -n "$replacement_theme" ]]; then
      omarchy theme set "$replacement_theme"
    elif ((json_mode)); then
      if ((! assume_yes)); then
        json_prompt uninstall replacement-theme 'choose a replacement theme before complete removal'
        json_completed uninstall cancelled prompt_required 'complete removal cancelled'
        exit 3
      fi
    elif [[ -t 0 ]]; then
      read -r -p 'Enter a replacement theme before removing Aranea: ' replacement_theme
      [[ -n "$replacement_theme" ]] || {
        printf '%s\n' 'Cancelled.'
        exit 3
      }
      omarchy theme set "$replacement_theme"
    else
      printf '%s\n' 'Complete removal requires --replacement-theme when Aranea is active.' >&2
      exit 3
    fi
  fi
  if ((json_mode)); then json_step uninstall running remove-theme 'remove aranea theme directory'; fi
  omarchy theme remove aranea
  if ((json_mode)); then json_step uninstall ok remove-theme 'aranea theme directory removed'; fi
fi

if ((json_mode)); then
  json_completed uninstall ok '' "$BRAND_NAME removed."
else
  if [[ "$scope" == complete ]]; then
    printf '%s\n' "$BRAND_NAME removed completely."
  else
    printf '%s\n' "$BRAND_NAME removed. The theme folder stays; remove it with: omarchy theme remove aranea"
  fi
fi
