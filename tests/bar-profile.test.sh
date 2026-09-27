#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
config_root="$(mktemp -d)"
config_file="$config_root/shell.json"
printf '%s\n' '{"bar":{"id":"araneadev.bar"},"plugins":[]}' >"$config_file"

list_output="$("$repo_root"/scripts/aranea-bar-profile list)"
grep -Fxq minimal <<<"$list_output"
grep -Fxq diagnostic <<<"$list_output"
grep -Fxq ceremony <<<"$list_output"
[[ "$(ARANEA_SHELL_CONFIG="$config_file" "$repo_root/scripts/aranea-bar-profile" current)" == minimal ]]
set_output="$(ARANEA_SHELL_CONFIG="$config_file" "$repo_root/scripts/aranea-bar-profile" set diagnostic)"
grep -Fq 'bar profile: diagnostic' <<<"$set_output"
[[ "$(jq -r '.bar.profile' "$config_file")" == diagnostic ]]
test -f "$config_file.aranea-profile.bak"
if ARANEA_SHELL_CONFIG="$config_file" "$repo_root/scripts/aranea-bar-profile" set invalid >/dev/null 2>&1; then
  echo "invalid bar profile unexpectedly succeeded" >&2
  exit 1
fi

# A symlinked shell.json stays a symlink (Review Focus 5).
real_profile_cfg="$(mktemp -d)/shell.json"
printf '{"bar": {}}\n' >"$real_profile_cfg"
linked_profile_cfg="$(mktemp -d)/shell.json"
ln -s "$real_profile_cfg" "$linked_profile_cfg"
ARANEA_SHELL_CONFIG="$linked_profile_cfg" "$repo_root/scripts/aranea-bar-profile" set ceremony >/dev/null
test -L "$linked_profile_cfg"
jq -e '.bar.profile == "ceremony"' "$real_profile_cfg" >/dev/null
echo "bar profile contract passed"
