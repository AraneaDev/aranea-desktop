#!/usr/bin/env bash
# Contract for the retired Teams desktop-entry override: the hooks no longer
# write it, and the cleanup (ownership.sh remove_teams_override) deletes an
# override only when it is exactly what Aranea generated, so a user's own
# edited copy stays.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/scripts/lib/ownership.sh"

[[ ! -e "$repo_root/scripts/repair-desktop-entry" ]]
if grep -Fq 'repair-desktop-entry' "$repo_root/hooks/theme-set" "$repo_root/hooks/post-boot"; then
  echo "the hooks must not write the Teams override any more" >&2
  exit 1
fi
grep -Fq 'remove_teams_override' "$repo_root/hooks/post-boot"
grep -Fq 'remove_teams_override' "$repo_root/scripts/uninstall.sh"

source_file="$ARANEA_TEST_SANDBOX/teams-for-linux.desktop"
target_file="$ARANEA_TEST_SANDBOX/applications/teams-for-linux.desktop"
mkdir -p "$(dirname "$target_file")"
cat >"$source_file" <<'DESKTOP'
[Desktop Entry]
Version=1.0
Name=Microsoft Teams for Linux
Exec=teams-for-linux --gtk-version=3 %U
Icon=teams-for-linux
Categories=Application;Network;Chat;
DESKTOP

# Aranea's generated override (no Version=, no Application category) goes.
cat >"$target_file" <<'DESKTOP'
[Desktop Entry]
Name=Microsoft Teams for Linux
Exec=teams-for-linux --gtk-version=3 %U
Icon=teams-for-linux
Categories=Network;Chat;
DESKTOP
remove_teams_override "$source_file" "$target_file"
[[ ! -e "$target_file" ]]

# A copy the user edited stays.
printf '[Desktop Entry]\nName=My Teams\n' >"$target_file"
remove_teams_override "$source_file" "$target_file"
[[ -e "$target_file" ]]

# No system entry or no override: nothing happens.
remove_teams_override "$ARANEA_TEST_SANDBOX/missing.desktop" "$target_file"
[[ -e "$target_file" ]]

echo "desktop entry contract passed"
