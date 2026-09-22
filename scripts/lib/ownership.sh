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

link_managed_file() {
  local target="$1"
  local source="$2"
  backup_target "$target"
  mkdir -p "$(dirname "$target")"
  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    record_managed_file "$target"
    return 0
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    rm -f -- "$target"
  fi
  ln -s -- "$source" "$target"
  record_managed_file "$target"
}

restore_managed_files() {
  local record
  local target
  record="$(ownership_record)"
  [[ -f "$record" ]] || return 0
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    if [[ -e "$target" || -L "$target" ]]; then
      rm -f -- "$target"
    fi
    local backup
    backup="$(backup_path "$target")"
    if [[ -e "$backup" || -L "$backup" ]]; then
      mkdir -p "$(dirname "$target")"
      cp -a "$backup" "$target"
    fi
  done < "$record"
}
