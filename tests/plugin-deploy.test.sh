#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

source_dir="$work_dir/source"
target_dir="$work_dir/target"
mkdir -p "$source_dir" "$target_dir"
printf '%s\n' manifest > "$source_dir/manifest.json"
printf '%s\n' qml > "$source_dir/Widget.qml"
printf '%s\n' stale > "$target_dir/stale.txt"

"$repo_root/scripts/deploy-plugin" "$source_dir" "$target_dir"

[[ -f "$target_dir/manifest.json" ]]
[[ -f "$target_dir/Widget.qml" ]]
[[ ! -e "$target_dir/stale.txt" ]]
if find "$work_dir" -maxdepth 1 -name '.target.stage.*' -print -quit | grep -q .; then
  echo "staging directory leaked" >&2
  exit 1
fi

echo "plugin deploy contract passed"
