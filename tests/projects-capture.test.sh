#!/usr/bin/env bash
# The Projects README captures grab the production Projects window over the
# desktop through aranea.projects.capture with inert fixture projects only,
# restore the window and focus on every exit, and refuse (exit 3, previous
# screenshot kept) when the owner or its capture IPC is unavailable, instead
# of falling back to an offscreen render.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
bin="$ARANEA_TEST_SANDBOX/bin"
out="$ARANEA_TEST_SANDBOX/shots"
log="$ARANEA_TEST_SANDBOX/calls"
mkdir -p "$bin" "$out"
cat >"$bin/omarchy-shell" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls"
[[ "${CAPTURE_PROJECTS_OWNER_DOWN:-0}" != 1 ]] || {
  echo 'omarchy-shell is not running' >&2
  exit 1
}
[[ "$1" == aranea.projects.capture ]] || exit 1
snapshot='{"opened":false,"mode":"","section":"projects","projectId":"p-real"}'
ready='{"ready":true,"readOnly":true}'
case "$2" in
  captureSnapshot) echo "${CAPTURE_PROJECTS_SNAPSHOT-$snapshot}" ;;
  captureBegin) echo "${CAPTURE_PROJECTS_ANSWER-ok}" ;;
  captureState) echo "${CAPTURE_PROJECTS_READY-$ready}" ;;
  captureRestore) echo "${CAPTURE_PROJECTS_RESTORE-ok}" ;;
  *) exit 1 ;;
esac
STUB
cat >"$bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >>"$ARANEA_TEST_SANDBOX/calls"
case "$1" in
  activeworkspace) echo '{"id":7}' ;;
  activewindow) echo '{"address":"0xabc"}' ;;
esac
STUB
cat >"$bin/grim" <<'STUB'
#!/usr/bin/env bash
printf 'grim\n' >>"$ARANEA_TEST_SANDBOX/calls"
printf frame >"${@: -1}"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/sleep"
chmod +x "$bin"/*
export PATH="$bin:$PATH"
capture="$repo_root/scripts/capture-screenshots"
snapshot='{"opened":false,"mode":"","section":"projects","projectId":"p-real"}'
# Prints the first log line number matching a pattern.
line() { grep -n -- "$1" "$log" | head -1 | cut -d: -f1; }

# Every README surface: snapshot, inert fixture, readiness, grab, then restore and refocus.
# Prints a fragment the fixture payload of SURFACE must contain.
marker() {
  case "$1" in
    projects) echo '"id":"p-many-5"' ;;
    project-overview) echo '"lastCheckoutId":"c-review"' ;;
    project-problem) echo '"projectAcceptanceUnknown":true' ;;
    project-switcher) echo '"mode":"switcher"' ;;
    project-review) echo '"branch":"agent/navigation-polish"' ;;
    project-actions) echo '"projectSection":"actions"' ;;
  esac
}
for surface in projects project-overview project-problem project-switcher project-review project-actions; do
  : >"$log"
  "$capture" --surface "$surface" --output "$out" >/dev/null
  [[ "$(cat "$out/$surface.png")" == frame ]]
  begin="$(grep '^aranea.projects.capture captureBegin ' "$log")"
  payload="${begin#aranea.projects.capture captureBegin }"
  jq -e --arg snapshot "$snapshot" '.snapshot == $snapshot and .section == "projects" and (.fixture.projectsState.projects | length > 0)' <<<"$payload" >/dev/null
  grep -Fq -- "$(marker "$surface")" <<<"$payload"
  # Stand-in projects only: every root and checkout lives under /fixture.
  [[ "$(jq '.fixture.projectsState | [.roots[].path, .projects[].checkouts[].path] | map(select(startswith("/fixture/") | not)) | length' <<<"$payload")" == 0 ]]
  (($(line captureSnapshot) < $(line captureBegin)))
  (($(line captureState) < $(line '^grim$')))
  (($(line '^grim$') < $(line captureRestore)))
  grep -Fxq "aranea.projects.capture captureRestore $snapshot" "$log"
  grep -Fq 'workspace = "7"' "$log"
  grep -Fq 'window = "address:0xabc"' "$log"
  # Only the capture transaction: no open, refresh, summon or settings call.
  [[ "$(grep -cv '^hyprctl \|^grim$\|^aranea.projects.capture capture' "$log")" == 0 ]]
  rm "$out/$surface.png"
done
[[ "$(node "$repo_root/tools/project-capture-fixture.mjs" project-overview | jq -r .mode)" == "" ]]

# No owner, no capture IPC or a malformed snapshot: refuse before any fixture or grab.
printf old >"$out/projects.png"
for failure in owner-down missing-ipc invalid-snapshot; do
  : >"$log"
  rc=0
  case "$failure" in
    owner-down) CAPTURE_PROJECTS_OWNER_DOWN=1 "$capture" --surface projects --output "$out" >/dev/null 2>&1 || rc=$? ;;
    missing-ipc) CAPTURE_PROJECTS_SNAPSHOT='Function not found.' "$capture" --surface projects --output "$out" >/dev/null 2>&1 || rc=$? ;;
    invalid-snapshot) CAPTURE_PROJECTS_SNAPSHOT='{"opened":"yes"}' "$capture" --surface projects --output "$out" >/dev/null 2>&1 || rc=$? ;;
  esac
  [[ "$rc" == 3 && "$(cat "$out/projects.png")" == old ]]
  if grep -Eq 'captureBegin|captureRestore|dispatch|^grim$' "$log"; then exit 1; fi
done
# A refused fixture grabs nothing and has nothing to restore.
for answer in busy invalid ''; do
  : >"$log"
  rc=0
  CAPTURE_PROJECTS_ANSWER="$answer" "$capture" --surface project-switcher --output "$out" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 3 && ! -e "$out/project-switcher.png" ]]
  if grep -Eq 'grim|captureRestore|dispatch' "$log"; then exit 1; fi
done
# Not read-only, never ready or a failed restore: restored, refocused, old image kept.
for failure in writable timeout restore; do
  : >"$log"
  rc=0
  case "$failure" in
    writable) CAPTURE_PROJECTS_READY='{"ready":true,"readOnly":false}' "$capture" --surface projects --output "$out" >/dev/null 2>&1 || rc=$? ;;
    timeout) CAPTURE_PROJECTS_READY='{"ready":false,"readOnly":true}' "$capture" --surface projects --output "$out" >/dev/null 2>&1 || rc=$? ;;
    restore) CAPTURE_PROJECTS_RESTORE=invalid "$capture" --surface projects --output "$out" >/dev/null 2>&1 || rc=$? ;;
  esac
  [[ "$rc" == 3 && "$(cat "$out/projects.png")" == old ]]
  [[ "$failure" == restore ]] || ! grep -Fxq grim "$log"
  grep -Fq captureRestore "$log"
  grep -Fq 'workspace = "7"' "$log"
  grep -Fq 'window = "address:0xabc"' "$log"
done
[[ "$(find "$out" -name '.*' -type f | wc -l)" == 0 ]]
# The offscreen renderer is never the fallback: no quickshell was started.
if grep -q quickshell "$ARANEA_TEST_SANDBOX/guard.log" 2>/dev/null; then exit 1; fi
echo 'Projects capture contract passed'
