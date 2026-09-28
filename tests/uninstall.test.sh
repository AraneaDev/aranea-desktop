#!/usr/bin/env bash
# Contract for scripts/uninstall.sh: removes Aranea's hooks (only its own),
# hands the shell back, removes the plugins, the wallpaper timer and Aranea's
# state, restores saved gsettings, and is safe to run twice. Restoring the
# managed files themselves is covered by tests/ownership.test.sh.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

hooks="$HOME/.config/omarchy/hooks"
plugins="$HOME/.config/omarchy/plugins"
units="$HOME/.config/systemd/user"
mkdir -p "$hooks/theme-set.d" "$hooks/post-boot.d" "$plugins/araneadev.bar" "$plugins/other.plugin" \
  "$units" "$XDG_STATE_HOME/aranea/gsettings" "$XDG_DATA_HOME/icons/Aranea/cursors"
cp "$repo_root/hooks/theme-set" "$hooks/theme-set.d/theme-set"
cp "$repo_root/hooks/post-boot" "$hooks/post-boot.d/post-boot"
printf '#!/bin/bash\n# my own hook\n' >"$hooks/theme-set.d/mine"
: >"$units/aranea-wallpaper-day-night.timer"
: >"$units/aranea-wallpaper-day-night.service"
printf "'Adwaita'\n" >"$XDG_STATE_HOME/aranea/gsettings/org.gnome.desktop.interface.icon-theme"
printf '{"bar":{"id":"araneadev.bar"},"plugins":[]}\n' >"$HOME/.config/omarchy/shell.json"
mkdir -p "$XDG_CONFIG_HOME/aranea"
printf 'dawn=06:00\n' >"$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"

"$repo_root/scripts/uninstall.sh" --yes >/dev/null

[[ ! -e "$hooks/theme-set.d/theme-set" && ! -e "$hooks/post-boot.d/post-boot" ]]
[[ -e "$hooks/theme-set.d/mine" ]]
[[ ! -e "$plugins/araneadev.bar" && -e "$plugins/other.plugin" ]]
[[ ! -e "$units/aranea-wallpaper-day-night.timer" && ! -e "$units/aranea-wallpaper-day-night.service" ]]
[[ ! -e "$XDG_STATE_HOME/aranea" ]]
[[ ! -e "$XDG_CONFIG_HOME/aranea" ]]
[[ ! -e "$XDG_DATA_HOME/icons/Aranea" ]]
jq -e '.bar.id != "araneadev.bar"' "$HOME/.config/omarchy/shell.json" >/dev/null
grep -Fq "gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'" "$ARANEA_TEST_SANDBOX/guard.log"
grep -Fq 'systemctl --user disable --now aranea-wallpaper-day-night.timer' "$ARANEA_TEST_SANDBOX/guard.log"

# A second run finds nothing to do and still succeeds.
"$repo_root/scripts/uninstall.sh" --yes >/dev/null

# --dry-run changes nothing.
mkdir -p "$plugins/araneadev.menu"
"$repo_root/scripts/uninstall.sh" --dry-run >/dev/null
[[ -e "$plugins/araneadev.menu" ]]

# --- 4d review: a same-named user hook stays; no ledger is fine; backups of
# files the user customised survive; desktop settings fall back to reset
rm -rf "$XDG_STATE_HOME/aranea"
printf '#!/bin/bash\n# my own theme-set hook\n' >"$hooks/theme-set.d/theme-set"
"$repo_root/scripts/uninstall.sh" --yes >/dev/null
[[ -e "$hooks/theme-set.d/theme-set" ]]

custom="$HOME/.config/starship.toml"
mkdir -p "$XDG_STATE_HOME/aranea/backups$(dirname "$custom")" "$XDG_STATE_HOME/aranea/gsettings"
printf 'original\n' >"$XDG_STATE_HOME/aranea/backups$custom"
printf 'customised\n' >"$custom"
printf '%s\n' "$custom" >"$XDG_STATE_HOME/aranea/managed-files"
printf "'Aranea-icons'\n" >"$XDG_STATE_HOME/aranea/gsettings/org.gnome.desktop.interface.icon-theme"
: >"$ARANEA_TEST_SANDBOX/guard.log"
"$repo_root/scripts/uninstall.sh" --yes >/dev/null
[[ "$(<"$custom")" == customised ]]
[[ "$(<"$XDG_STATE_HOME/aranea/backups$custom")" == original ]]
grep -Fqx "$custom" "$XDG_STATE_HOME/aranea/managed-files"
grep -Fq 'gsettings reset org.gnome.desktop.interface icon-theme' "$ARANEA_TEST_SANDBOX/guard.log"
if grep -Fq "icon-theme 'Aranea-icons'" "$ARANEA_TEST_SANDBOX/guard.log"; then
  echo "restored Aranea's own icon theme as the previous value" >&2
  exit 1
fi

echo "uninstall contract passed"
