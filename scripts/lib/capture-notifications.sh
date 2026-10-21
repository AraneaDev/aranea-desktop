#!/usr/bin/env bash
# shellcheck disable=SC2154 # Caller supplies the notification paths documented below.
# Notification preservation transaction for capture-screenshots. Sourced, not run.
#
# Initialization contract: before calling these helpers, the caller sets
# notification_state_dir and its notification_inbox_dir / notification_images_dir
# paths, provides stop_omarchy_shell (success only after every shell has stopped),
# and makes the shell lifecycle commands `omarchy restart shell` and
# `omarchy-hyprland-session-locked` available. The caller owns traps, the swapped
# flag passed to park_notification_inbox, and restarting the shell after restore.
# Sourcing only defines functions; it does not initialize paths or touch files.

# Prints every entry (dotfiles included) directly inside dir $1, one per
# line, NUL-terminated.
dir_entries() {
  find "$1" -mindepth 1 -maxdepth 1 -print0 2>/dev/null
}

# Moves the real notification inbox (entries and images) into backup dir $1
# while the shell is stopped, sets the caller's swapped flag (variable named
# $2) to 1 the moment the move is done, then restarts the shell on the empty
# inbox. Fails with nothing parked when the shell cannot be stopped (the shell
# is restarted unless the session is locked, as the stop may already have
# killed instances); a failed move is rolled back, and anything the rollback
# could not move stays in the backup (see remove_empty_backup).
park_notification_inbox() {
  local backup="$1" flag="$2" dir file
  if ! stop_omarchy_shell; then
    omarchy-hyprland-session-locked >/dev/null 2>&1 || omarchy restart shell >/dev/null 2>&1 || true
    return 1
  fi
  mkdir -p "$backup/inbox" "$backup/images" "$notification_inbox_dir" "$notification_images_dir"
  if ! { find "$notification_inbox_dir" -maxdepth 1 -name '*.json' -exec mv -t "$backup/inbox" {} + &&
    find "$notification_images_dir" -mindepth 1 -maxdepth 1 -exec mv -t "$backup/images" {} +; }; then
    for dir in inbox images; do
      while IFS= read -r -d '' file; do
        mv -n -- "$file" "$notification_state_dir/$dir/" || true
      done < <(dir_entries "$backup/$dir")
    done
    omarchy restart shell >/dev/null 2>&1 || true
    return 1
  fi
  printf -v "$flag" 1
  omarchy restart shell >/dev/null 2>&1 || true
}

# Puts the notification inbox parked in backup dir $1 back. With every shell
# instance stopped (so no queued job of the capture shell survives), it drops
# the capture entries and images, copies every parked file (dotfiles too)
# back and checks each one; only then is the backup handed off (renamed, then
# deleted), so a rerun never deletes verified files. When the shell cannot be
# stopped or a file does not match, nothing more is touched and the backup is
# kept and named. Rerunning after an interruption is safe. The caller
# restarts the shell.
restore_parked_inbox() {
  local backup="$1" dir file
  [[ -d "$backup" ]] || return 0
  if ! stop_omarchy_shell; then
    printf 'notification inbox not restored (shell still running / session locked); your notifications are kept in %s\n' "$backup" >&2
    return 1
  fi
  mkdir -p "$notification_inbox_dir" "$notification_images_dir"
  find "$notification_inbox_dir" -maxdepth 1 -name '*.json' -delete 2>/dev/null || true
  find "$notification_images_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
  for dir in inbox images; do
    while IFS= read -r -d '' file; do
      cp -p -- "$file" "$notification_state_dir/$dir/" 2>/dev/null || true
    done < <(dir_entries "$backup/$dir")
  done
  for dir in inbox images; do
    while IFS= read -r -d '' file; do
      cmp -s -- "$file" "$notification_state_dir/$dir/${file##*/}" || {
        printf 'notification inbox not fully restored; your notifications are kept in %s\n' "$backup" >&2
        return 1
      }
    done < <(dir_entries "$backup/$dir")
  done
  # Every file is back: a leftover of the backup is no longer needed.
  rm -rf -- "$backup.restored" 2>/dev/null || true
  if ! mv -- "$backup" "$backup.restored"; then
    printf 'notification inbox restored; its backup %s could not be removed, delete it yourself\n' "$backup" >&2
    return 0
  fi
  rm -rf -- "$backup.restored" 2>/dev/null ||
    printf 'notification inbox restored; delete the leftover %s yourself\n' "$backup.restored" >&2
  return 0
}

# Removes an unused park backup dir $1 (rmdir only: never deletes files).
# When files are left in it (a park whose rollback could not move them all
# back), it is kept and named, and this fails.
remove_empty_backup() {
  rmdir -- "$1/inbox" "$1/images" 2>/dev/null || true
  rmdir -- "$1" 2>/dev/null && return 0
  [[ -d "$1" ]] || return 0
  printf 'notification files from an aborted park are kept in %s; move them back into %s\n' "$1" "$notification_state_dir" >&2
  return 1
}
