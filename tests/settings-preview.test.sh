#!/usr/bin/env bash
# Production SettingsSurface capture in a scratch offscreen host. Removing
# showcase isolation, geometry, or capture routing must fail this contract.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
quickshell_bin=""
while IFS= read -r candidate; do
  [[ "$candidate" == */tests/guard-bin/* ]] && continue
  quickshell_bin="$candidate"
  break
done < <(type -ap quickshell 2>/dev/null || true)
if [[ -z "$quickshell_bin" || ! -f /usr/share/omarchy/shell/Commons/qmldir ]] || ! command -v magick >/dev/null; then
  echo 'SKIP: settings preview requires Quickshell, Omarchy and ImageMagick'
  exit 0
fi
out="$ARANEA_TEST_SANDBOX/shots"
ARANEA_SETTINGS_PREVIEW_QUICKSHELL="$quickshell_bin" "$repo_root/scripts/capture-screenshots" --surface settings-narrow --output "$out"
[[ "$(magick identify -format '%wx%h' "$out/settings-narrow.png")" == 652x452 ]]
ARANEA_SETTINGS_PREVIEW_QUICKSHELL="$quickshell_bin" "$repo_root/tools/render-settings-preview" --fixture scaling --output "$out/settings-scaling.png"
[[ "$(magick identify -format '%wx%h' "$out/settings-scaling.png")" == 840x620 ]]
for fixture in projects-empty projects-discovery projects-grouped projects-partial project-details project-launch-partial workspaces; do
  ARANEA_SETTINGS_PREVIEW_QUICKSHELL="$quickshell_bin" "$repo_root/scripts/capture-screenshots" --surface "$fixture" --output "$out"
  [[ -s "$out/$fixture.png" ]]
done
ARANEA_SETTINGS_RENDER_WIDTH=652 ARANEA_SETTINGS_RENDER_HEIGHT=452 ARANEA_SETTINGS_RENDER_CONTROLS=1 ARANEA_SETTINGS_PREVIEW_QUICKSHELL="$quickshell_bin" "$repo_root/tools/render-settings-preview" --fixture project-details --output "$out/project-controls.png"
# Isolated preview must never summon or mutate the active desktop owners.
# Shared host Style probes compositor geometry read-only. With session sockets
# removed these cannot contact the desktop; no settings owner commands may run.
if [[ -f "$ARANEA_TEST_SANDBOX/guard.log" ]] && grep -Ev '^hyprctl -j getoption (general:gaps_out|decoration:rounding)$' "$ARANEA_TEST_SANDBOX/guard.log"; then
  exit 1
fi
rc=0
"$repo_root/tools/render-settings-preview" --output "$out/invalid.png" --fixture invalid >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 && ! -e "$out/invalid.png" ]]
# A renderer must reject process execution even when a valid image was produced.
cat >"$ARANEA_TEST_SANDBOX/capture-exec-trap" <<'EXECUTION'
#!/usr/bin/env bash
omarchy-shell aranea.projects request '{"projectId":"p-fixture"}' >/dev/null 2>&1 || true
magick -size "${ARANEA_SETTINGS_RENDER_WIDTH:-480}x${ARANEA_SETTINGS_RENDER_HEIGHT:-300}" xc:black "${ARANEA_SETTINGS_RENDER_OUTPUT:-$ARANEA_MENU_RENDER_OUTPUT}"
printf 'SETTINGSRENDER OK trap probe\n'
EXECUTION
chmod +x "$ARANEA_TEST_SANDBOX/capture-exec-trap"
rc=0
ARANEA_SETTINGS_PREVIEW_QUICKSHELL="$ARANEA_TEST_SANDBOX/capture-exec-trap" "$repo_root/tools/render-settings-preview" --output "$out/trapped.png" >"$ARANEA_TEST_SANDBOX/trap-diagnostic" 2>&1 || rc=$?
[[ "$rc" == 1 && ! -e "$out/trapped.png" ]]
grep -Fq 'Preview refused unexpected process execution' "$ARANEA_TEST_SANDBOX/trap-diagnostic"
echo 'settings preview contract passed'
