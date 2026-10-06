#!/usr/bin/env bash
# Contract for the araneadev.health plugin: every check command is timeout
# bounded and never a shell string, service/panel/metrics wiring stay split
# by responsibility (no cross-posting to notifications), the top-process
# sampler tracks open panels rather than a shared boolean, and the
# final-review minors below.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

# Logic contract: tests/js/health.test.js (node:test; run by tests/js.test.sh).

# Every check command is bounded: a hung df/systemctl/docker must become
# "unknown", not freeze the check (review Important #4).
health_qml="$repo_root/plugins/araneadev.health/Monitor.qml"
for cmd in '"systemctl", "list-units"' '"systemctl", "--user"' '"df"'; do
  grep -F "command: [\"timeout\", \"10\", $cmd" "$health_qml" >/dev/null || {
    echo "unbounded check command: $cmd" >&2
    exit 1
  }
done
# docker goes through dockerCommand (tests replace it); still bounded.
grep -Fq 'property var dockerCommand: ["docker"]' "$health_qml"
grep -Fq 'command: ["timeout", "10"].concat(monitor.dockerCommand, ["info"' "$health_qml"
grep -Fq 'command: ["timeout", "10"].concat(monitor.dockerCommand, ["ps"' "$health_qml"
grep -Fq '"-l"' "$health_qml"
grep -Fq '"--since"' "$health_qml"
grep -Fq 'HealthLogic.pruneDockerHistory' "$health_qml"
grep -Fq '"which", "xdg-terminal-exec"' "$health_qml"
if grep -Eq '"bash", *"-c"|"sh", *"-c"' "$health_qml"; then
  echo "Monitor.qml must not run shell strings" >&2
  exit 1
fi
plugin="$repo_root/plugins/araneadev.health"
jq -e '(.kinds | index("service")) and .entryPoints.service == "Service.qml" and .id == "araneadev.health"' "$plugin/manifest.json" >/dev/null
grep -Fq '.pragma library' "$plugin/HealthBridge.js"
grep -Fq 'HealthBridge.publish(service)' "$plugin/Service.qml"
if grep -Eq 'ServiceBridge|NotificationsBridge|FileViewError|upsertSourceItem' "$plugin/Monitor.qml"; then
  echo "health must not post to the notification center" >&2
  exit 1
fi
grep -Fq 'HealthLogic.annotateProblems' "$plugin/Monitor.qml"
test ! -e "$repo_root/plugins/araneadev.notifications/Health.qml"

grep -Fq 'MetricsLogic.cpuPercent' "$plugin/Metrics.qml"
grep -Fq 'running: metrics.topActive' "$plugin/Metrics.qml"
grep -Fq 'Metrics {' "$plugin/Service.qml"

jq -e '(.kinds | index("bar-widget")) and .entryPoints.barWidget == "Panel.qml" and .barWidget.defaultSection == "right"' "$plugin/manifest.json" >/dev/null
grep -Fq 'HealthBridge.current()' "$plugin/Panel.qml"
grep -Fq 'All systems healthy' "$plugin/HealthProblemsSection.qml"
grep -Fq 'String.fromCodePoint(0xf05f6)' "$plugin/Panel.qml"

# One dropdown per monitor: top-process sampling follows an open-panel count,
# never a shared boolean one bar can switch off for another (review Important #1).
# The count itself and a reload moving it: tests/qml/health.qml.
grep -Fq 'service.panelOpened()' "$plugin/Panel.qml"
grep -Fq 'Component.onDestruction' "$plugin/Panel.qml"
if grep -Fq 'service.metrics.topActive = opened' "$plugin/Panel.qml"; then
  echo "Panel must not set topActive directly" >&2
  exit 1
fi

# --- final-review minors
# 1: a sample still in flight when the dropdown closes is dropped
grep -A1 -F 'if (!metrics.topActive)' "$plugin/Metrics.qml" | grep -Fq return
# 2: page size and clock tick come from getconf, not constants
grep -Fq '"getconf", "PAGESIZE"' "$plugin/Metrics.qml"
grep -Fq '"getconf", "CLK_TCK"' "$plugin/Metrics.qml"
if grep -Eq 'parseProcStat\(text, 4096\)|, 3, 100\)' "$plugin/Metrics.qml"; then
  echo "page size / clock tick must not be hard-coded" >&2
  exit 1
fi
# 3: TOP rows survive the service disappearing mid-reload
if grep -Fq 'readonly property var c: root.m.topProcs' "$plugin/Panel.qml"; then
  echo "TOP rows must guard root.m" >&2
  exit 1
fi
# 4: the CPU trace follows the samples only while the dropdown is open
grep -Fq 'HealthDropdown {' "$plugin/Panel.qml"
grep -Fq 'HealthResourceSection {' "$plugin/HealthDropdown.qml"
grep -Fq 'samples: root.active && root.metrics ? HealthLogic.cpuSamples(' "$plugin/HealthResourceSection.qml"
# 5: missing-service summary remains readable; unavailable and empty states
# are exercised by tests/qml/health-panel-components.qml.
# 9: branding paths honour XDG_STATE_HOME everywhere
# (Omarchy's own state files, e.g. clipboard-history.json, stay at the
# $HOME path its scripts hard-code; only branding assets are theme-owned.)
if grep -rFq 'Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/branding' "$repo_root/plugins"; then
  echo "branding paths must honour XDG_STATE_HOME" >&2
  exit 1
fi

# `omarchy-shell health refresh` reruns the checks now (captures, scripts).
grep -Fq 'function refresh(): string' "$plugin/Service.qml"
grep -Fq 'samples: service.metrics.cpuHistory.length' "$plugin/Service.qml"

# --- 4c: the cursor follows its problem; a reloaded service is counted again
hpanel="$repo_root/plugins/araneadev.health/Panel.qml"
grep -Fq 'property string cursorKey: ""' "$hpanel"
grep -Fq 'HealthLogic.cursorMove(' "$hpanel"
if grep -Fq 'root.problems[root.cursor]' "$hpanel"; then
  echo "Enter must run the row under cursorKey" >&2
  exit 1
fi
grep -Fq 'onServiceChanged:' "$hpanel"

# --- 4c: docker OOM events are watched (a failed `docker ps` never clearing
# problems: tests/qml/health.qml)
mon="$repo_root/plugins/araneadev.health/Monitor.qml"
grep -Fq '"--filter", "event=oom"' "$mon"

# --- 4c: rates use the uptime clock
metrics_qml="$repo_root/plugins/araneadev.health/Metrics.qml"
grep -Fq 'MetricsLogic.uptimeMs(' "$metrics_qml"
if grep -Fq 'var now = Date.now()' "$metrics_qml"; then
  echo "rates must not use the wall clock" >&2
  exit 1
fi

# --- 4c final review: a cursor whose problem is gone is cleared
grep -Fq 'onCursorChanged: if (root.cursor < 0 && root.cursorKey)' "$hpanel"
grep -Fq '137 or 143' "$repo_root/README.md"

echo "health contract passed"
