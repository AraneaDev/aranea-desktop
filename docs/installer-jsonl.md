# Installer JSONL Protocol

The Aranea installer keeps human-readable output by default. Pass `--json` to
`scripts/install.sh`, `scripts/uninstall.sh`, or `scripts/aranea-doctor` for a
newline-delimited JSON event stream (JSONL).

```bash
scripts/install.sh --json --yes --profile full
scripts/uninstall.sh --json --yes --scope integration
scripts/uninstall.sh --json --yes --scope complete --replacement-theme Omarchy
scripts/aranea-doctor --json
```

Every non-empty stdout line is one complete JSON object. Do not parse the
human-readable `message` field to determine state; use `event`, `status`,
`code`, and stable step IDs. In JSON mode, diagnostics are kept off JSON
stdout.

## Common envelope

Every event includes:

| Field | Values | Meaning |
| --- | --- | --- |
| `schema` | `1` | Protocol version. |
| `event` | `started`, `step`, `prompt`, `recovery`, `completed` | Event kind. |
| `operation` | `install`, `uninstall`, `doctor` | Operation producing the event. |
| `timestamp` | UTC ISO-8601 | Event creation time. |

Events may also include `status`, `code`, `id`, `message`, and `data`.

## Events

`started` is the first event and includes operation options in `data`.

`step` reports a stable operation step. Its status is `running`, `ok`,
`warning`, or `failed`. Agents should key on `id`, not the message. Current
step IDs are:

- install: `validate`, `persist-profile`, `install-theme`, `adopt-theme`,
  `install-hooks`, `activate-theme`, `install-cursor`, `install-icons`,
  `install-terminal`;
- uninstall: `remove-hooks`, `remove-plugins`, `remove-timer`,
  `restore-managed-files`, `restore-settings`, `remove-state`, `remove-theme`;
- doctor: the health-check IDs already reported by the doctor, such as `theme`,
  `hooks`, `manifest`, `icons`, `plugins`, `runtime`, and `health`.

`prompt` means a required decision was not supplied by flags. For unattended
use, provide the relevant option or treat the operation as cancelled.

`recovery` carries an actionable recovery message, such as the command to
restore the previously active theme after a failed install.

`completed` is the final normal event. Its status is `ok`, `warning`,
`cancelled`, or `failed`.

Example successful install:

```json
{"schema":1,"event":"started","operation":"install","timestamp":"2026-09-28T10:00:00Z","data":{"profile":"full","dry_run":false,"assume_yes":true}}
{"schema":1,"event":"step","operation":"install","timestamp":"2026-09-28T10:00:01Z","status":"running","id":"install-theme","message":"install theme"}
{"schema":1,"event":"step","operation":"install","timestamp":"2026-09-28T10:00:04Z","status":"ok","id":"install-theme","message":"theme installed as aranea"}
{"schema":1,"event":"completed","operation":"install","timestamp":"2026-09-28T10:00:05Z","status":"ok","message":"Aranea installed."}
```

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Operation completed successfully. A doctor warning is still represented in its final event. |
| `1` | Operation failed. |
| `2` | Invalid usage or option. |
| `3` | Cancelled or required user decision was not supplied. |
| `4` | Required dependency is missing, normally `jq` for JSON mode. |

Use both the final event and the process exit code. The exit code is the
authoritative shell result; the final event explains what happened.

## Uninstall scopes

The default scope is `integration`, which removes Aranea hooks, plugins,
managed files, settings, timers, and state while leaving the theme directory.

Use `--scope complete` to also call `omarchy theme remove aranea`. If Aranea
is active, provide `--replacement-theme THEME` or use `--yes` only when the
automation explicitly accepts the active-theme transition.

Preview either scope with `--dry-run`. A dry run emits the same event shape but
does not change the system.
