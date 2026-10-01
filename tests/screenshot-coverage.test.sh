#!/usr/bin/env bash
# Contract for scripts/capture-screenshots and the screenshots it produces:
# every declared surface has a PNG referenced from the README, the hero
# showcase GIF has the right frame count and each frame matches its still,
# the capture never disables the notifications plugin or types real text,
# the real inbox/clipboard/picker state is always restored (trap ordering
# and swap-flag guards checked directly in the script), and the polkit shot
# is a harmless cancelled request.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
capture_script="$repo_root/scripts/capture-screenshots"
readme="$repo_root/README.md"

mapfile -t surfaces < <(
  sed -n 's/^all_surfaces=(\(.*\))$/\1/p' "$capture_script" | tr ' ' '\n'
)
expected_surfaces=(
  menu menu-submenu menu-search menu-input desktop health lock plymouth
  btop file-manager neovim notifications notifications-empty clipboard emojis polkit
  network audio bluetooth agents
  power monitor clock weather image-picker apps favorites recent
  dawn osd workspaces updates
)
expected_hero_frames=(
  desktop menu menu-submenu menu-search menu-input apps favorites recent
  notifications notifications-empty health updates workspaces clipboard emojis
  image-picker network audio bluetooth agents power monitor clock weather lock osd
)
[[ "${surfaces[*]}" == "${expected_surfaces[*]}" ]]

for surface in "${surfaces[@]}"; do
  test -f "$repo_root/screenshots/$surface.png"
  if [[ "$surface" == dawn ]]; then
    grep -Eq 'screenshots/dawn\.png|backgrounds/variants/dawn\.png' "$readme"
  else
    grep -Fq "screenshots/$surface.png" "$readme"
  fi
done

test -f "$repo_root/screenshots/dawn.png"
test -f "$repo_root/screenshots/osd.png"
grep -Fq 'ARANEA_OSD_CAPTURE_COMMAND' "$capture_script"

test ! -e "$repo_root/screenshots/idle.png"
test -f "$repo_root/screenshots/hero-showcase.gif"
grep -Fq 'screenshots/hero-showcase.gif' "$readme"
grep -Fq 'build_hero_showcase' "$capture_script"
grep -Fq 'trap cleanup_health_probe EXIT' "$capture_script"
# The bell belongs in every capture: never disable the notifications plugin
# (the host rewrites a disabled clone's bar entry). The real inbox is parked
# for the batch instead, so badges show capture data only.
if grep -Eq 'plugin (disable|enable) araneadev.notifications' "$capture_script"; then
  echo "capture must not toggle the notifications plugin" >&2
  exit 1
fi
grep -Fq 'batch_inbox_backup' "$capture_script"
# The health probe is cleared before the next surface is captured.
grep -Fq 'omarchy-shell health refresh' "$capture_script"
# I3: picker fixtures are swapped only while the shell is stopped, the backup
# lives in the state dir (not /tmp), a password-manager hint is never the
# saved clipboard type, and an empty clipboard is left empty.
grep -Fq 'stop_omarchy_shell' "$capture_script"
grep -Fq 'capture-backup' "$capture_script"
grep -Fq 'x-kde-passwordManagerHint' "$capture_script"
grep -Fq 'wl-copy --clear' "$capture_script"
# The health shot waits for enough CPU history to draw a real sparkline.
grep -Fq '.samples' "$capture_script"
grep -Fq 'omarchy-shell health status' "$capture_script"

# Capture windows are closed by address, never as "the active window": focus
# may have moved to the user's own window (closing it once killed a session).
if grep -Fq 'hl.dsp.window.close()' "$capture_script"; then
  echo "capture must never close the active window" >&2
  exit 1
fi
# shellcheck disable=SC2016 # a literal, not an expansion
grep -Fq 'close_new_windows "$windows_before"' "$capture_script"

# The polkit shot is a harmless pkexec request that is always cancelled with
# Escape: nothing is ever typed into the password field.
grep -Fq 'pkexec /usr/bin/true' "$capture_script"
grep -Fq 'wtype -k Escape' "$capture_script"
grep -Fq 'omarchy-polkit' "$capture_script"
# Only single named keys (Tab, Escape) are ever sent; no text.
if grep -E '^\s*wtype |[;&|(] *wtype ' "$capture_script" | grep -Ev 'wtype -k (Tab|Escape)( |$)'; then
  echo "capture must never type text" >&2
  exit 1
fi

