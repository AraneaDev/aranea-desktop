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

echo "installer dry-run contract passed"
