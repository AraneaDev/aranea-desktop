#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(mktemp)"
trap 'rm -f "$output"' EXIT

PATH="$repo_root/tests/fake-bin:$PATH" \
  OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/scripts/install.sh" --dry-run --yes >"$output"

grep -Fq "would install conky-cairo-wayland-git with paru" "$output"
grep -Fq "would install theme hooks" "$output"
grep -Fq "would set theme to aranea" "$output"
grep -Fq "would install cursor integration" "$output"
grep -Fq "would install icons integration" "$output"
grep -Fq "would install terminal integration" "$output"
grep -Fq "would persist profile: full" "$output"

grep -Fq "would install theme from: $repo_root" <(PATH="$repo_root/tests/fake-bin:$PATH" OMARCHY_INSTALLER_TEST=1 "$repo_root/scripts/install.sh" --dry-run --yes --source "$repo_root")
if PATH="$repo_root/tests/fake-bin:$PATH" OMARCHY_INSTALLER_TEST=1 "$repo_root/scripts/install.sh" --dry-run --yes --source "$repo_root/tests/missing-local-source" >/dev/null 2>&1; then
  echo "installer accepted a missing local source" >&2
  exit 1
fi

minimal_output="$(mktemp)"
trap 'rm -f "$output" "$minimal_output"' EXIT
PATH="$repo_root/tests/fake-bin:$PATH" \
  OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/scripts/install.sh" --dry-run --yes --profile no_apps >"$minimal_output"

grep -Fq "profile: no_apps" "$minimal_output"
grep -Fq "would install theme hooks" "$minimal_output"
grep -Fq "would persist profile: no_apps" "$minimal_output"
grep -Fq "conky-cairo-wayland-git" "$minimal_output" && exit 1

grep -Fq 'profile_file=' "$repo_root/hooks/theme-set"
grep -Fq 'profile_file=' "$repo_root/hooks/post-boot"

# --- the theme is always installed as `aranea`, whatever the source is called
# (the default URL ends in aranea-desktop.git, which Omarchy names
# "aranea-desktop"; `omarchy theme set aranea` must not activate a stale copy).
name_root="$(mktemp -d)"
trap 'rm -f "$output" "$minimal_output"; rm -rf "$name_root"' EXIT
mkdir -p "$name_root/bin" "$name_root/home/.config/omarchy/themes/aranea"
printf 'stale\n' > "$name_root/home/.config/omarchy/themes/aranea/VERSION"
cat > "$name_root/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
# Mimics omarchy-theme-install's naming: basename, no .git, no omarchy-/-theme.
if [[ "$1 $2" == "theme install" ]]; then
  name="$(basename -- "$3" .git | sed -E 's/^omarchy-//; s/-theme$//' | tr '[:upper:]' '[:lower:]')"
  rm -rf "$HOME/.config/omarchy/themes/$name"
  mkdir -p "$HOME/.config/omarchy/themes/$name"
  printf 'fresh\n' > "$HOME/.config/omarchy/themes/$name/VERSION"
fi
printf '%s\n' "$*" >> "$HOME/omarchy-calls"
exit 0
EOF
chmod +x "$name_root/bin/omarchy"

HOME="$name_root/home" XDG_STATE_HOME="$name_root/home/.local/state" \
  PATH="$name_root/bin:$repo_root/tests/fake-bin:$PATH" OMARCHY_INSTALLER_TEST=1 \
  "$repo_root/scripts/install.sh" --yes --skip-conky --profile minimal \
  --source "https://example.invalid/AraneaDev/aranea-desktop.git" >/dev/null

themes="$name_root/home/.config/omarchy/themes"
[[ "$(cat "$themes/aranea/VERSION")" == fresh ]] || { echo "installer activated a stale aranea copy" >&2; exit 1; }
[[ ! -e "$themes/aranea-desktop" ]] || { echo "installer left the aranea-desktop clone behind" >&2; exit 1; }
grep -Fxq 'theme set aranea' "$name_root/home/omarchy-calls"

echo "installer dry-run contract passed"
