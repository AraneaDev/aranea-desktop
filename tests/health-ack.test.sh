#!/usr/bin/env bash
# Acknowledgments apply to one stopped-container occurrence, never future failures.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/sandbox.sh
source "$repo_root/tests/lib/sandbox.sh"
task_bin="$TMPDIR/ack-bin"
mkdir -p "$task_bin"
export PATH="$task_bin:$PATH"
export HEALTH_CONTAINER_STATE="$TMPDIR/container-state"
cat >"$task_bin/docker" <<'SH'
#!/usr/bin/env bash
[[ "$1" == inspect ]] || exit 1
cat "$HEALTH_CONTAINER_STATE"
SH
chmod +x "$task_bin/docker"
echo '{"id":"container-one","finishedAt":"2026-10-07T22:51:55Z","running":false}' >"$HEALTH_CONTAINER_STATE"
ack="$repo_root/scripts/aranea-health-ack"
"$ack" acknowledge 'container:demo' >/dev/null
"$ack" status | jq -e '.acknowledged == ["container:demo"]' >/dev/null
test -f "$XDG_STATE_HOME/aranea/health-acknowledgments.json"
# A second process reads persistent state, not a service-local dismissal.
"$ack" status | jq -e '.acknowledged == ["container:demo"]' >/dev/null
echo '{"id":"container-one","finishedAt":"2026-10-07T22:51:55Z","running":true}' >"$HEALTH_CONTAINER_STATE"
"$ack" status | jq -e '.acknowledged == []' >/dev/null
if "$ack" acknowledge 'container:demo' >/dev/null 2>&1; then exit 1; fi
# A later failure of the same named container must be visible again.
echo '{"id":"container-one","finishedAt":"2026-10-12T21:00:00Z","running":false}' >"$HEALTH_CONTAINER_STATE"
"$ack" status | jq -e '.acknowledged == []' >/dev/null
old='{"id":"container-one","finishedAt":"2026-10-07T22:51:55Z","running":false}'
if "$ack" acknowledge 'container:demo' "$old" >/dev/null 2>&1; then exit 1; fi
"$ack" acknowledge 'container:demo' >/dev/null
echo '{"id":"replacement-container","finishedAt":"2026-10-12T21:00:00Z","running":false}' >"$HEALTH_CONTAINER_STATE"
"$ack" status | jq -e '.acknowledged == []' >/dev/null
"$ack" forget 'container:demo' >/dev/null
"$ack" status | jq -e '.acknowledged == []' >/dev/null
if "$ack" acknowledge 'unit:user:demo.service' >/dev/null 2>&1; then exit 1; fi
echo 'health acknowledgment contract passed'
