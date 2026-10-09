#!/usr/bin/env bash

set -euo pipefail

# Ownership ledger for files Aranea installs into the user's home: records
# managed targets, backs up what they replaced, tells Aranea's links apart
# from user customisations, and restores the backups on deactivate or
# uninstall. ARANEA_OWNERSHIP_ROOT overrides the state dir.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"

# Prints the state dir that holds the ledger and the backups.
aranea_ownership_root() {
  printf '%s\n' "${ARANEA_OWNERSHIP_ROOT:-$(aranea_state_root)}"
}

# Prints the path of the managed-files ledger.
ownership_record() {
  printf '%s/managed-files\n' "$(aranea_ownership_root)"
}

# Prints where the backup of absolute path TARGET is kept.
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
    # Only this exact command target is managed; scripts directories contain
    # unrelated helpers and must never become general ownership roots.
    [[ "$destination" == "$HOME/.config/omarchy/themes/aranea/scripts/aranea" ]] && return 0
    while IFS= read -r root; do
      [[ "$destination" == "$root"/* ]] && return 0
    done < <(aranea_link_roots)
    # Any other Aranea checkout (the README has users run the integration
    # controller from one): an .../integrations/<path> that this theme ships,
    # even when that checkout is gone and the link dangles.
    # The theme files the hooks link at the current theme (link_theme_files).
    local theme_link
    while IFS= read -r theme_link; do
      [[ "$destination" == "${theme_link#* }" ]] && return 0
    done < <(aranea_theme_links)
    if [[ "$destination" == */integrations/* ]]; then
      [[ -e "$ownership_lib_repo/integrations/${destination##*/integrations/}" ]] && return 0
    fi
    return 1
  fi
  local data_root
  data_root="$(xdg_data_home)"
  [[ "$target" == "$data_root/icons/Aranea/"* || "$target" == "$data_root/icons/Aranea-icons/"* ]]
}

# Prints "target source" for each file the hooks point at the current theme:
# GTK 3 and 4 css, the cava colours and the screensaver text. Omarchy does not
# manage these, so Aranea links them as managed files.
aranea_theme_links() {
  local current="$HOME/.local/state/omarchy/current/theme"
  printf '%s %s\n' \
    "$HOME/.config/gtk-4.0/gtk.css" "$current/gtk.css" \
    "$HOME/.config/gtk-3.0/gtk.css" "$current/gtk.css" \
    "$HOME/.config/cava/config" "$current/cava-theme" \
    "$HOME/.config/omarchy/branding/screensaver.txt" "$current/branding/screensaver.txt"
}

# Links the theme files (aranea_theme_links) as managed files: an existing
# file is backed up and restored on uninstall, and a later user change is
# kept (link_managed_file).
link_theme_files() {
  local target source
  while read -r target source; do
    link_managed_file "$target" "$source"
  done < <(aranea_theme_links)
}

# True when TARGET is in the managed-files ledger.
is_recorded_target() {
  local record
  record="$(ownership_record)"
  [[ -f "$record" ]] && grep -Fqx -- "$1" "$record"
}

# Copies TARGET to its backup path unless TARGET is missing or a backup
# already exists.
backup_target() {
  local target="$1"
  local backup
  backup="$(backup_path "$target")"
  [[ -e "$target" || -L "$target" ]] || return 0
  [[ -e "$backup" || -L "$backup" ]] && return 0
  mkdir -p "$(dirname "$backup")"
  cp -a "$target" "$backup"
}

# Adds TARGET to the ledger unless it is already there.
record_managed_file() {
  local target="$1"
  local record
  record="$(ownership_record)"
  mkdir -p "$(dirname "$record")"
  touch "$record"
  grep -Fqx -- "$target" "$record" || printf '%s\n' "$target" >>"$record"
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
  grep -Fvx -- "$target" "$record" >"$tmp" || true
  mv "$tmp" "$record"
}

