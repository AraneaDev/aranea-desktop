#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/manifest.sh"
theme_repo_url="${ARANEA_THEME_REPO_URL:-https://github.com/AraneaDev/omarchy-aranea-theme.git}"
dry_run=0
assume_yes=0
skip_conky=0
profile="full"

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [--profile minimal|full|no_apps] [--dry-run] [--yes] [--skip-conky]

Installs the Aranea theme, its Omarchy hooks, and optionally the Wayland Conky build.
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
  say "would install theme hooks"
  say "would set theme to aranea"
else
  run omarchy theme install "$theme_repo_url"
  run omarchy hook install theme-set "$repo_root/hooks/theme-set"
  run omarchy hook install post-boot "$repo_root/hooks/post-boot"
  run omarchy theme set aranea
  say "Aranea installed. Conky remains off until you run aranea-diagnostics-toggle."
fi
