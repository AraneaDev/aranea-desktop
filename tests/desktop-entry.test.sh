#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

source_file="$test_root/teams-for-linux.desktop"
target_file="$test_root/applications/teams-for-linux.desktop"
cat > "$source_file" <<'EOF'
[Desktop Entry]
Type=Application
Name=Microsoft Teams for Linux
Version=0.1.9
Exec=teams-for-linux --gtk-version=3 %U
Icon=teams-for-linux
Categories=Network;Chat;InstantMessaging;Application;
EOF

"$repo_root/scripts/repair-desktop-entry" "$source_file" "$target_file"

grep -Fq 'Name=Microsoft Teams for Linux' "$target_file"
grep -Fq 'Exec=teams-for-linux --gtk-version=3 %U' "$target_file"
grep -Fq 'Version=' "$target_file" && exit 1
grep -Fq 'Application;' "$target_file" && exit 1

echo "desktop entry repair contract passed"
