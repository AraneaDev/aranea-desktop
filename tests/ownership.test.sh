#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
source "$repo_root/scripts/lib/ownership.sh"

state="$HOME/.local/state/aranea"
source_dir="$repo_root/integrations/session"
src="$source_dir/omarchy.css"

# First adoption: a pre-Aranea user file is backed up, then linked (Review Focus 1).
target="$HOME/.config/example.conf"
mkdir -p "$(dirname "$target")"
printf 'user setting\n' > "$target"
link_managed_file "$target" "$src"
[[ "$(last_ownership_action)" == linked ]]
test -L "$target"
grep -Fq 'user setting' "$state/backups$target"
grep -Fqx -- "$target" "$state/managed-files"

# Links into the repo checkout, the stable theme or current/theme are Aranea's (Review Focus 2).
is_aranea_target "$target"
stable="$HOME/.config/omarchy/themes/aranea/integrations"; mkdir -p "$stable/x"; : > "$stable/x/f"
current="$HOME/.local/state/omarchy/current/theme/integrations"; mkdir -p "$current/x"; : > "$current/x/f"
ln -s "$stable/x/f" "$HOME/l1"; ln -s "$current/x/f" "$HOME/l2"; ln -s /etc/hostname "$HOME/l3"
is_aranea_target "$HOME/l1"; is_aranea_target "$HOME/l2"
if is_aranea_target "$HOME/l3"; then echo "foreign link counted as Aranea's" >&2; exit 1; fi
icon="$HOME/.local/share/icons/Aranea-icons/scalable/a.svg"; mkdir -p "$(dirname "$icon")"; : > "$icon"
is_aranea_target "$icon"

# An old current/theme link is migrated to the new source.
migr="$HOME/.config/migr.conf"; ln -s "$current/x/f" "$migr"; record_managed_file "$migr"
link_managed_file "$migr" "$src"
[[ "$(readlink "$migr")" == "$src" && "$(last_ownership_action)" == linked ]]

# Customised: the user replaced a managed link with their own file → kept (spec B1).
rm "$target"; printf 'my edit\n' > "$target"
link_managed_file "$target" "$src"
[[ "$(last_ownership_action)" == kept ]]
grep -Fq 'my edit' "$target"
grep -Fq 'user setting' "$state/backups$target"

# Uninstall: customised stays, Aranea's links go and backups come back; the
# ledger is emptied, a second run is a no-op (spec B2).
plain="$HOME/.config/plain.conf"; printf 'orig\n' > "$plain"
link_managed_file "$plain" "$src"
out="$(restore_managed_files)"
grep -Fq "kept your $target" <<<"$out"
grep -Fq 'my edit' "$target"
grep -Fq 'orig' "$plain" && test ! -L "$plain"
test ! -e "$state/backups$plain"
test ! -s "$state/managed-files" || { echo "ledger not emptied" >&2; exit 1; }
printf 'later\n' > "$plain"
restore_managed_files
grep -Fq 'later' "$plain"

# forget_managed_file stays exact.
record_managed_file "$HOME/a"; record_managed_file "$HOME/b"
forget_managed_file "$HOME/a"
if grep -Fqx -- "$HOME/a" "$state/managed-files"; then echo "forget left the entry" >&2; exit 1; fi
grep -Fqx -- "$HOME/b" "$state/managed-files"
forget_managed_file "$HOME/never"

echo "ownership contract passed"
