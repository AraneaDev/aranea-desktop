#!/usr/bin/env bash
set -euo pipefail

# Installs Aranea Desktop: saves the profile, installs the theme with
# `omarchy theme install`, adopts it as "aranea", installs the theme-set and
# post-boot hooks, applies the theme and links the profile's integrations.
# Asks for the profile with gum when interactive without --profile or --yes.
#
# Usage: scripts/install.sh [--profile minimal|full|no_apps] [--source PATH|URL] [--dry-run] [--yes]

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/paths.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/ownership.sh"
# shellcheck disable=SC1091
source "$repo_root/branding/brand.env"
source "$repo_root/scripts/lib/manifest.sh"
source "$repo_root/scripts/lib/json-events.sh"
theme_repo_url="${ARANEA_THEME_REPO_URL:-https://github.com/AraneaDev/aranea-desktop.git}"
theme_source="${ARANEA_THEME_SOURCE:-$theme_repo_url}"
dry_run=0
assume_yes=0
json_mode=0
profile="full"
profile_explicit=0
json_completed_sent=0

# Prints the usage text.
usage() {
  cat <<'EOF'
Usage: scripts/install.sh [--profile minimal|full|no_apps] [--source PATH|URL] [--dry-run] [--yes]

Installs Aranea Desktop and its Omarchy theme/hooks.
EOF
}

# Prints its arguments as one line.
say() {
  ((json_mode)) && return 0
  printf '%s\n' "$*"
}

# Emits a machine-readable failure or the existing human error and exits.
fail_install() {
  local status="$1"
  local message="$2"
  if ((json_mode)); then
    json_completed install failed "$3" "$message"
    json_completed_sent=1
  else
    printf '%s\n' "$message" >&2
  fi
  exit "$status"
}

# Runs the command, or only prints it in dry-run.
run() {
  if ((dry_run)); then
    say "would run: $*"
  else
    "$@"
  fi
}

