#!/usr/bin/env bash
# Behaviour of `scripts/capture-screenshots --all` with every surface capture
# replaced (ARANEA_CAPTURE_SURFACE_COMMAND) and the desktop stubbed: a failed
# surface keeps its previous PNG, is listed at the end and fails the batch,
# the hero GIF is rebuilt only when every surface worked, and the parked
# notification inbox (entries and images) always comes back byte for byte, or
# stays in its backup with a message when the shell cannot be stopped.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

capture="$repo_root/scripts/capture-screenshots"
bin="$ARANEA_TEST_SANDBOX/capture-bin"
out="$ARANEA_TEST_SANDBOX/shots"
notifications="$HOME/.local/state/omarchy/notifications"
inbox="$notifications/inbox"
images="$notifications/images"
real="$ARANEA_TEST_SANDBOX/real"
backups="$XDG_STATE_HOME/aranea"
mkdir -p "$bin" "$out" "$inbox" "$images" "$real"

# hyprctl on workspace 2; anything else it is asked is only logged.
cat >"$bin/hyprctl" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == activeworkspace ]]; then
  printf '{"id":2}\n'
else
  printf 'hyprctl %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/guard.log"
fi
SH
# magick records that the hero GIF was built and writes it.
cat >"$bin/magick" <<'SH'
#!/usr/bin/env bash
printf 'built\n' >"${@: -1}"
SH
# Writes <surface>.png, except for the surfaces listed in CAPTURE_FAILS. Like
# the real notifications surface it drops a capture entry and its image into
# the inbox. STICK_SHELL=1 makes the fake shell unkillable from then on.
cat >"$bin/fake-surface" <<'SH'
#!/usr/bin/env bash
[[ " ${CAPTURE_FAILS:-} " == *" $1 "* ]] && exit 1
printf 'new %s\n' "$1" >"$2/$1.png"
if [[ "$1" == notifications ]]; then
  dir="$HOME/.local/state/omarchy/notifications"
  mkdir -p "$dir/inbox" "$dir/images"
  printf 'fixture\n' >"$dir/inbox/9-9.json"
  printf 'fixture image\n' >"$dir/images/9-9-0.png"
  [[ "${STICK_SHELL:-0}" == 1 ]] && touch "$ARANEA_TEST_SANDBOX/shell-stuck"
fi
exit 0
SH
# omarchy-shell clears the notification inbox the way the real shell does:
# with a queued job that may run seconds later and deletes whatever *.json is
# in the inbox by then. Stopping the shell (quickshell kill) cancels it.
cat >"$bin/omarchy-shell" <<'SH'
#!/usr/bin/env bash
printf 'omarchy-shell %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/guard.log"
if [[ "$1 $2" == "notifications clear" ]]; then
  inbox="$HOME/.local/state/omarchy/notifications/inbox"
  (sleep 2 && rm -f "$inbox"/*.json) </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" >>"$ARANEA_TEST_SANDBOX/shell-jobs"
fi
SH
# `omarchy restart shell` starts the fake shell, which on load sweeps every
# image whose entry is missing (Inbox.qml sweepOrphanImages).
cat >"$bin/omarchy" <<'SH'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/guard.log"
if [[ "$1 $2" == "restart shell" ]]; then
  [[ "${FAKE_LOCKED:-0}" == 1 ]] && exit 1
  touch "$ARANEA_TEST_SANDBOX/shell-running"
  dir="$HOME/.local/state/omarchy/notifications"
  for img in "$dir"/images/*; do
    [[ -e $img ]] || continue
    stem="${img##*/}"
    stem="${stem%-*}"
    [[ -e $dir/inbox/$stem.json ]] || rm -f "$img"
  done
fi
SH
# quickshell kill stops one running fake shell (and its queued jobs) and
# fails once none is left; list reports a running (or stuck) one.
cat >"$bin/quickshell" <<'SH'
#!/usr/bin/env bash
printf 'quickshell %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/guard.log"
stuck=0
[[ "${FAKE_SHELL_STUCK:-0}" == 1 || -e $ARANEA_TEST_SANDBOX/shell-stuck ]] && stuck=1
case "$1" in
  kill)
    if [[ -f "$ARANEA_TEST_SANDBOX/shell-jobs" ]] && ((!stuck)); then
      while read -r job; do kill "$job" 2>/dev/null || true; done <"$ARANEA_TEST_SANDBOX/shell-jobs"
      rm -f "$ARANEA_TEST_SANDBOX/shell-jobs"
    fi
    [[ -e "$ARANEA_TEST_SANDBOX/shell-running" ]] || exit 1
    rm -f "$ARANEA_TEST_SANDBOX/shell-running"
    ;;
  list)
    if [[ -e "$ARANEA_TEST_SANDBOX/shell-running" ]] || ((stuck)); then
      printf 'Instance fake:\n  Process ID: 1\n'
    fi
    ;;
