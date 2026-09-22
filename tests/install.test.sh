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

echo "installer dry-run contract passed"
