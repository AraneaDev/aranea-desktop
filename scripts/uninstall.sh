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
source "$repo_root/scripts/lib/project-actions.sh"

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
project_state_root="$(aranea_state_root)"
hook_files=("$omarchy_config/hooks/theme-set.d/theme-set" "$omarchy_config/hooks/post-boot.d/post-boot")
# The desktop settings Aranea changes (install-integration save_gsetting).
gsetting_keys=("org.gnome.desktop.interface cursor-theme" "org.gnome.desktop.interface icon-theme" "org.gnome.desktop.interface font-name" "org.gnome.desktop.interface text-scaling-factor")
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

# Native effects cannot retain the install/removal mutex after this script exits.
lifecycle_effect() (
  [[ -z ${dispatch_fd:-} ]] || exec {dispatch_fd}>&-
  "$@"
)

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
  ((found)) && { lifecycle_effect omarchy restart shell >/dev/null 2>&1 || true; }
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
  lifecycle_effect systemctl --user disable --now aranea-wallpaper-day-night.timer >/dev/null 2>&1 || true
  rm -f -- "${unit_files[@]}"
  lifecycle_effect systemctl --user daemon-reload >/dev/null 2>&1 || true
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
    if [[ "$key" == font-name || "$key" == text-scaling-factor ]]; then
      [[ -f "$saved.applied" ]] || continue
      current="$(lifecycle_effect gsettings get "$schema" "$key" 2>/dev/null || true)"
      [[ "$current" == "$(cat "$saved.applied")" ]] || continue
    fi
    if [[ -f "$saved" && "$(<"$saved")" != "'Aranea'" && "$(<"$saved")" != "'Aranea-icons'" ]]; then
      lifecycle_effect gsettings set "$schema" "$key" "$(<"$saved")" >/dev/null 2>&1 || true
      continue
    fi
    current="$(lifecycle_effect gsettings get "$schema" "$key" 2>/dev/null || true)"
    if [[ -f "$saved" || "$current" == "'Aranea'" || "$current" == "'Aranea-icons'" ]]; then
      lifecycle_effect gsettings reset "$schema" "$key" >/dev/null 2>&1 || true
    fi
  done
}

# Remove only exact commands owned by this installation; unsafe settings remain untouched.
remove_agent_adapters() {
  local provider config
  for provider in claude codex; do
    if [[ "$provider" == claude ]]; then config="$HOME/.claude/settings.json"; else config="${CODEX_HOME:-$HOME/.codex}/hooks.json"; fi
    [[ -e "$config" || -L "$config" ]] || continue
    if ! "$repo_root/scripts/aranea-agent-adapter" remove "$provider" >/dev/null; then
      printf 'Agent adapter cleanup refused for %s (%s). Restore this theme at %s, then run its scripts/aranea-agent-adapter remove %s; review only the exact aranea-agent-hook command in this file. Provider settings were preserved.\n' "$provider" "$config" "$repo_root" "$provider" >&2
    fi
  done
}

# A receipt is not kill authority without exact live PID/start/boot/executable/argv proof.
remove_agent_helpers() {
  local root="$project_state_root/agent-heartbeats" record pid start stat boot key
  local -a argv
  [[ -d "$root" && ! -L "$root" ]] || return 0
  boot=$(cat /proc/sys/kernel/random/boot_id)
  for record in "$root"/*.json; do
    [[ -f "$record" && ! -L "$record" ]] || continue
    pid=$(jq -er '.pid | select(type=="number" and .>1 and floor==.)' "$record" 2>/dev/null) || continue
    [[ -r "/proc/$pid/stat" && -r "/proc/$pid/cmdline" ]] || continue
    stat=$(cat "/proc/$pid/stat" 2>/dev/null) || continue
    start=$(awk '{print $20}' <<<"${stat##*) }")
    jq -e --arg start "$start" --arg boot "$boot" '.startTime==$start and .bootId==$boot' "$record" >/dev/null 2>&1 || continue
    [[ $(readlink -f -- "/proc/$pid/exe") == "$(readlink -f /bin/bash)" ]] || continue
    argv=()
    mapfile -d '' -t argv <"/proc/$pid/cmdline" || continue
    [[ ${#argv[@]} == 8 && ${argv[0]} == /bin/bash && ${argv[1]} == "$repo_root/scripts/aranea-agent-heartbeat" ]] || continue
    jq -e --arg provider "${argv[2]}" --arg session "${argv[3]}" --arg epoch "${argv[4]}" --arg providerPid "${argv[5]}" --arg providerStart "${argv[6]}" --arg boot "${argv[7]}" '.provider==$provider and .providerSessionId==$session and .producerEpoch==$epoch and (.providerProcess.pid|tostring)==$providerPid and .providerProcess.startTime==$providerStart and .bootId==$boot' "$record" >/dev/null 2>&1 || continue
    key=$(printf '%s\n' "${argv[2]}" "${argv[3]}" "${argv[4]}" | sha256sum | cut -d' ' -f1)
    [[ "$record" == "$root/$key.json" ]] || continue
    kill -TERM "$pid" 2>/dev/null || true
  done
  # Deleting the receipt also prevents a sleeping helper from reporting again.
  rm -rf -- "$root"
}

# Delete owned state while preserving the three exact stable coordination inodes and
# only its ancestor directories. Existing customised-file backups retain scope.
remove_owned_state_dir() {
  local directory=$1 entry canonical coordination preserve ancestor link_check=$1
  # Test the directory entry itself, including roots supplied with trailing slashes.
  while [[ "$link_check" == */ && "$link_check" != / ]]; do link_check=${link_check%/}; done
  [[ ! -L "$link_check" ]] || fail_uninstall 1 ownership_state_symlink 'Refusing to traverse a symlink ownership state root during cleanup.'
  [[ -d "$directory" ]] || return 0
  for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    [[ "$keep_backups" != true || ("$entry" != "$(ownership_record)" && "$entry" != "$state_root/backups") ]] || continue
    canonical=$(realpath -m -- "$entry")
    preserve=false ancestor=false
    for coordination in "${coordination_files[@]}"; do
      [[ "$canonical" != "$coordination" ]] || preserve=true
      [[ "$coordination" != "$canonical/"* ]] || ancestor=true
    done
    if [[ -L "$entry" ]]; then
      # Never sever a retained lock's lookup path or follow an unrelated alias.
      [[ "$preserve" == false && "$ancestor" == false ]] || fail_uninstall 1 ownership_state_symlink 'Refusing to remove a symlink on a coordination path.'
      rm -f -- "$entry"
    elif [[ "$preserve" == true ]]; then
      continue
    elif [[ "$ancestor" == true && -d "$entry" ]]; then
      remove_owned_state_dir "$entry"
    else
      rm -rf -- "$entry"
    fi
  done
  rmdir -- "$directory" 2>/dev/null || true
}

