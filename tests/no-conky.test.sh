#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Conky is gone: only the changelog and design docs may still mention it.
hits="$(git -C "$repo_root" grep -Iil conky -- . ':!CHANGELOG.md' ':!docs' ':!tests/no-conky.test.sh' ':!scripts/remove-legacy-diagnostics' || true)"
if [[ -n "$hits" ]]; then
  printf 'conky still referenced in:\n%s\n' "$hits" >&2
  exit 1
fi
for gone in conky.conf scripts/write-conky-gradient-border scripts/aranea-diagnostics-toggle screenshots/diagnostics.png; do
  test ! -e "$repo_root/$gone"
done

# Leftover cleanup removes only what Aranea installed (Review Focus 5).
home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT
mkdir -p "$home/.config/conky" "$home/.local/bin" "$home/state/omarchy/current/theme"
ln -s "$home/state/omarchy/current/theme/conky.conf" "$home/.config/conky/conky.conf"
printf '%s\n' "-- Draws conky's hairline border as the theme's signature mint -> violet" 'x' > "$home/.config/conky/gradient-border.lua"
printf '#!/bin/sh\n' > "$home/.local/bin/aranea-diagnostics-toggle"
mkdir -p "$home/state/aranea" && printf '{"version":1,"muted":[]}\n' > "$home/state/aranea/health.json"
HOME="$home" XDG_STATE_HOME="$home/state" "$repo_root/scripts/remove-legacy-diagnostics"
test ! -e "$home/.config/conky" && test ! -e "$home/.local/bin/aranea-diagnostics-toggle"
# 1.7.0's health mutes are obsolete now that health lives only in its dropdown.
test ! -e "$home/state/aranea/health.json"

# A user's own conky config survives.
mkdir -p "$home/.config/conky"
printf 'conky.config = {}\n' > "$home/.config/conky/conky.conf"
printf '%s\n' '-- my own lua' > "$home/.config/conky/gradient-border.lua"
HOME="$home" XDG_STATE_HOME="$home/state" "$repo_root/scripts/remove-legacy-diagnostics"
test -f "$home/.config/conky/conky.conf" && test -f "$home/.config/conky/gradient-border.lua"

# A Conky started by the old toggle (config = Aranea's symlink) is stopped;
# the match is on that exact config path, so a user's own Conky survives.
# shellcheck disable=SC2016 # matching the script's literal text, not expanding it
grep -Fq 'pkill -f -- "conky -c $conky_dir/conky.conf"' "$repo_root/scripts/remove-legacy-diagnostics"

echo "no-conky contract passed"
