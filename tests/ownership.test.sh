#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/ownership.sh"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

export ARANEA_OWNERSHIP_ROOT="$test_root/state"
target="$test_root/config/example.conf"
mkdir -p "$(dirname "$target")"
printf 'user setting\n' > "$target"

backup_target "$target"
link_managed_file "$target" "$repo_root/colors.toml"

test -L "$target"
backup="$test_root/state/backups$target"
test -f "$backup"
grep -Fq 'user setting' "$backup"
grep -Fq "$target" "$test_root/state/managed-files"

restore_managed_files
test ! -L "$target"
grep -Fq 'user setting' "$target"

# forget_managed_file is the inverse of record_managed_file: it must drop the
# exact entry without disturbing the others, and be a no-op for an entry that
# isn't present.
other_target="$test_root/config/other.conf"
mkdir -p "$(dirname "$other_target")"
: > "$other_target"
record_managed_file "$other_target"
grep -Fqx -- "$target" "$test_root/state/managed-files"
grep -Fqx -- "$other_target" "$test_root/state/managed-files"

forget_managed_file "$target"
grep -Fqx -- "$target" "$test_root/state/managed-files" && exit 1
grep -Fqx -- "$other_target" "$test_root/state/managed-files"

forget_managed_file "$test_root/config/never-recorded.conf"
grep -Fqx -- "$other_target" "$test_root/state/managed-files"

echo "ownership contract passed"
