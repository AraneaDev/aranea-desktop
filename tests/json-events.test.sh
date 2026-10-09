#!/usr/bin/env bash
# Contract for the shared installer JSONL event helpers.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

source "$repo_root/scripts/lib/json-events.sh"

quoted_message='quoted "message"'
line="$(json_event step install ok install-theme "$quoted_message")"
jq -e '
  .schema == 1 and
  .event == "step" and
  .operation == "install" and
  .status == "ok" and
  .id == "install-theme" and
  .message == "quoted \"message\""
' <<<"$line" >/dev/null

started="$(json_started install '{"profile":"full","dry_run":true}')"
jq -e '
  .event == "started" and
  .operation == "install" and
  .data.profile == "full" and
  .data.dry_run == true
' <<<"$started" >/dev/null

completed="$(json_completed install failed operation_failed 'install failed')"
jq -e '
  .event == "completed" and
  .operation == "install" and
  .status == "failed" and
  .code == "operation_failed" and
  .message == "install failed"
' <<<"$completed" >/dev/null

prompt_event="$(json_prompt uninstall replacement_theme 'choose a replacement')"
restore_command='omarchy theme set "Adwaita"'
recovery_event="$(json_recovery install restore_theme "$restore_command")"
for event in "$prompt_event" "$recovery_event"; do
  jq -e '.schema == 1 and .event and .operation and .timestamp and .status and .id and .message' <<<"$event" >/dev/null
done

echo "json event contract passed"

operation_event="$(json_event step projects.open accepted request '' '' '{}' op-123-1)"
jq -e '.operationId == "op-123-1"' <<<"$operation_event" >/dev/null
jq -e 'has("operationId")|not' <<<"$line" >/dev/null
