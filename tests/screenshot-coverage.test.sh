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
  power monitor apps favorites recent
  dawn osd
)
expected_hero_frames=(
  desktop menu menu-submenu menu-search menu-input apps favorites recent
  notifications health network audio bluetooth agents power monitor btop
  file-manager neovim lock osd
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
grep -Fq 'stop_shell' "$capture_script"
grep -Fq 'capture-backup' "$capture_script"
grep -Fq 'x-kde-passwordManagerHint' "$capture_script"
grep -Fq 'wl-copy --clear' "$capture_script"
# The health shot waits for enough CPU history to draw a real sparkline.
grep -Fq '.samples' "$capture_script"
grep -Fq 'omarchy-shell health status' "$capture_script"

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
(($(line_of 'trap restore_inbox EXIT') < $(line_of "mv -t \"\$inbox_backup\"")))
(($(line_of 'trap finish_picker EXIT') < $(line_of "mv \"\$picker_file\" \"\$picker_backup/saved\"")))
grep -Fq "inbox_backup=\"\$(mktemp -d \"\$state_home/aranea/capture-backup.XXXXXX\")\"" "$capture_script"
if grep -Fq "capture_status" "$capture_script"; then
  echo "capture_status is gone: capture fails only when no frame was written" >&2
  exit 1
fi
# ...and the cleanup only undoes what was done: it never deletes an unmoved
# history file or clears an untouched clipboard.
(($(line_of 'picker_swapped=1') > $(line_of "mv \"\$picker_file\" \"\$picker_backup/saved\"")))
grep -Fq 'if ((picker_swapped)); then' "$capture_script"
grep -Fq '&& ((clipboard_swapped)); then' "$capture_script"
(($(line_of 'inbox_swapped=1') > $(line_of "mv -t \"\$inbox_backup\"")))
grep -Fq 'if ((! inbox_swapped)); then return 0; fi' "$capture_script"
# The --all batch also sets its restore trap before parking the inbox, and a
# clipboard that cannot be saved is never replaced.
(($(line_of 'trap finish_batch EXIT') < $(line_of "-exec mv -t \"\$batch_inbox_backup\"")))
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
capture="$repo_root/scripts/capture-screenshots"
grep -Fq "capture_one \"\$all_surface\" || failed_surfaces+=(\"\$all_surface\")" "$capture"
grep -Fq "if [[ -f \"\$png\" ]]; then mv -- \"\$png\" \"\$previous\"; fi" "$capture"
grep -Fq "if [[ -f \"\$previous\" ]]; then mv -- \"\$previous\" \"\$png\"; fi" "$capture"
grep -Fq "printf 'capture failed: %s\\n' \"\${failed_surfaces[*]}\"" "$capture"

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
