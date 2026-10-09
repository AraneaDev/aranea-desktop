#!/usr/bin/env bash
# Contract for scripts/install.sh --dry-run: reports every planned step and
# profile, rejects a missing --source, and (for a real run) always installs
# and activates the theme as "aranea" regardless of the source clone's name,
# leaving no stale or duplicate theme directory behind.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
output="$(mktemp)"

PATH="$repo_root/tests/fake-bin:$PATH" \
  OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/scripts/install.sh" --dry-run --yes >"$output"

grep -Fq "would install theme hooks" "$output"
grep -Fq "would set theme to aranea" "$output"
grep -Fq "would install cursor integration" "$output"
grep -Fq "would install icons integration" "$output"
grep -Fq "would install terminal integration" "$output"
grep -Fq "would persist profile: full" "$output"
grep -Fq "would install project command: $HOME/.local/bin/aranea" "$output"

grep -Fq "would install theme from: $repo_root" <(PATH="$repo_root/tests/fake-bin:$PATH" OMARCHY_INSTALLER_TEST=1 "$repo_root/scripts/install.sh" --dry-run --yes --source "$repo_root")
if PATH="$repo_root/tests/fake-bin:$PATH" OMARCHY_INSTALLER_TEST=1 "$repo_root/scripts/install.sh" --dry-run --yes --source "$repo_root/tests/missing-local-source" >/dev/null 2>&1; then
  echo "installer accepted a missing local source" >&2
  exit 1
fi

minimal_output="$(mktemp)"
PATH="$repo_root/tests/fake-bin:$PATH" \
  OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/scripts/install.sh" --dry-run --yes --profile no_apps >"$minimal_output"

grep -Fq "profile: no_apps" "$minimal_output"
grep -Fq "would install theme hooks" "$minimal_output"
grep -Fq "would persist profile: no_apps" "$minimal_output"

grep -Fq 'profile_file=' "$repo_root/hooks/theme-set"
grep -Fq 'profile_file=' "$repo_root/hooks/post-boot"

json_output="$(PATH="$repo_root/tests/fake-bin:$PATH" \
  OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/scripts/install.sh" --json --dry-run --yes --profile full)"
first_event=1
last_event=''
while IFS= read -r event; do
  [[ -n "$event" ]] || continue
  jq -e '.schema == 1 and .operation == "install" and .timestamp and .event' <<<"$event" >/dev/null
  if ((first_event)); then
    jq -e '.event == "started" and .data.profile == "full" and .data.dry_run == true' <<<"$event" >/dev/null
    first_event=0
  fi
  last_event="$event"
done <<<"$json_output"
jq -e '.event == "completed" and .status == "ok"' <<<"$last_event" >/dev/null

missing_json_status=0
PATH="$repo_root/tests/fake-bin:$PATH" OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/scripts/install.sh" --json --dry-run --yes \
  --source "$repo_root/tests/missing-local-source" >/dev/null 2>&1 || missing_json_status=$?
[[ "$missing_json_status" == 1 ]] || {
  echo "missing local source did not return JSON operation failure" >&2
  exit 1
}

# --- the theme is always installed as `aranea`, whatever the source is called
# (the default URL ends in aranea-desktop.git, which Omarchy names
# "aranea-desktop"; `omarchy theme set aranea` must not activate a stale copy).
name_root="$(mktemp -d)"
mkdir -p "$name_root/bin" "$name_root/home/.config/omarchy/themes/aranea"
printf 'stale\n' >"$name_root/home/.config/omarchy/themes/aranea/VERSION"
cat >"$name_root/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
# Mimics omarchy-theme-install's naming: basename, no .git, no omarchy-/-theme.
if [[ "$1 $2" == "theme install" ]]; then
  name="$(basename -- "$3" .git | sed -E 's/^omarchy-//; s/-theme$//' | tr '[:upper:]' '[:lower:]')"
  rm -rf "$HOME/.config/omarchy/themes/$name"
  mkdir -p "$HOME/.config/omarchy/themes/$name"
  printf 'fresh\n' > "$HOME/.config/omarchy/themes/$name/VERSION"
  cp -a "$TEST_THEME_SOURCE/plugins" "$HOME/.config/omarchy/themes/$name/plugins"
  cp -a "$TEST_THEME_SOURCE/scripts" "$HOME/.config/omarchy/themes/$name/scripts"
  cp -a "$TEST_THEME_SOURCE/integrations" "$TEST_THEME_SOURCE/branding" \
    "$TEST_THEME_SOURCE/theme-manifest.toml" "$HOME/.config/omarchy/themes/$name/"
fi
printf '%s\n' "$*" >> "$HOME/omarchy-calls"
exit 0
EOF
chmod +x "$name_root/bin/omarchy"

HOME="$name_root/home" XDG_STATE_HOME="$name_root/home/.local/state" TEST_THEME_SOURCE="$repo_root" \
  PATH="$name_root/bin:$repo_root/tests/fake-bin:$PATH" OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/scripts/install.sh" --yes --profile minimal \
  --source "https://example.invalid/AraneaDev/aranea-desktop.git" >/dev/null

