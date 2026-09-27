#!/usr/bin/env bash

set -euo pipefail

aranea_ownership_root() {
  printf '%s\n' "${ARANEA_OWNERSHIP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/aranea}"
}

ownership_record() {
  printf '%s/managed-files\n' "$(aranea_ownership_root)"
}

backup_path() {
  local target="$1"
  printf '%s/backups%s\n' "$(aranea_ownership_root)" "$target"
}

ownership_lib_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ownership_last_action=""

# Prints the directories an Aranea integration symlink may point into: this
# checkout, the stable installed theme and Omarchy's current-theme copy
# (where older installs linked from).
aranea_link_roots() {
  printf '%s\n' "$ownership_lib_repo/integrations" \
    "$HOME/.config/omarchy/themes/aranea/integrations" \
    "$HOME/.local/state/omarchy/current/theme/integrations"
}

# True when TARGET is Aranea's: a symlink into one of aranea_link_roots, or a
# file inside a directory Aranea owns outright (its cursor and icon themes).
is_aranea_target() {
  local target="$1" destination root
  if [[ -L "$target" ]]; then
    destination="$(readlink -- "$target")"
    while IFS= read -r root; do
      [[ "$destination" == "$root"/* ]] && return 0
    done < <(aranea_link_roots)
    return 1
  fi
  local data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
  [[ "$target" == "$data_root/icons/Aranea/"* || "$target" == "$data_root/icons/Aranea-icons/"* ]]
}

# True when TARGET is in the managed-files ledger.
is_recorded_target() {
  local record
  record="$(ownership_record)"
  [[ -f "$record" ]] && grep -Fqx -- "$1" "$record"
}

backup_target() {
  local target="$1"
  local backup
  backup="$(backup_path "$target")"
  [[ -e "$target" || -L "$target" ]] || return 0
  [[ -e "$backup" || -L "$backup" ]] && return 0
  mkdir -p "$(dirname "$backup")"
  cp -a "$target" "$backup"
}

record_managed_file() {
  local target="$1"
  local record
  record="$(ownership_record)"
  mkdir -p "$(dirname "$record")"
  touch "$record"
  grep -Fqx -- "$target" "$record" || printf '%s\n' "$target" >> "$record"
}

# The inverse of record_managed_file, for a caller that has just removed a
# target it no longer manages (e.g. an icon dropped by an icon-set rebuild).
# Without this, the ledger only ever grows, and aranea-doctor's ownership
# check reports a permanent false "repair" for every entry an integration
# update intentionally removed.
forget_managed_file() {
  local target="$1"
  local record
  record="$(ownership_record)"
  [[ -f "$record" ]] || return 0
  local tmp
  tmp="$(mktemp "$(dirname "$record")/.managed-files.XXXXXX")"
  grep -Fvx -- "$target" "$record" > "$tmp" || true
  mv "$tmp" "$record"
}

# Points TARGET at SOURCE and records it. A pre-Aranea file is backed up
# first; a managed target the user has since replaced (customised) is left
# alone. Sets ownership_last_action to "linked" or "kept".
link_managed_file() {
  local target="$1"
  local source="$2"
  mkdir -p "$(dirname "$target")"
  if [[ -L "$target" && "$(readlink -- "$target")" == "$source" ]]; then
    record_managed_file "$target"
    ownership_last_action=linked
    return 0
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    if ! is_aranea_target "$target"; then
      if is_recorded_target "$target"; then
        ownership_last_action=kept
        return 0
      fi
      backup_target "$target"
    fi
    rm -f -- "$target"
  fi
  ln -s -- "$source" "$target"
  record_managed_file "$target"
  ownership_last_action=linked
}

# Prints what the last link_managed_file call did: "linked" or "kept".
last_ownership_action() {
  printf '%s\n' "$ownership_last_action"
}

# Hands one managed TARGET back: Aranea's (or missing) is removed and its
# backup restored and deleted; a customised one is left as it is, with its
# backup kept, and reported as "kept your <target>".
restore_one_target() {
  local target="$1" backup
  backup="$(backup_path "$target")"
  if [[ -e "$target" || -L "$target" ]] && ! is_aranea_target "$target"; then
    printf 'kept your %s\n' "$target"
    return 0
  fi
  rm -f -- "$target"
  if [[ -e "$backup" || -L "$backup" ]]; then
    mkdir -p "$(dirname "$target")"
    cp -a -- "$backup" "$target"
    rm -rf -- "$backup"
  fi
}

# Hands every managed target back (uninstall) and empties the ledger, so a
# second run is a no-op and a later reinstall starts clean.
restore_managed_files() {
  local record target
  record="$(ownership_record)"
  [[ -f "$record" ]] || return 0
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    restore_one_target "$target"
  done < "$record"
  : > "$record"
}
