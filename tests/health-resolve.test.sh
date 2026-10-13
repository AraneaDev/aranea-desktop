#!/usr/bin/env bash
# Drive the real guided resolver through inert native-tool boundaries.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
task_bin="$TMPDIR/health-bin"
mkdir -p "$task_bin"
export PATH="$task_bin:$PATH"
export HEALTH_TEST_CALLS="$TMPDIR/health-calls"
for task_tool in docker systemctl journalctl df du xdg-open omarchy-shell omarchy-system-reboot sudo; do
  cat >"$task_bin/$task_tool" <<'SH'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >>"$HEALTH_TEST_CALLS"
printf ' <%s>' "$@" >>"$HEALTH_TEST_CALLS"
printf '\n' >>"$HEALTH_TEST_CALLS"
if [[ "${0##*/}" == docker && "$*" == *finishedAt* ]]; then
  echo '{"id":"fixture-container","finishedAt":"2026-10-07T22:51:55Z","running":false}'
else
  echo 'inert diagnostic output'
fi
SH
  chmod +x "$task_bin/$task_tool"
done
resolver="$repo_root/scripts/aranea-health-resolve"
printf 'q\n' | "$resolver" 'container:app-test' >"$TMPDIR/view"
rg -q 'restart' "$TMPDIR/view"
rg -q '^docker <logs>' "$HEALTH_TEST_CALLS"
if rg -q '^docker <restart>' "$HEALTH_TEST_CALLS"; then exit 1; fi
# A selected repair is still refused unless it is explicitly confirmed.
printf 'r\nn\nq\n' | "$resolver" 'container:app-test' >/dev/null
if rg -q '^docker <restart>' "$HEALTH_TEST_CALLS"; then exit 1; fi
printf 'r\ny\nq\n' | "$resolver" 'container:app-test' >/dev/null
rg -q '^docker <restart> <--> <app-test>$' "$HEALTH_TEST_CALLS"
: >"$HEALTH_TEST_CALLS"
printf 'r\ny\nq\n' | "$resolver" 'unit:user:demo.service' >/dev/null
rg -q '^systemctl <--user> <restart> <--> <demo.service>$' "$HEALTH_TEST_CALLS"
if rg -q '^sudo ' "$HEALTH_TEST_CALLS"; then exit 1; fi
: >"$HEALTH_TEST_CALLS"
printf 'r\ny\nq\n' | "$resolver" 'unit:system:demo.service' >/dev/null
rg -q '^sudo <systemctl> <restart> <--> <demo.service>$' "$HEALTH_TEST_CALLS"
: >"$HEALTH_TEST_CALLS"
printf 'o\nq\n' | "$resolver" 'disk:/path with spaces' >/dev/null
rg -q '^xdg-open </path with spaces>$' "$HEALTH_TEST_CALLS"
: >"$HEALTH_TEST_CALLS"
printf 'r\nn\nq\n' | "$resolver" 'reboot' >/dev/null
if rg -q '^omarchy-system-reboot' "$HEALTH_TEST_CALLS"; then exit 1; fi
# Even hostile-looking keys remain data and cannot inject shell commands.
if "$resolver" "container:app;touch $TMPDIR/injected" </dev/null >/dev/null 2>&1; then exit 1; fi
test ! -e "$TMPDIR/injected"
: >"$HEALTH_TEST_CALLS"
printf 'a\nq\n' | "$resolver" 'container:app-test' >"$TMPDIR/ack-output"
rg -q 'Alert acknowledged' "$TMPDIR/ack-output"
test -f "$XDG_STATE_HOME/aranea/health-acknowledgments.json"
if rg -q '^docker <restart>' "$HEALTH_TEST_CALLS"; then exit 1; fi
echo 'health resolution contract passed'