esac
exit 0
SH
# The running session's OMARCHY_PATH differs from the caller's.
cat >"$bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/guard.log"
[[ "$*" == "--user show-environment" ]] && printf 'OMARCHY_PATH=/session/omarchy\n'
exit 0
SH
# The session is unlocked unless FAKE_LOCKED=1.
cat >"$bin/omarchy-hyprland-session-locked" <<'SH'
#!/usr/bin/env bash
[[ "${FAKE_LOCKED:-0}" == 1 ]]
SH
chmod +x "$bin"/*
touch "$ARANEA_TEST_SANDBOX/shell-running"
export OMARCHY_PATH=/caller/omarchy

# Runs the batch with the stubs; prints its stderr (stdout is dropped),
# returns its status.
run_batch() {
  {
    PATH="$bin:$PATH" ARANEA_CAPTURE_SURFACE_COMMAND="$bin/fake-surface" \
      ARANEA_CAPTURE_RETURN_DELAY=0 "$capture" --all --output "$out" >/dev/null
  } 2>&1
}

# Seeds the real inbox: entries with images, and a reference copy of each.
seed_real() {
  rm -rf "${inbox:?}" "${images:?}" "$real"
  mkdir -p "$inbox" "$images" "$real/inbox" "$real/images"
  printf 'real\n' >"$inbox/1-1.json"
  printf 'real a\n' >"$inbox/2-1.json"
  printf 'real b\n' >"$inbox/2-2.json"
  printf 'image of 1-1\n' >"$images/1-1-0.png"
  printf 'image of 2-1\n' >"$images/2-1-0.png"
  printf 'second image of 2-1\n' >"$images/2-1-1.jpg"
  cp -p "$inbox"/* "$real/inbox/"
  cp -p "$images"/* "$real/images/"
}

# Fails unless the inbox and images dirs hold exactly the reference files.
assert_real_back() {
  local what="$1" dir
  for dir in inbox images; do
    diff -r "$real/$dir" "$notifications/$dir" >/dev/null || {
      printf '%s: %s is not the real one:\n' "$what" "$dir" >&2
      diff -r "$real/$dir" "$notifications/$dir" >&2 || true
      exit 1
    }
  done
}

# Fails when a capture backup directory is left behind.
assert_no_backup() {
  if compgen -G "$backups/capture-backup.*" >/dev/null; then
    printf '%s: the inbox backup directory must be removed\n' "$1" >&2
    exit 1
  fi
}

# --- two surfaces fail
seed_real
printf 'stale osd\n' >"$out/osd.png"
printf 'old gif\n' >"$out/hero-showcase.gif"
status=0
errors="$(CAPTURE_FAILS="menu osd" run_batch)" || status=$?
[[ "$status" -eq 1 ]] || {
  printf 'a batch with failed surfaces must exit 1 (got %s): %s\n' "$status" "$errors" >&2
  exit 1
}
grep -Fxq 'capture failed: menu osd' <<<"$errors"
grep -Fq 'hero showcase not rebuilt' <<<"$errors"
while read -r surface; do
  case "$surface" in
    menu) [[ ! -e "$out/menu.png" ]] ;;
    osd) [[ "$(cat "$out/osd.png")" == "stale osd" ]] ;;
    *) [[ "$(cat "$out/$surface.png")" == "new $surface" ]] ;;
  esac || {
    echo "unexpected result for $surface" >&2
    exit 1
  }
done < <(sed -n 's/^all_surfaces=(\(.*\))$/\1/p' "$capture" | tr ' ' '\n')
[[ "$(cat "$out/hero-showcase.gif")" == "old gif" ]]
assert_real_back 'failed surfaces'
if compgen -G "$out/.*.previous" >/dev/null; then
  echo "set-aside PNGs must not be left behind" >&2
  exit 1
fi
assert_no_backup 'failed surfaces'
grep -Fq 'omarchy restart shell' "$ARANEA_TEST_SANDBOX/guard.log"
grep -Fq 'hl.dsp.focus({ workspace = "1" })' "$ARANEA_TEST_SANDBOX/guard.log"

# --- every surface works: entries and images come back byte for byte, the
# capture entry is dropped, and a late inbox clear can never delete them
seed_real
status=0
errors="$(run_batch)" || status=$?
[[ "$status" -eq 0 ]] || {
  printf 'a clean batch must exit 0 (got %s): %s\n' "$status" "$errors" >&2
  exit 1
}
[[ "$(cat "$out/osd.png")" == "new osd" ]]
[[ "$(cat "$out/hero-showcase.gif")" == "built" ]]
assert_real_back 'clean batch'
assert_no_backup 'clean batch'
grep -Fq 'notifications that arrived during the capture' <<<"$errors" || {
  echo "the batch summary must say notifications arriving mid-capture are dropped" >&2
  exit 1
}
sleep 3
assert_real_back 'clean batch, 3 s later'
if grep -Fq 'omarchy-shell notifications clear' "$ARANEA_TEST_SANDBOX/guard.log"; then
  echo "park and restore must never ask the shell to clear the inbox" >&2
  exit 1
fi
# The shell is stopped through the running session's config (not the
# caller's OMARCHY_PATH), and checked to be gone.
grep -Fq 'quickshell kill -p /session/omarchy/shell --any-display' "$ARANEA_TEST_SANDBOX/guard.log"
grep -Fq 'quickshell list -p /session/omarchy/shell --any-display' "$ARANEA_TEST_SANDBOX/guard.log"
if grep -Fq 'quickshell kill -p /caller/omarchy/shell' "$ARANEA_TEST_SANDBOX/guard.log"; then
  echo "the shell must be stopped through the session's OMARCHY_PATH" >&2
  exit 1
fi

# --- the shell cannot be stopped at restore: the real notifications stay in
# the backup (named in the message), the inbox is left alone, the batch fails
seed_real
status=0
errors="$(STICK_SHELL=1 run_batch)" || status=$?
rm -f "$ARANEA_TEST_SANDBOX/shell-stuck"
((status != 0)) || {
  echo "a batch whose inbox was not restored must fail" >&2
  exit 1
}
mapfile -t kept < <(compgen -G "$backups/capture-backup.*" || true)
((${#kept[@]} == 1)) || {
  printf 'expected one kept backup, found %s\n' "${#kept[@]}" >&2
  exit 1
}
grep -Fq "your notifications are kept in ${kept[0]}" <<<"$errors" || {
  printf 'the message must name the kept backup: %s\n' "$errors" >&2
  exit 1
}
diff -r "$real/inbox" "${kept[0]}/inbox" >/dev/null
diff -r "$real/images" "${kept[0]}/images" >/dev/null
[[ "$(cat "$inbox/9-9.json")" == fixture && "$(cat "$images/9-9-0.png")" == 'fixture image' ]] || {
  echo "an unrestored inbox must be left as it was" >&2
  exit 1
}
grep -Fq 'omarchy restart shell' "$ARANEA_TEST_SANDBOX/guard.log"
rm -rf "${kept[0]}"

# --- the session is locked before parking: nothing is parked or captured,
# the batch stops with a message and the real inbox is untouched
seed_real
locked_out="$ARANEA_TEST_SANDBOX/locked-shots"
mkdir -p "$locked_out"
status=0
errors="$(
  {
    PATH="$bin:$PATH" FAKE_LOCKED=1 ARANEA_CAPTURE_SURFACE_COMMAND="$bin/fake-surface" \
      ARANEA_CAPTURE_RETURN_DELAY=0 "$capture" --all --output "$locked_out" >/dev/null
  } 2>&1
)" || status=$?
((status != 0)) || {
  echo "a batch that could not park the inbox must fail" >&2
  exit 1
}
grep -Fq 'notification inbox not parked' <<<"$errors" || {
  printf 'a locked session must say why nothing was captured: %s\n' "$errors" >&2
  exit 1
}
if compgen -G "$locked_out/*.png" >/dev/null; then
  echo "nothing may be captured when the inbox could not be parked" >&2
  exit 1
fi
assert_real_back 'locked session'
assert_no_backup 'locked session'

# --- an interrupted restore can be run again without losing anything
# restore_parked_inbox and its helpers are top-level functions; load them.
eval "$(sed -n '/^notification_state_dir=/p; /^notification_inbox_dir=/p; /^notification_images_dir=/p' "$capture")"
for helper in omarchy_shell_config stop_omarchy_shell restore_parked_inbox; do
  eval "$(sed -n "/^$helper() {\$/,/^}\$/p" "$capture")"
  declare -F "$helper" >/dev/null || {
    echo "capture-screenshots must define $helper" >&2
    exit 1
  }
done
# shellcheck disable=SC2154 # defined by the eval above
[[ "$notification_inbox_dir" == "$inbox" && "$notification_images_dir" == "$images" ]]
PATH="$bin:$PATH"
seed_real
backup="$backups/capture-backup.test"
mkdir -p "$backup/inbox" "$backup/images"
mv "$inbox"/* "$backup/inbox/"
mv "$images"/* "$backup/images/"
# The first run was cut off halfway through copying: one entry is missing,
# one is truncated, and a capture leftover is still there.
cp -p "$backup/inbox/1-1.json" "$inbox/"
: >"$inbox/2-1.json"
printf 'fixture\n' >"$inbox/9-9.json"
printf 'fixture image\n' >"$images/9-9-0.png"
restore_parked_inbox "$backup"
assert_real_back 'rerun restore'
[[ ! -e $backup && ! -e $backup.restored ]] || {
  echo "a verified restore must hand off (remove) its backup" >&2
  exit 1
}
# A second run after the hand-off (even one whose cleanup was cut off) never
# touches the restored inbox.
mkdir -p "$backup.restored/inbox"
restore_parked_inbox "$backup"
assert_real_back 'restore after hand-off'

echo "capture batch behaviour passed"