# Removes Aranea's state. Files the user customised stay in the ledger with
# their backups (restore_managed_files keeps them), so those are kept.
remove_state() {
  local response keep_backups=false
  local -a coordination_files
  remove_agent_adapters
  # This drains publication before state/helper deletion. Never unlink the lock:
  # pending store/worker/helper ingress must observe the tombstone on that inode.
  if ! response=$("$repo_root/scripts/aranea-agent-store" deactivate); then
    fail_uninstall 1 activity_teardown_failed "Activity teardown could not coordinate; state removal is incomplete. $response"
  fi
  remove_agent_helpers
  coordination_files=(
    "$(realpath -m -- "$project_state_root/agent-activity.json.lock")"
    "$(realpath -m -- "$project_state_root/project-actions.json.lock")"
    "$(realpath -m -- "$project_state_root/project-actions.json.dispatch.lock")"
  )
  # Registry state does not follow an independently overridden ownership root.
  rm -f -- "$project_state_root/projects.json" "$project_state_root/projects.json.lock"
  if [[ -s "$(ownership_record)" ]]; then
    keep_backups=true
    printf 'kept the originals of files you changed in %s\n' "$state_root/backups"
  fi
  remove_owned_state_dir "$state_root"
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
  printf '  fence project action starts, stop proven owned runs, then remove action definitions/history\n'
  printf '  retain inert activity/action coordination files and necessary ancestors\n'
  printf '  remove exact owned Claude/Codex adapter hooks, heartbeat helpers and activity state\n'
  printf '  remove project registrations %s/projects.json and its lock\n' "$project_state_root"
  return 0
}

if ((dry_run)); then
  if ((json_mode)); then
    json_step uninstall ok stop-actions 'would fence project actions and drain only proven owned runs'
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

# Retain the installed command, theme scripts, registry and authority on failure.
# Backend retirement fences ingress and drains dispatch before deleting payload.
ownership_path=$state_root
while [[ "$ownership_path" == */ && "$ownership_path" != / ]]; do ownership_path=${ownership_path%/}; done
[[ ! -L "$ownership_path" ]] || fail_uninstall 1 ownership_state_symlink 'Refusing to traverse a symlink ownership state root during cleanup.'
unset ARANEA_ACTION_DISPATCH_FD
lifecycle_umask=$(umask)
umask 077
project_actions_dispatch_lock || fail_uninstall 1 action_lifecycle_busy "Project action lifecycle is busy or unsafe ($action_lock_error); removal has not begun. Retry after the other operation finishes."
umask "$lifecycle_umask"
if ((json_mode)); then json_step uninstall running stop-actions 'drain owned project actions'; fi
if ! action_response=$(ARANEA_ACTION_DISPATCH_FD=$dispatch_fd "$repo_root/scripts/aranea-project-actions" deactivate </dev/null); then
  action_error=$(printf '%s\n' "$action_response" | jq -r '[.error.message, .error.recovery, (if .run.id then "Retained run: " + .run.id + ". Use aranea projects runs inspect|refresh|stop with this run ID." else empty end)] | join(" ")')
  fail_uninstall 1 action_teardown_failed "Project action removal is incomplete; installed recovery tools and action state were retained. $action_error Restore manager access, resolve the retained run, then retry this uninstall."
fi
if ((json_mode)); then json_step uninstall ok stop-actions 'owned project actions drained'; fi

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
  current_theme="$(lifecycle_effect omarchy theme current 2>/dev/null || true)"
  if [[ "$current_theme" == Aranea || "$current_theme" == aranea ]]; then
    if [[ -n "$replacement_theme" ]]; then
      lifecycle_effect omarchy theme set "$replacement_theme"
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
      lifecycle_effect omarchy theme set "$replacement_theme"
    else
      printf '%s\n' 'Complete removal requires --replacement-theme when Aranea is active.' >&2
      exit 3
    fi
  fi
  if ((json_mode)); then json_step uninstall running remove-theme 'remove aranea theme directory'; fi
  lifecycle_effect omarchy theme remove aranea
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
