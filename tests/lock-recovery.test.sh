#!/usr/bin/env bash
# Lock recovery must consult the ownership-aware helper with the shell PID,
# and retry an undetermined result instead of taking another locker's lock.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

service="$repo_root/plugins/araneadev.lock/Service.qml"
# shellcheck disable=SC2016 # Match the literal QML command, not this test's PID.
grep -Fq 'omarchy-hyprland-session-lock-stranded \"$PPID\"' "$service"
grep -Fq 'if (exitCode === 2)' "$service"
grep -Fq 'root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested' "$service"
echo 'lock recovery checks ownership before reclaiming a lock'