# Points TARGET at SOURCE and records it. A pre-Aranea file is backed up
# first (an older backup is kept under a timestamped name, never lost); a
# managed target the user has since replaced (customised), or a directory,
# is left alone. Sets ownership_last_action to "linked" or "kept".
link_managed_file() {
  local target="$1"
  local source="$2"
  local backup
  backup="$(backup_path "$target")"
  mkdir -p "$(dirname "$target")"
  if [[ -L "$target" && "$(readlink -- "$target")" == "$source" ]]; then
    record_managed_file "$target"
    ownership_last_action=linked
    return 0
  fi
  if [[ -d "$target" && ! -L "$target" ]]; then
    ownership_last_action=kept
    return 0
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    if ! is_aranea_target "$target"; then
      if is_recorded_target "$target"; then
        # Still managed but no longer ours: customised, unless it is exactly
        # the original an older uninstall restored (identical to its backup).
        if ! { [[ -f "$target" && -f "$backup" ]] && cmp -s -- "$target" "$backup"; }; then
          ownership_last_action=kept
          return 0
        fi
      else
        # First adoption. A backup left from an earlier install must not
        # stop this file from being backed up.
        if [[ -e "$backup" || -L "$backup" ]] && ! { [[ -f "$target" && -f "$backup" ]] && cmp -s -- "$target" "$backup"; }; then
          mv -- "$backup" "$backup.$(date +%Y%m%d%H%M%S)"
        fi
        backup_target "$target"
      fi
    fi
    rm -f -- "$target"
  fi
  ln -s -- "$source" "$target"
  record_managed_file "$target"
  ownership_last_action=linked
}

# Prints what the last link_managed_file / restore_one_target call did:
# "linked", "restored" or "kept".
last_ownership_action() {
  printf '%s\n' "$ownership_last_action"
}

# Hands one managed TARGET back: Aranea's (or missing) is removed and its
# backup restored and deleted; a customised one is left as it is, with its
# backup kept, and reported as "kept your <target>". Sets
# ownership_last_action to "restored" or "kept".
restore_one_target() {
  local target="$1" backup
  backup="$(backup_path "$target")"
  if [[ -e "$target" || -L "$target" ]] && ! is_aranea_target "$target"; then
    printf 'kept your %s
' "$target"
    ownership_last_action=kept
    return 0
  fi
  rm -f -- "$target"
  if [[ -e "$backup" || -L "$backup" ]]; then
    mkdir -p "$(dirname "$target")"
    cp -a -- "$backup" "$target"
    rm -rf -- "$backup"
  fi
  ownership_last_action=restored
}

# Hands every managed target back (uninstall). Customised targets stay in
# the ledger, so a later reinstall keeps them too; everything else leaves it,
# so a second run is a no-op and a reinstall starts clean.
restore_managed_files() {
  local record target kept_file
  record="$(ownership_record)"
  [[ -f "$record" ]] || return 0
  kept_file="$(mktemp "$(dirname "$record")/.managed-files.XXXXXX")"
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    restore_one_target "$target"
    if [[ "$ownership_last_action" == kept ]]; then printf '%s
' "$target" >>"$kept_file"; fi
  done <"$record"
  mv -- "$kept_file" "$record"
}

# Deletes TARGET (the Teams desktop-entry override older Aranea versions
# wrote) when it is exactly what Aranea generated from SOURCE: the system
# entry without its Version= line and without the Application category. A
# copy the user edited, or a missing SOURCE, leaves TARGET alone.
remove_teams_override() {
  local source="$1" target="$2" generated
  [[ -f "$source" && -f "$target" ]] || return 0
  generated="$(awk '
    /^Version=/ { next }
    /^Categories=/ {
      value = $0
      sub(/^Categories=/, "", value)
      gsub(/(^|;)Application(;|$)/, ";", value)
      gsub(/;;+/, ";", value)
      sub(/^;/, "", value)
      sub(/;$/, "", value)
      print "Categories=" value ";"
      next
    }
    { print }
  ' "$source")"
  [[ "$generated" == "$(<"$target")" ]] && rm -f -- "$target"
  return 0
}
