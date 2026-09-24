#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/manifest.sh"
theme_repo_url="${ARANEA_THEME_REPO_URL:-https://github.com/AraneaDev/aranea-desktop.git}"
theme_source="${ARANEA_THEME_SOURCE:-$theme_repo_url}"
dry_run=0
assume_yes=0
skip_conky=0
profile="full"

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [--profile minimal|full|no_apps] [--source PATH|URL] [--dry-run] [--yes] [--skip-conky]

Installs Aranea Desktop, its Omarchy theme/hooks, and optionally the Wayland Conky build.
EOF
}

say() { printf '%s\n' "$*"; }

run() {
  if (( dry_run )); then
    say "would run: $*"
  else
    "$@"
  fi
}

aur_helper() {
  if command -v paru >/dev/null 2>&1; then
    printf 'paru'
  elif command -v yay >/dev/null 2>&1; then
    printf 'yay'
  fi
}

while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes) assume_yes=1 ;;
    --skip-conky) skip_conky=1 ;;
    --source)
      (($# >= 2)) || { say "--source requires a path or URL" >&2; exit 2; }
      theme_source="$2"
      shift
      ;;
    --profile)
      (($# >= 2)) || { say "--profile requires a value" >&2; exit 2; }
      profile="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) say "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ! manifest_profile_exists "$profile"; then
  say "Unknown profile: $profile" >&2
  usage >&2
  exit 2
fi

if [[ "$theme_source" == /* && ! -d "$theme_source" ]]; then
  say "Aranea installer: local theme source does not exist: $theme_source" >&2
  exit 1
fi

say "profile: $profile"

if ! command -v omarchy >/dev/null 2>&1 && [[ "${OMARCHY_INSTALLER_TEST:-}" != 1 ]]; then
  say "Aranea installer: Omarchy is required but was not found." >&2
  exit 1
fi

helper="$(aur_helper || true)"
if [[ "$profile" != "no_apps" && "$profile" != "minimal" && $skip_conky -eq 0 ]]; then
  if [[ -n "$helper" ]]; then
    if (( dry_run )); then
      say "would install conky-cairo-wayland-git with $helper"
    elif (( assume_yes )); then
      run "$helper" -S --needed conky-cairo-wayland-git
    elif [[ -t 0 ]]; then
      read -r -p "Install optional conky-cairo-wayland-git for Aranea diagnostics? [Y/n] " answer
      if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        run "$helper" -S --needed conky-cairo-wayland-git
      fi
    else
      say "Skipping optional Conky install (rerun with --yes or install it manually)."
    fi
else
  if [[ "$profile" == "no_apps" || "$profile" == "minimal" ]]; then
    say "Skipping optional Conky install for profile: $profile"
  else
    say "Skipping optional Conky install: install paru or yay first."
  fi
fi
fi

if (( dry_run )); then
  say "would persist profile: $profile"
  say "would install theme from: $theme_source"
  say "would install theme hooks"
  say "would set theme to aranea"
  if [[ "$profile" == full || "$profile" == no_apps ]]; then
    say "would install cursor integration"
    say "would install icons integration"
    if [[ "$profile" == full ]]; then
      say "would install terminal integration"
    fi
  fi
else
  previous_theme="$(omarchy theme current 2>/dev/null || true)"
  install_failure_handler() {
    local status=$?
    if (( status != 0 )); then
      if [[ -n "$previous_theme" ]]; then
        say "Aranea install failed. Restore the previous theme with: omarchy theme set $previous_theme" >&2
      else
        say "Aranea install failed before a previous theme could be detected." >&2
      fi
    fi
    return "$status"
  }
  trap install_failure_handler EXIT
  profile_state="${XDG_STATE_HOME:-$HOME/.local/state}/aranea/profile"
  install -Dm644 /dev/null "$profile_state"
  printf '%s\n' "$profile" > "$profile_state"
  run omarchy theme install "$theme_source"
  run omarchy hook install theme-set "$repo_root/hooks/theme-set"
  run omarchy hook install post-boot "$repo_root/hooks/post-boot"
  run omarchy theme set aranea
  if [[ "$profile" == full || "$profile" == no_apps ]]; then
    theme_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme"
    run "$theme_root/scripts/install-integration" cursor --yes
    run "$theme_root/scripts/install-integration" icons --yes
    if [[ "$profile" == full ]]; then
      # Terminal configs live under integrations/terminal. Omarchy ignores
      # root-level alacritty.toml, kitty.conf, and foot.ini files when a theme
      # is installed from Git, so install the selected terminal explicitly.
      run "$theme_root/scripts/install-integration" terminal --yes
    fi
  fi
  say "Aranea installed. Conky remains off until you run aranea-diagnostics-toggle."
fi
