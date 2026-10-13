#!/usr/bin/env bash
# Exercise the real collector with inert package-tool boundaries.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
task_bin="$TMPDIR/update-bin"
mkdir -p "$task_bin"
export PATH="$task_bin:$PATH"
export UPDATE_FIXTURE="$TMPDIR/update-fixture"
mkdir -p "$UPDATE_FIXTURE"
export OMARCHY_PATH=/usr/share/omarchy
for task_tool in checkupdates yay; do
  cat >"$task_bin/$task_tool" <<'SH'
#!/usr/bin/env bash
tool="${0##*/}"
printf '%s %s\n' "$tool" "$*" >>"$UPDATE_FIXTURE/calls"
cat "$UPDATE_FIXTURE/$tool.out"
cat "$UPDATE_FIXTURE/$tool.err" >&2
exit "$(cat "$UPDATE_FIXTURE/$tool.rc")"
SH
  chmod +x "$task_bin/$task_tool"
  : >"$UPDATE_FIXTURE/$task_tool.err"
done
cat >"$UPDATE_FIXTURE/checkupdates.out" <<'EOF'
curl 8.1-1 -> 8.2-1
linux 6.1-1 -> 6.2-1
omarchy 4.0-1 -> 4.1-1
EOF
echo 0 >"$UPDATE_FIXTURE/checkupdates.rc"
echo 'my-app 1-1 -> 2-1' >"$UPDATE_FIXTURE/yay.out"
echo 0 >"$UPDATE_FIXTURE/yay.rc"
collector="$repo_root/scripts/aranea-update-status"
"$collector" >"$TMPDIR/status.json"
jq -e '.updates | length == 4' "$TMPDIR/status.json" >/dev/null
jq -e '[.updates[] | select(.source == "system") | .name] == ["curl", "linux", "omarchy"]' "$TMPDIR/status.json" >/dev/null
jq -e '.updates[] | select(.source == "aur" and .name == "my-app")' "$TMPDIR/status.json" >/dev/null
rg -q '^checkupdates --nocolor$' "$UPDATE_FIXTURE/calls"
rg -q '^yay -Qua --color never$' "$UPDATE_FIXTURE/calls"
mkdir -p "$XDG_STATE_HOME/omarchy"
touch "$XDG_STATE_HOME/omarchy/reboot-required"
: >"$UPDATE_FIXTURE/checkupdates.out"
echo 2 >"$UPDATE_FIXTURE/checkupdates.rc"
: >"$UPDATE_FIXTURE/yay.out"
echo 1 >"$UPDATE_FIXTURE/yay.rc"
"$collector" >"$TMPDIR/status.json"
jq -e '.updates == [] and .rebootRequired == true and (.error // "") == ""' "$TMPDIR/status.json" >/dev/null
# Failed checks never masquerade as an empty successful check.
echo 'Cannot fetch updates' >"$UPDATE_FIXTURE/checkupdates.err"
echo 1 >"$UPDATE_FIXTURE/checkupdates.rc"
if "$collector" >"$TMPDIR/status.json"; then
  echo 'failed repository check was accepted' >&2
  exit 1
fi
jq -e '.error | contains("system")' "$TMPDIR/status.json" >/dev/null
# Error text is not a package row, even when a tool returned success.
: >"$UPDATE_FIXTURE/checkupdates.err"
echo 0 >"$UPDATE_FIXTURE/checkupdates.rc"
echo 'unexpected tool response' >"$UPDATE_FIXTURE/checkupdates.out"
if "$collector" >"$TMPDIR/status.json"; then
  echo 'malformed package response was accepted' >&2
  exit 1
fi
jq -e '.error | contains("system")' "$TMPDIR/status.json" >/dev/null
# An AUR error with its usual no-results exit code is still a failure.
: >"$UPDATE_FIXTURE/checkupdates.out"
echo 2 >"$UPDATE_FIXTURE/checkupdates.rc"
echo 'AUR is unavailable' >"$UPDATE_FIXTURE/yay.err"
if "$collector" >"$TMPDIR/status.json"; then
  echo 'failed AUR check was accepted' >&2
  exit 1
fi
jq -e '.error | contains("aur")' "$TMPDIR/status.json" >/dev/null
echo 'update status contract passed'
