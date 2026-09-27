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
printf 'user setting\n' >"$target"
link_managed_file "$target" "$src"
[[ "$(last_ownership_action)" == linked ]]
test -L "$target"
grep -Fq 'user setting' "$state/backups$target"
grep -Fqx -- "$target" "$state/managed-files"

# Links into the repo checkout, the stable theme or current/theme are Aranea's (Review Focus 2).
is_aranea_target "$target"
stable="$HOME/.config/omarchy/themes/aranea/integrations"
mkdir -p "$stable/x"
: >"$stable/x/f"
current="$HOME/.local/state/omarchy/current/theme/integrations"
mkdir -p "$current/x"
: >"$current/x/f"
ln -s "$stable/x/f" "$HOME/l1"
ln -s "$current/x/f" "$HOME/l2"
ln -s /etc/hostname "$HOME/l3"
is_aranea_target "$HOME/l1"
is_aranea_target "$HOME/l2"
if is_aranea_target "$HOME/l3"; then
  echo "foreign link counted as Aranea's" >&2
  exit 1
fi
icon="$HOME/.local/share/icons/Aranea-icons/scalable/a.svg"
mkdir -p "$(dirname "$icon")"
: >"$icon"
is_aranea_target "$icon"

# An old current/theme link is migrated to the new source.
migr="$HOME/.config/migr.conf"
ln -s "$current/x/f" "$migr"
record_managed_file "$migr"
link_managed_file "$migr" "$src"
[[ "$(readlink "$migr")" == "$src" && "$(last_ownership_action)" == linked ]]

# Customised: the user replaced a managed link with their own file → kept (spec B1).
rm "$target"
printf 'my edit\n' >"$target"
link_managed_file "$target" "$src"
[[ "$(last_ownership_action)" == kept ]]
grep -Fq 'my edit' "$target"
grep -Fq 'user setting' "$state/backups$target"

# Uninstall: customised stays, Aranea's links go and backups come back; the
# ledger is emptied, a second run is a no-op (spec B2).
plain="$HOME/.config/plain.conf"
printf 'orig\n' >"$plain"
link_managed_file "$plain" "$src"
out="$(restore_managed_files)"
grep -Fq "kept your $target" <<<"$out"
grep -Fq 'my edit' "$target"
grep -Fq 'orig' "$plain" && test ! -L "$plain"
test ! -e "$state/backups$plain"
# Only the customised target stays in the ledger, so a reinstall keeps it too.
[[ "$(cat "$state/managed-files")" == "$target" ]] || {
  echo "ledger should hold only the kept target" >&2
  cat "$state/managed-files"
  exit 1
}
printf 'later\n' >"$plain"
restore_managed_files
grep -Fq 'later' "$plain"

# forget_managed_file stays exact.
record_managed_file "$HOME/a"
record_managed_file "$HOME/b"
forget_managed_file "$HOME/a"
if grep -Fqx -- "$HOME/a" "$state/managed-files"; then
  echo "forget left the entry" >&2
  exit 1
fi
grep -Fqx -- "$HOME/b" "$state/managed-files"
forget_managed_file "$HOME/never"

# --- final review fixes
# C1: a customised file survives uninstall -> reinstall.
c1="$HOME/.config/c1.conf"
printf 'PRE\n' >"$c1"
link_managed_file "$c1" "$src"
rm "$c1"
printf 'CUSTOM\n' >"$c1"
restore_managed_files >/dev/null
link_managed_file "$c1" "$src"
grep -Fq CUSTOM "$c1" || {
  echo "customised file lost on reinstall" >&2
  exit 1
}
[[ "$(last_ownership_action)" == kept ]]
# C1: a stale backup never lets a first adoption delete the only copy.
c1b="$HOME/.config/c1b.conf"
mkdir -p "$(dirname "$state/backups$c1b")"
printf 'OLD\n' >"$state/backups$c1b"
printf 'NEW\n' >"$c1b"
link_managed_file "$c1b" "$src"
test -L "$c1b"
grep -Fq NEW "$state/backups$c1b" || {
  echo "current file not backed up" >&2
  exit 1
}
compgen -G "$state/backups$c1b.*" >/dev/null || {
  echo "old backup not kept" >&2
  exit 1
}
# I2: a link into any Aranea checkout's integrations is Aranea's, even dangling.
other="$ARANEA_TEST_SANDBOX/other-checkout/integrations/session"
mkdir -p "$other"
: >"$other/omarchy.css"
c3="$HOME/.config/c3.css"
ln -s "$other/omarchy.css" "$c3"
is_aranea_target "$c3"
rm -rf "$ARANEA_TEST_SANDBOX/other-checkout"
is_aranea_target "$c3"
ln -s "$ARANEA_TEST_SANDBOX/elsewhere/integrations/not-ours.css" "$HOME/.config/c3b.css"
if is_aranea_target "$HOME/.config/c3b.css"; then
  echo "unknown integrations path counted as Aranea's" >&2
  exit 1
fi
# M4: a restored original left in the ledger by an old uninstall is adopted again.
c4="$HOME/.config/c4.conf"
printf 'ORIG\n' >"$c4"
record_managed_file "$c4"
mkdir -p "$(dirname "$state/backups$c4")"
cp "$c4" "$state/backups$c4"
link_managed_file "$c4" "$src"
test -L "$c4"
# M7: a directory at the target is kept, never removed.
c5="$HOME/.config/c5"
mkdir -p "$c5/inner"
link_managed_file "$c5" "$src"
test -d "$c5/inner"
[[ "$(last_ownership_action)" == kept ]]
echo "ownership contract passed"
