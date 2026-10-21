#!/usr/bin/env bash
# Explicit preview: exact video argument, no audio/network/player config, no idle changes.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
launcher="$repo_root/scripts/aranea-screensaver"
mkdir -p "$TMPDIR/player"
cat >"$TMPDIR/player/mpv" <<'PLAYER'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARANEA_PLAYER_ARGS"
PLAYER
chmod +x "$TMPDIR/player/mpv"
export ARANEA_PLAYER_ARGS="$TMPDIR/args"
export PATH="$TMPDIR/player:$PATH"
"$launcher" --help >/dev/null
if "$launcher" wrong >/dev/null 2>&1; then exit 1; fi
test ! -e "$ARANEA_PLAYER_ARGS"
"$launcher" video
grep -F -- '--no-audio' "$ARANEA_PLAYER_ARGS" >/dev/null
grep -F -- '--no-config' "$ARANEA_PLAYER_ARGS" >/dev/null
grep -F -- '--loop-file=inf' "$ARANEA_PLAYER_ARGS" >/dev/null
grep -F -- '--fullscreen' "$ARANEA_PLAYER_ARGS" >/dev/null
grep -F -- "$repo_root/branding/3d/silk-chamber.mp4" "$ARANEA_PLAYER_ARGS" >/dev/null
# Missing assets fail before spawning a player, including paths with spaces.
fixture="$TMPDIR/preview root"
mkdir -p "$fixture/scripts" "$fixture/branding/3d"
cp "$launcher" "$fixture/scripts/aranea-screensaver"
rm "$ARANEA_PLAYER_ARGS"
if "$fixture/scripts/aranea-screensaver" video >/dev/null 2>&1; then exit 1; fi
test ! -e "$ARANEA_PLAYER_ARGS"
printf 'fixture' >"$fixture/branding/3d/silk-chamber.mp4"
"$fixture/scripts/aranea-screensaver" video
test "$(tail -n 1 "$ARANEA_PLAYER_ARGS")" = "$fixture/branding/3d/silk-chamber.mp4"
if command -v lua >/dev/null; then
  lua "$repo_root/tests/spider-preview-input.test.lua" "$repo_root"
fi
echo 'spider preview contract passed'

# Live preview uses the owned local server and isolated browser runner.
cat >"$TMPDIR/player/python3" <<'PYTHON'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARANEA_PLAYER_ARGS"
PYTHON
chmod +x "$TMPDIR/player/python3"
"$launcher" preview
test "$(cat "$ARANEA_PLAYER_ARGS")" = "$repo_root/tools/spider/preview.py"