# The directory `omarchy theme install` clones a source into: the basename
# without .git, an omarchy- prefix or a -theme suffix, lowercased. Mirrors
# omarchy-theme-install so the two cannot disagree about where Aranea landed.
installed_theme_name() {
  local source="${1%/}"
  if [[ "$source" != *"://"* && "$source" == *:* && "${source%%:*}" != */* ]]; then
    source="${source#*:}"
  fi
  basename -- "$source" .git | sed -E 's/^omarchy-//; s/-theme$//' | tr '[:upper:]' '[:lower:]'
}

# Aranea is always applied as the `aranea` theme (the hooks key on that name),
# but the default source (aranea-desktop.git) clones as "aranea-desktop". Move
# the fresh clone into place so `omarchy theme set aranea` never activates an
# older copy left from a previous install.
adopt_installed_theme() {
  local name themes_dir
  name="$(installed_theme_name "$1")"
  [[ "$name" == aranea ]] && return 0
  themes_dir="$HOME/.config/omarchy/themes"
  [[ -d "$themes_dir/$name" ]] || {
    say "installed theme not found: $themes_dir/$name" >&2
    return 1
  }
  rm -rf "$themes_dir/aranea"
  mv "$themes_dir/$name" "$themes_dir/aranea"
}

# gum is already an Omarchy-ecosystem dependency (omarchy-theme-install uses
# it too), so an interactive terminal running this installer is likely to
# have it. Prompts fall back to plain read/output when it doesn't, so gum is
# a nicer default rather than a hard requirement.
has_gum() {
  command -v gum >/dev/null 2>&1
}

while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes) assume_yes=1 ;;
    --json) json_mode=1 ;;
    --source)
      (($# >= 2)) || {
        fail_install 2 '--source requires a path or URL' invalid_usage
      }
      theme_source="$2"
      shift
      ;;
    --profile)
      (($# >= 2)) || {
        fail_install 2 '--profile requires a value' invalid_usage
      }
      profile="$2"
      profile_explicit=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      if ((json_mode)); then
        fail_install 2 "Unknown option: $1" invalid_usage
      fi
      say "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if ((json_mode)) && ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "$BRAND_NAME installer: --json requires jq." >&2
  exit 4
fi

if ((json_mode)); then
  dry_run_json=false
  assume_yes_json=false
  ((dry_run)) && dry_run_json=true
  ((assume_yes)) && assume_yes_json=true
  start_data="$(jq -cn \
    --arg profile "$profile" \
    --arg source "$theme_source" \
    --argjson dry_run "$dry_run_json" \
    --argjson assume_yes "$assume_yes_json" \
    '{profile: $profile, source: $source, dry_run: $dry_run, assume_yes: $assume_yes}')"
  json_started install "$start_data"
fi

# An explicit --profile, --yes, or no interactive terminal all keep the
# "full" default silent, exactly as before gum was ever in the picture.
if ((! profile_explicit)) && ((! assume_yes)) && [[ -t 0 ]] && has_gum; then
  if profile_choice="$(gum choose \
    --header 'Choose an installation profile:' \
    'full       Every supported application integration' \
    'minimal    Core and GTK experience only' \
    'no_apps    Theme, cursor, icons, wallpaper, and branding, without application integrations')"; then
    profile="${profile_choice%% *}"
  else
    say "$BRAND_NAME installer: profile selection cancelled." >&2
    exit 1
  fi
fi

if ! manifest_profile_exists "$profile"; then
  fail_install 2 "Unknown profile: $profile" invalid_profile
fi

if [[ "$theme_source" == /* && ! -d "$theme_source" ]]; then
  fail_install 1 "$BRAND_NAME installer: local theme source does not exist: $theme_source" missing_source
fi

if ((json_mode)); then
  json_step install running validate 'validate install options'
  json_step install ok validate 'install options validated'
else
  say "profile: $profile"
fi

if ! command -v omarchy >/dev/null 2>&1 && [[ "${OMARCHY_INSTALLER_TEST:-}" != 1 ]]; then
  fail_install 4 "$BRAND_NAME installer: Omarchy is required but was not found." missing_dependency
fi

if ((dry_run)); then
  if ((json_mode)); then
    json_step install ok persist-profile 'would persist installation profile'
    json_step install ok install-theme "would install theme from: $theme_source"
    json_step install ok install-command 'would install the owned project command'
    json_step install ok install-fonts 'would install bundled interface fonts'
    json_step install ok install-hooks 'would install theme hooks'
    json_step install ok activate-theme 'would set theme to aranea'
  else
    say "would persist profile: $profile"
    say "would install theme from: $theme_source"
    say "would install project command: $(xdg_bin_home)/aranea"
    say "would install theme hooks"
    say "would install bundled interface fonts"
    say "would set theme to aranea"
  fi
  if [[ "$profile" == full || "$profile" == no_apps ]]; then
    if ((json_mode)); then
      json_step install ok install-cursor 'would install cursor integration'
      json_step install ok install-icons 'would install icons integration'
    else
      say "would install cursor integration"
      say "would install icons integration"
    fi
    if [[ "$profile" == full ]]; then
      if ((json_mode)); then
        json_step install ok install-terminal 'would install terminal integration'
      else
        say "would install terminal integration"
      fi
    fi
  fi
  if ((json_mode)); then
    json_completed install ok '' 'dry-run completed'
    json_completed_sent=1
  fi
else
  previous_theme="$(omarchy theme current 2>/dev/null || true)"
  # EXIT trap: on failure, tells the user how to restore the previous theme.
  install_failure_handler() {
    local status=$?
    if ((status != 0)); then
      if ((json_mode)); then
        if [[ -n "$previous_theme" ]]; then
          json_recovery install restore-theme "restore previous theme with: omarchy theme set \"$previous_theme\""
        fi
        if ((json_completed_sent == 0)); then
          json_completed install failed operation_failed "$BRAND_NAME install failed."
          json_completed_sent=1
        fi
      elif [[ -n "$previous_theme" ]]; then
        say "$BRAND_NAME install failed. Restore the previous theme with: omarchy theme set \"$previous_theme\"" >&2
      else
        say "$BRAND_NAME install failed before a previous theme could be detected." >&2
      fi
    fi
    return "$status"
  }
  trap install_failure_handler EXIT
  ((json_mode)) && json_step install running persist-profile 'persist installation profile'
  profile_state="$(aranea_state_root)/profile"
  install -Dm644 /dev/null "$profile_state"
  printf '%s\n' "$profile" >"$profile_state"
  ((json_mode)) && json_step install ok persist-profile 'installation profile persisted'
  ((json_mode)) && json_step install running install-theme 'install theme'
  run omarchy theme install "$theme_source"
  adopt_installed_theme "$theme_source"
  ((json_mode)) && json_step install ok install-theme 'theme installed as aranea'
  ((json_mode)) && json_step install running install-command 'install the owned project command'
  theme_root="$HOME/.config/omarchy/themes/aranea"
  [[ -x "$theme_root/scripts/aranea" ]] || fail_install 1 'Installed project command is missing.' missing_command
  link_managed_file "$(xdg_bin_home)/aranea" "$theme_root/scripts/aranea"
  ((json_mode)) && json_step install ok install-command 'project command ownership reconciled'
  ((json_mode)) && json_step install running install-fonts 'install bundled interface fonts'
  run "$repo_root/scripts/install-fonts"
  ((json_mode)) && json_step install ok install-fonts 'bundled interface fonts installed'
  ((json_mode)) && json_step install running install-hooks 'install theme hooks'
  run omarchy hook install theme-set "$repo_root/hooks/theme-set"
  run omarchy hook install post-boot "$repo_root/hooks/post-boot"
  ((json_mode)) && json_step install ok install-hooks 'theme hooks installed'
  ((json_mode)) && json_step install running activate-theme 'activate aranea theme'
  run omarchy theme set aranea
  ((json_mode)) && json_step install ok activate-theme 'aranea theme activated'
  if [[ "$profile" == full || "$profile" == no_apps ]]; then
    # Link integrations from the stable installed theme, which survives theme
    # switches (Omarchy's current-theme copy is replaced on every switch).
    theme_root="$HOME/.config/omarchy/themes/aranea"
    ((json_mode)) && json_step install running install-cursor 'install cursor integration'
    run "$theme_root/scripts/install-integration" cursor --yes
    ((json_mode)) && json_step install ok install-cursor 'cursor integration installed'
    ((json_mode)) && json_step install running install-icons 'install icons integration'
    run "$theme_root/scripts/install-integration" icons --yes
    ((json_mode)) && json_step install ok install-icons 'icons integration installed'
    if [[ "$profile" == full ]]; then
      # Terminal configs live under integrations/terminal. Omarchy ignores
      # root-level alacritty.toml, kitty.conf, and foot.ini files when a theme
      # is installed from Git, so install the selected terminal explicitly.
      ((json_mode)) && json_step install running install-terminal 'install terminal integration'
      run "$theme_root/scripts/install-integration" terminal --yes
      ((json_mode)) && json_step install ok install-terminal 'terminal integration installed'
    fi
  fi
  if ((json_mode)); then
    json_completed install ok '' "$BRAND_NAME installed."
    json_completed_sent=1
  else
    say "$BRAND_NAME installed."
  fi
fi
