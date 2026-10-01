#!/usr/bin/env bash
# Behaviour of `scripts/capture-screenshots --all` with every surface capture
# replaced (ARANEA_CAPTURE_SURFACE_COMMAND) and the desktop stubbed: a failed
# surface keeps its previous PNG, is listed at the end and fails the batch,
# the hero GIF is rebuilt only when every surface worked, and the parked
# notification inbox always comes back.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

capture="$repo_root/scripts/capture-screenshots"
bin="$ARANEA_TEST_SANDBOX/capture-bin"
out="$ARANEA_TEST_SANDBOX/shots"
inbox="$HOME/.local/state/omarchy/notifications/inbox"
mkdir -p "$bin" "$out" "$inbox"

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
# Writes <surface>.png, except for the surfaces listed in CAPTURE_FAILS.
cat >"$bin/fake-surface" <<'SH'
#!/usr/bin/env bash
[[ " ${CAPTURE_FAILS:-} " == *" $1 "* ]] && exit 1
printf 'new %s\n' "$1" >"$2/$1.png"
SH
# omarchy-shell clears the notification inbox the way the real shell does:
# with a queued job that may run seconds later and deletes whatever *.json is
# in the inbox by then. Stopping the shell (quickshell kill) cancels it.
cat >"$bin/omarchy-shell" <<'SH'
#!/usr/bin/env bash
if [[ "$1 $2" == "notifications clear" ]]; then
  inbox="$HOME/.local/state/omarchy/notifications/inbox"
  (sleep 2 && rm -f "$inbox"/*.json) </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" >>"$ARANEA_TEST_SANDBOX/shell-jobs"
fi
SH
cat >"$bin/quickshell" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == kill && -f "$ARANEA_TEST_SANDBOX/shell-jobs" ]]; then
  while read -r job; do kill "$job" 2>/dev/null || true; done <"$ARANEA_TEST_SANDBOX/shell-jobs"
  rm -f "$ARANEA_TEST_SANDBOX/shell-jobs"
fi
SH
chmod +x "$bin/hyprctl" "$bin/magick" "$bin/fake-surface" "$bin/omarchy-shell" "$bin/quickshell"

# Runs the batch with the stubs; prints its stderr (stdout is dropped),
# returns its status.
run_batch() {
  {
    PATH="$bin:$PATH" ARANEA_CAPTURE_SURFACE_COMMAND="$bin/fake-surface" \
      ARANEA_CAPTURE_RETURN_DELAY=0 "$capture" --all --output "$out" >/dev/null
  } 2>&1
}

# --- two surfaces fail
printf 'real\n' >"$inbox/1-1.json"
printf 'stale osd\n' >"$out/osd.png"
printf 'old gif\n' >"$out/hero-showcase.gif"
status=0
errors="$(CAPTURE_FAILS="menu osd" run_batch)" || status=$?
[[ "$status" -eq 1 ]] || {
  echo "a batch with failed surfaces must exit 1 (got $status)" >&2
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
[[ "$(cat "$inbox/1-1.json")" == "real" ]]
if compgen -G "$out/.*.previous" >/dev/null; then
  echo "set-aside PNGs must not be left behind" >&2
  exit 1
fi
if compgen -G "$XDG_STATE_HOME/aranea/capture-backup.*" >/dev/null; then
  echo "the inbox backup directory must be removed" >&2
  exit 1
fi
grep -Fq 'omarchy restart shell' "$ARANEA_TEST_SANDBOX/guard.log"
grep -Fq 'hl.dsp.focus({ workspace = "1" })' "$ARANEA_TEST_SANDBOX/guard.log"

# --- every surface works
status=0
errors="$(run_batch)" || status=$?
[[ "$status" -eq 0 ]] || {
  printf 'a clean batch must exit 0 (got %s): %s\n' "$status" "$errors" >&2
  exit 1
}
[[ "$(cat "$out/osd.png")" == "new osd" ]]
[[ "$(cat "$out/hero-showcase.gif")" == "built" ]]
[[ "$(cat "$inbox/1-1.json")" == "real" ]]

# --- a late inbox clear never deletes the restored notifications
# (a queued clear outlived the old one-second wait and deleted them)
printf 'real a\n' >"$inbox/2-1.json"
printf 'real b\n' >"$inbox/2-2.json"
run_batch >/dev/null || true
sleep 3
for file in 1-1 2-1 2-2; do
  [[ -f "$inbox/$file.json" ]] || {
    echo "real notification $file was deleted by the capture's inbox clear" >&2
    exit 1
  }
done

echo "capture batch behaviour passed"
