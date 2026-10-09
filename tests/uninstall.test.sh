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
mkdir -p "$hooks/theme-set.d" "$hooks/post-boot.d" "$plugins/araneadev.bar" "$plugins/araneadev.settings" "$plugins/other.plugin" \
  "$units" "$XDG_STATE_HOME/aranea/gsettings" "$XDG_DATA_HOME/icons/Aranea/cursors"
cp "$repo_root/hooks/theme-set" "$hooks/theme-set.d/theme-set"
cp "$repo_root/hooks/post-boot" "$hooks/post-boot.d/post-boot"
printf '#!/bin/bash\n# my own hook\n' >"$hooks/theme-set.d/mine"
: >"$units/aranea-wallpaper-day-night.timer"
: >"$units/aranea-wallpaper-day-night.service"
printf "'Adwaita'\n" >"$XDG_STATE_HOME/aranea/gsettings/org.gnome.desktop.interface.icon-theme"
printf '{"bar":{"id":"araneadev.bar"},"plugins":[{"id":"araneadev.settings"},{"id":"user.widget","option":7}],"userSettings":{"keep":true}}\n' >"$HOME/.config/omarchy/shell.json"
mkdir -p "$XDG_CONFIG_HOME/aranea"
printf 'dawn=06:00\n' >"$XDG_CONFIG_HOME/aranea/wallpaper-schedule.conf"

"$repo_root/scripts/uninstall.sh" --yes >/dev/null

[[ ! -e "$hooks/theme-set.d/theme-set" && ! -e "$hooks/post-boot.d/post-boot" ]]
[[ -e "$hooks/theme-set.d/mine" ]]
[[ ! -e "$plugins/araneadev.bar" && ! -e "$plugins/araneadev.settings" && -e "$plugins/other.plugin" ]]
jq -e ' .plugins == [{id:"user.widget",option:7}] and .userSettings.keep' "$HOME/.config/omarchy/shell.json" >/dev/null
[[ ! -e "$units/aranea-wallpaper-day-night.timer" && ! -e "$units/aranea-wallpaper-day-night.service" ]]
[[ ! -e "$XDG_STATE_HOME/aranea" ]]
[[ ! -e "$XDG_CONFIG_HOME/aranea" ]]
[[ ! -e "$XDG_DATA_HOME/icons/Aranea" ]]
jq -e '.bar.id != "araneadev.bar"' "$HOME/.config/omarchy/shell.json" >/dev/null
grep -Fq "gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'" "$ARANEA_TEST_SANDBOX/guard.log"
grep -Fq 'systemctl --user disable --now aranea-wallpaper-day-night.timer' "$ARANEA_TEST_SANDBOX/guard.log"

json_output="$("$repo_root/scripts/uninstall.sh" --json --dry-run --yes --scope integration)"
first_event=1
last_event=''
while IFS= read -r event; do
  [[ -n "$event" ]] || continue
  jq -e '.schema == 1 and .operation == "uninstall" and .timestamp and .event' <<<"$event" >/dev/null
  if ((first_event)); then
    jq -e '.event == "started" and .data.scope == "integration" and .data.dry_run == true' <<<"$event" >/dev/null
    first_event=0
  fi
  last_event="$event"
done <<<"$json_output"
jq -e '.event == "completed" and .status == "ok"' <<<"$last_event" >/dev/null

mkdir -p "$HOME/.config/omarchy/themes/aranea"
"$repo_root/scripts/uninstall.sh" --json --yes --scope complete >/dev/null
grep -Fq 'omarchy theme remove aranea' "$ARANEA_TEST_SANDBOX/guard.log"

invalid_scope_status=0
"$repo_root/scripts/uninstall.sh" --json --scope invalid >/dev/null 2>&1 || invalid_scope_status=$?
[[ "$invalid_scope_status" == 2 ]]

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

# Both scopes discard project registrations, never their repository folders.
# An owned command is removed; a user-replaced command and its backup stay.
source "$repo_root/scripts/lib/ownership.sh"
project_dir="$ARANEA_TEST_SANDBOX/project with spaces"
git init -q "$project_dir"
printf 'keep repository content\n' >"$project_dir/content"
mkdir -p "$ARANEA_TEST_SANDBOX/app-bin"
printf '#!/usr/bin/env bash\nexec /usr/bin/sleep 60\n' >"$ARANEA_TEST_SANDBOX/app-bin/code"
chmod +x "$ARANEA_TEST_SANDBOX/app-bin/code"
launch=$(jq -cn --arg cwd "$project_dir" '{cwd:$cwd,argv:["code","--new-window",$cwd]}' |
  PATH="$ARANEA_TEST_SANDBOX/app-bin:$PATH" "$repo_root/scripts/aranea-project-launch")
app_pid=$(jq -er 'select(.ok).identity.pid' <<<"$launch")
sandbox_on_exit "kill -- -$app_pid 2>/dev/null || true"
for removal_scope in integration complete; do
  export ARANEA_STATE_ROOT="$ARANEA_TEST_SANDBOX/$removal_scope state"
  "$repo_root/scripts/aranea" projects register --path "$project_dir" --json >/dev/null
  mkdir -p "$HOME/.local/bin" "$plugins/araneadev.projects"
  ln -s "$HOME/.config/omarchy/themes/aranea/scripts/aranea" "$HOME/.local/bin/aranea"
  record_managed_file "$HOME/.local/bin/aranea"
  ln -sf "$project_dir/user-command" "$HOME/.local/bin/custom-command"
  record_managed_file "$HOME/.local/bin/custom-command"
  mkdir -p "$(dirname "$(backup_path "$HOME/.local/bin/custom-command")")"
  printf 'original command\n' >"$(backup_path "$HOME/.local/bin/custom-command")"
  printf '{"plugins":[{"id":"araneadev.projects"},{"id":"user.widget","option":7}]}\n' >"$HOME/.config/omarchy/shell.json"
  "$repo_root/scripts/uninstall.sh" --yes --scope "$removal_scope" >/dev/null
  [[ ! -L "$HOME/.local/bin/aranea" ]] || {
    echo "$removal_scope removal kept the owned project command" >&2
    exit 1
  }
  [[ ! -e "$ARANEA_STATE_ROOT/projects.json" && ! -e "$plugins/araneadev.projects" ]]
  jq -e '.plugins == [{id:"user.widget",option:7}]' "$HOME/.config/omarchy/shell.json" >/dev/null
  [[ "$(cat "$project_dir/content")" == 'keep repository content' && -d "$project_dir/.git" ]]
  [[ "$(readlink "$HOME/.local/bin/custom-command")" == "$project_dir/user-command" ]]
  [[ "$(cat "$(backup_path "$HOME/.local/bin/custom-command")")" == 'original command' ]]
  kill -0 "$app_pid" # uninstall removes state, never detached applications
  [[ "$(ps -o stat= -p "$app_pid")" != Z* ]]
done

echo "uninstall contract passed"