# Final review I2: no keys are sent unless the prompt is on screen, and a
# pkexec left running is killed.
grep -Fq 'polkit prompt never appeared' "$capture_script"
grep -Fq "kill \"\$pkexec_pid\"" "$capture_script"
# The real inbox / picker data is protected by a restore trap set before it
# is moved aside, and parked under the state dir, not /tmp (spec D).
line_of() { grep -nF -- "$1" "$capture_script" | head -n 1 | cut -d: -f1; }
# shellcheck disable=SC2016 # literals, not expansions
(($(line_of "trap 'restore_inbox || exit 1' EXIT") < $(line_of 'park_notification_inbox "$inbox_backup"')))
(($(line_of "trap 'finish_picker || exit 1' EXIT") < $(line_of "mv \"\$picker_file\" \"\$picker_backup/saved\"")))
# shellcheck disable=SC2016 # a literal, not an expansion
grep -Fq 'inbox_backup="$(mktemp -d "$(aranea_state_root)/capture-backup.XXXXXX")"' "$capture_script"
if grep -Fq "capture_status" "$capture_script"; then
  echo "capture_status is gone: capture fails only when no frame was written" >&2
  exit 1
fi
# ...and the cleanup only undoes what was done: it never deletes an unmoved
# history file or clears an untouched clipboard.
(($(line_of 'picker_swapped=1') > $(line_of "mv \"\$picker_file\" \"\$picker_backup/saved\"")))
grep -Fq 'if ((picker_swapped)); then' "$capture_script"
grep -Fq '&& ((clipboard_swapped)); then' "$capture_script"
# shellcheck disable=SC2016 # literals, not expansions
grep -Fq 'park_notification_inbox "$inbox_backup" inbox_swapped' "$capture_script"
grep -Fq 'if ((! inbox_swapped)); then' "$capture_script"
# Parking and restoring the inbox happen only while every shell instance is
# stopped (a queued job of a running shell once deleted a restored inbox, and
# a restart sweeps images whose entry is parked), so images are parked too,
# the shell is never asked to clear the inbox, parked files are copied (not
# moved) back, and the backup is kept unless every file is verified back.
park_body="$(sed -n '/^park_notification_inbox() {$/,/^}$/p' "$capture_script")"
restore_body="$(sed -n '/^restore_parked_inbox() {$/,/^}$/p' "$capture_script")"
grep -Fq 'stop_omarchy_shell' <<<"$park_body"
grep -Fq 'stop_omarchy_shell' <<<"$restore_body"
grep -Fq 'images' <<<"$park_body"
# The swapped flag is set by the park the moment the move is done (no window
# in which a parked inbox is not restored), never by the caller afterwards.
# shellcheck disable=SC2016 # a literal, not an expansion
grep -Fq 'printf -v "$flag" 1' <<<"$park_body"
if grep -Eq '^ *(batch|inbox)_swapped=1' "$capture_script"; then
  echo "the inbox swapped flags are set inside park_notification_inbox" >&2
  exit 1
fi
# A stop counts only when quickshell list confirms it (fails closed).
stop_body="$(sed -n '/^stop_omarchy_shell() {$/,/^}$/p' "$capture_script")"
# shellcheck disable=SC2016 # literals, not expansions
grep -Fq 'listed="$(quickshell list -p "$config" --any-display 2>&1)" || return 1' <<<"$stop_body"
# shellcheck disable=SC2016 # a literal, not an expansion
grep -Fq '[[ -f "$config/shell.qml" ]] || return 1' <<<"$stop_body"
# shellcheck disable=SC2016 # literals, not expansions
grep -Fq 'park_notification_inbox "$batch_inbox_backup" batch_swapped' "$capture_script"
# shellcheck disable=SC2016 # literals, not expansions
grep -Fq 'restore_parked_inbox "$batch_inbox_backup"' "$capture_script"
# shellcheck disable=SC2016 # literals, not expansions
grep -Fq 'restore_parked_inbox "$inbox_backup"' "$capture_script"
grep -Fq 'your notifications are kept in' "$capture_script"
# The verified backup is handed off by rename before it is deleted, so a
# rerun after an interrupted delete finds no backup and touches nothing.
# shellcheck disable=SC2016 # a literal, not an expansion
grep -Fq 'if ! mv -- "$backup" "$backup.restored"; then' <<<"$restore_body"
if grep -Fq 'notifications clear' "$capture_script"; then
  echo "park and restore must never ask the shell to clear the inbox" >&2
  exit 1
fi
if grep -Eq 'quickshell kill .*\|\| true' "$capture_script"; then
  echo "a failed shell stop must never be ignored" >&2
  exit 1
