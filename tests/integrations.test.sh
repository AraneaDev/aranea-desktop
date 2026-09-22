#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if "$repo_root/scripts/install-integration" --dry-run missing-integration 2>"$repo_root/tests/.integration-error"; then
  echo "unknown integration unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Unknown integration' "$repo_root/tests/.integration-error"
rm -f "$repo_root/tests/.integration-error"

for file in alacritty.toml kitty.conf foot.ini; do
  test -f "$repo_root/$file"
done
grep -Fq 'integrations/terminal/alacritty.toml' "$repo_root/alacritty.toml"
grep -Fq 'integrations/terminal/kitty.conf' "$repo_root/kitty.conf"
grep -Fq 'integrations/terminal/foot.ini' "$repo_root/foot.ini"

qt_output="$($repo_root/scripts/install-integration qt --dry-run)"
grep -Eq 'Skipping qt:|would link .*Aranea\.kvconfig' <<<"$qt_output"

echo "integration contract passed"
