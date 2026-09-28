#!/usr/bin/env bash

# Shared JSONL event helpers for the installer CLI. Callers must ensure jq is
# available before emitting events. Every helper writes exactly one JSON object
# to stdout and keeps optional fields absent when they are not supplied.

# Escapes stdin as one JSON string.
json_escape() {
  jq -Rsc .
}

# Emits one JSONL event with optional lifecycle fields.
json_event() {
  local event="$1"
  local operation="$2"
  local status="${3:-}"
  local id="${4:-}"
  local message="${5:-}"
  local code="${6:-}"
  local data="${7:-}"
  local timestamp

  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -cn \
    --arg event "$event" \
    --arg operation "$operation" \
    --arg timestamp "$timestamp" \
    --arg status "$status" \
    --arg id "$id" \
    --arg message "$message" \
    --arg code "$code" \
    --arg data "$data" \
    '({schema: 1, event: $event, operation: $operation, timestamp: $timestamp} |
      if $status != "" then .status = $status else . end |
      if $id != "" then .id = $id else . end |
      if $message != "" then .message = $message else . end |
      if $code != "" then .code = $code else . end |
      if $data != "" then .data = ($data | fromjson) else . end)'
}

# Emits the start event for an operation.
json_started() {
  local data="${2:-}"
  [[ -n "$data" ]] || data='{}'
  json_event started "$1" "" "" "" "" "$data"
}

# Emits a step lifecycle event.
json_step() {
  json_event step "$1" "$2" "$3" "${4:-}" "${5:-}" "${6:-}"
}

# Emits an event that asks the caller for explicit input.
json_prompt() {
  json_event prompt "$1" "required" "$2" "$3" "prompt_required" "${4:-}"
}

# Emits an event describing an actionable recovery step.
json_recovery() {
  json_event recovery "$1" "action_required" "$2" "$3" "recovery_required" "${4:-}"
}

# Emits the terminal event for an operation.
json_completed() {
  json_event completed "$1" "$2" "" "${4:-}" "$3" "${5:-}"
}