fi
# shellcheck disable=SC2016 # a literal, not an expansion
if grep -E '(^|[^a-z])mv ' <<<"$restore_body" | grep -vF 'mv -- "$backup" "$backup.restored"'; then
  echo "parked notifications must be copied back and verified, never moved" >&2
  exit 1
fi
# shellcheck disable=SC2016 # a literal, not an expansion
grep -Fq 'cp -p -- "$file"' <<<"$restore_body"
# shellcheck disable=SC2016 # a literal, not an expansion
grep -Fq 'cmp -s -- "$file"' <<<"$restore_body"
# The --all batch also sets its restore trap before parking the inbox, and
# keeps it while the explicit finish runs (cleared only afterwards).
# shellcheck disable=SC2016 # literals, not expansions
(($(line_of "trap 'finish_batch || exit 1' EXIT") < $(line_of 'park_notification_inbox "$batch_inbox_backup"')))
# Each finisher's explicit call runs with its EXIT trap still set; the trap
# is cleared on the very next line.
next_line_of() { grep -A1 -Fx -- "$1" "$capture_script" | sed -n 2p; }
[[ "$(next_line_of '  finish_batch || batch_restore_status=1')" == '  trap - EXIT' ]]
[[ "$(next_line_of '    restore_inbox || exit 1')" == '    trap - EXIT' ]]
[[ "$(next_line_of '    finish_picker || exit 1')" == '    trap - EXIT' ]]
grep -Fq 'if ((batch_finished)); then' "$capture_script"
# A clipboard that cannot be saved is never replaced.
grep -Fq 'could not save the clipboard' "$capture_script"
hero_frames="$(identify "$repo_root/screenshots/hero-showcase.gif" | wc -l)"
[[ "$hero_frames" -eq "${#expected_hero_frames[@]}" ]]

hero_tmp="$(mktemp -d)"
# Use the classic convert/compare binaries rather than the unified `magick`
# wrapper: CI's apt-get imagemagick package is ImageMagick 6, which has no
# `magick` command at all, while `convert`/`compare` work on both IM6 and
# IM7 (as a deprecated but functional compatibility shim).
convert "$repo_root/screenshots/hero-showcase.gif" -coalesce -resize '160x90!' \
  "$hero_tmp/frame-%02d.png" 2>/dev/null
for index in "${!expected_hero_frames[@]}"; do
  convert "$repo_root/screenshots/${expected_hero_frames[$index]}.png" \
    -resize '160x90!' "$hero_tmp/expected.png" 2>/dev/null
  metric="$(
    compare -metric RMSE \
      "$hero_tmp/frame-$(printf '%02d' "$index").png" \
      "$hero_tmp/expected.png" null: 2>&1 || true
  )"
  # IM7's compare shim prints its own deprecation notice on the same stream
  # as the RMSE result; drop it before parsing the "N (n.nnn)" metric line.
  metric="$(grep -v '^WARNING:' <<<"$metric" || true)"
  normalized_metric="${metric##*(}"
  normalized_metric="${normalized_metric%)}"
  awk -v metric="$normalized_metric" 'BEGIN { exit !(metric < 0.03) }'
done

# --- 4d: --all captures every surface, lists failures and exits 1 on any
# (behaviour: tests/capture-batch.test.sh)
capture="$repo_root/scripts/capture-screenshots"

# --- 4e: the weather capture shows a demo city and always restores the user's
# location; there is no wifiqr capture; --hero rebuilds the GIF from stills
grep -Fq 'trap restore_weather EXIT' "$capture"
grep -Fq 'ARANEA_CAPTURE_WEATHER_CITY:-Amsterdam' "$capture"
if grep -Eq '^  wifiqr\)' "$capture"; then
  echo "wifiqr must never be captured" >&2
  exit 1
fi
hero_dir="$(mktemp -d)"
hero_bin="$hero_dir/bin"
mkdir -p "$hero_bin"
cat >"$hero_bin/magick" <<'SH'
#!/usr/bin/env bash
touch "${@: -1}"
SH
chmod +x "$hero_bin/magick"
while read -r frame; do
  : >"$hero_dir/$frame.png"
done < <(sed -n 's/^  local frames=(\(.*\))$/\1/p' "$capture" | tr ' ' '\n')
PATH="$hero_bin:$PATH" "$capture" --hero --output "$hero_dir" >/dev/null
test -f "$hero_dir/hero-showcase.gif"
rm -rf "$hero_dir"

echo "screenshot coverage contract passed (${#surfaces[@]} surfaces)"
