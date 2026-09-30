#!/usr/bin/env bash
# Contract for the plugin/theme branding skew check: scripts/lib/brand-assets.sh
# lists the branding files the plugins reference (BrandConfig's markFile and
# literal marks/motifs/glyphs paths) that the active theme lacks; aranea-doctor
# reports them as a "branding" repair and deploy-plugins-safely warns about
# them. Plugins newer than the installed theme once left the mark blank.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/brand-assets.sh"

theme="$ARANEA_TEST_SANDBOX/theme"
plugins="$repo_root/plugins"

# Copies the repository's branding into the fake theme.
full_theme() {
  rm -rf "$theme"
  mkdir -p "$theme"
  cp -r "$repo_root/branding" "$theme/branding"
}

# --- a theme with the repository's branding has everything the plugins use
full_theme
[[ -z "$(missing_brand_assets "$plugins" "$theme")" ]]

# --- a theme from before brand.svg existed misses exactly that file
rm "$theme/branding/brand.svg"
[[ "$(missing_brand_assets "$plugins" "$theme")" == branding/brand.svg ]]

# --- literal motif paths are checked too
full_theme
rm "$theme/branding/motifs/menu-network.svg"
[[ "$(missing_brand_assets "$plugins" "$theme")" == branding/motifs/menu-network.svg ]]

# --- no deployed shared plugin: nothing to compare
[[ -z "$(missing_brand_assets "$ARANEA_TEST_SANDBOX/no-plugins" "$theme")" ]]

# --- aranea-doctor: ok, repair with the file and the fix, skipped
# Runs the doctor against PLUGIN_ROOT and the fake theme and prints its
# branding record.
doctor_branding() {
  ARANEA_DOCTOR_PLUGIN_ROOT="$1" ARANEA_DOCTOR_THEME_ROOT="$theme" \
    "$repo_root/scripts/aranea-doctor" --json | jq -c 'select(.id == "branding")'
}
full_theme
jq -e '.status == "ok"' <<<"$(doctor_branding "$plugins")" >/dev/null
rm "$theme/branding/brand.svg"
record="$(doctor_branding "$plugins")"
jq -e '.status == "repair" and (.message | contains("branding/brand.svg") and contains("scripts/install.sh"))' <<<"$record" >/dev/null
jq -e '.status == "skipped"' <<<"$(doctor_branding "$ARANEA_TEST_SANDBOX/no-plugins")" >/dev/null

# --- deploy-plugins-safely warns (and still deploys) when the active theme
# lacks what the plugins it deploys reference
source_root="$ARANEA_TEST_SANDBOX/source"
mkdir -p "$source_root/scripts"
cp "$repo_root/scripts/deploy-plugin" "$source_root/scripts/"
cp -r "$repo_root/plugins" "$source_root/plugins"
active="$HOME/.local/state/omarchy/current/theme"
mkdir -p "$(dirname "$active")"
cp -r "$theme" "$active"
target="$ARANEA_TEST_SANDBOX/deployed"
# The guard stub for session-locked succeeds, which would skip the deploy.
mkdir -p "$ARANEA_TEST_SANDBOX/unlocked-bin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$ARANEA_TEST_SANDBOX/unlocked-bin/omarchy-hyprland-session-locked"
chmod +x "$ARANEA_TEST_SANDBOX/unlocked-bin/omarchy-hyprland-session-locked"
PATH="$ARANEA_TEST_SANDBOX/unlocked-bin:$PATH"
"$repo_root/scripts/deploy-plugins-safely" "$source_root" "$target" 2>"$ARANEA_TEST_SANDBOX/deploy.err"
grep -Fq 'branding/brand.svg' "$ARANEA_TEST_SANDBOX/deploy.err"
grep -Fq 'scripts/install.sh' "$ARANEA_TEST_SANDBOX/deploy.err"
test -f "$target/araneadev.shared/BrandConfig.qml"
cp "$repo_root/branding/brand.svg" "$active/branding/brand.svg"
"$repo_root/scripts/deploy-plugins-safely" "$source_root" "$target" 2>"$ARANEA_TEST_SANDBOX/deploy.err"
if grep -Fq 'branding/' "$ARANEA_TEST_SANDBOX/deploy.err"; then
  echo "deploy warned although the theme has every branding file" >&2
  exit 1
fi

echo "brand assets contract passed"