themes="$name_root/home/.config/omarchy/themes"
[[ "$(cat "$themes/aranea/VERSION")" == fresh ]] || {
  echo "installer activated a stale aranea copy" >&2
  exit 1
}
[[ ! -e "$themes/aranea-desktop" ]] || {
  echo "installer left the aranea-desktop clone behind" >&2
  exit 1
}
grep -Fxq 'theme set aranea' "$name_root/home/omarchy-calls"

# A user-bin command must survive active-theme changes and preserve the
# pre-existing wrapper through repeat installs and integration removal.
export XDG_BIN_HOME="$HOME/bin with spaces"
export TEST_THEME_SOURCE="$repo_root"
mkdir -p "$XDG_BIN_HOME"
printf '#!/usr/bin/env bash\nprintf "user wrapper\\n"\n' >"$XDG_BIN_HOME/aranea"
chmod +x "$XDG_BIN_HOME/aranea"
for attempt in first repeat; do
  PATH="$name_root/bin:$PATH" "$repo_root/scripts/install.sh" --yes --profile minimal \
    --source https://example.invalid/AraneaDev/aranea-desktop.git >/dev/null
  [[ "$(readlink "$XDG_BIN_HOME/aranea")" == "$HOME/.config/omarchy/themes/aranea/scripts/aranea" ]] || {
    echo "$attempt install did not link the stable installed project command" >&2
    exit 1
  }
  [[ "$(grep -Fxc "$XDG_BIN_HOME/aranea" "$XDG_STATE_HOME/aranea/managed-files")" == 1 ]]
done
grep -Fq 'user wrapper' "$XDG_STATE_HOME/aranea/backups$XDG_BIN_HOME/aranea"
mkdir -p "$HOME/.local/state/omarchy/current/theme/scripts"
printf '#!/usr/bin/env bash\nexit 99\n' >"$HOME/.local/state/omarchy/current/theme/scripts/aranea"
chmod +x "$HOME/.local/state/omarchy/current/theme/scripts/aranea"
for cli in "$repo_root/scripts/aranea" "$XDG_BIN_HOME/aranea"; do
  "$cli" projects list --json | jq -se 'last | .data.projects == [] and .data.outcome == "observed"' >/dev/null
  "$cli" capabilities --json | jq -se 'last | .data.availability.owner == null' >/dev/null
  status=0
  desktop_output="$("$cli" desktop status --json 2>/dev/null)" || status=$?
  [[ "$status" == 1 ]]
  jq -se 'last | .code == "OWNER_UNAVAILABLE" and .data.outcome == "partial"' <<<"$desktop_output" >/dev/null
done
[[ "$(readlink "$HOME/.local/bin/aranea" 2>/dev/null || true)" == '' ]]
"$repo_root/scripts/uninstall.sh" --yes --scope integration >/dev/null
[[ ! -L "$XDG_BIN_HOME/aranea" && "$("$XDG_BIN_HOME/aranea")" == 'user wrapper' ]]
[[ -d "$HOME/.config/omarchy/themes/aranea" ]]

# Full and no_apps installs expose the same CLI. User customisations after
# installation remain authoritative, including arbitrary scripts symlinks.
unset XDG_BIN_HOME
for install_profile in full no_apps; do
  PATH="$name_root/bin:$PATH" "$repo_root/scripts/install.sh" --yes --profile "$install_profile" \
    --source https://example.invalid/AraneaDev/aranea-desktop.git >/dev/null
  [[ "$(readlink "$HOME/.local/bin/aranea")" == "$HOME/.config/omarchy/themes/aranea/scripts/aranea" ]]
  "$HOME/.local/bin/aranea" agents list --json | jq -se 'last | .data.tasks == [] and .data.outcome == "observed"' >/dev/null
  "$HOME/.local/bin/aranea" projects list --json | jq -se 'last | .data.projects == []' >/dev/null
done
ln -sf "$HOME/custom/scripts/aranea" "$HOME/.local/bin/aranea"
PATH="$name_root/bin:$PATH" "$repo_root/scripts/install.sh" --yes --profile minimal \
  --source https://example.invalid/AraneaDev/aranea-desktop.git >/dev/null
[[ "$(readlink "$HOME/.local/bin/aranea")" == "$HOME/custom/scripts/aranea" ]]
"$repo_root/scripts/uninstall.sh" --yes >/dev/null
[[ "$(readlink "$HOME/.local/bin/aranea")" == "$HOME/custom/scripts/aranea" ]]

echo "installer dry-run contract passed"

# The stable installed CLI includes activity without silently opting providers in.
installed_theme="$HOME/.config/omarchy/themes/aranea"
jq -e '.id=="araneadev.activity" and .keepLoaded==true' "$installed_theme/plugins/araneadev.activity/manifest.json" >/dev/null
if "$installed_theme/scripts/aranea" agents list --json >"$TMPDIR/removed-activity" 2>/dev/null; then
  echo 'uninstalled activity unexpectedly reactivated'
  exit 1
fi
jq -se 'last | .code=="ACTIVITY_REMOVED"' "$TMPDIR/removed-activity" >/dev/null
[[ ! -e "$HOME/.claude/settings.json" && ! -e "$HOME/.codex/hooks.json" ]]
echo 'PASS installed persistent activity plugin and opt-in provider configuration'
