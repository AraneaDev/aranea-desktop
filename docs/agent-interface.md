# Agent interface

Aranea exposes the same operations to humans and automation. Humans can run
`./installer`; agents should call the operation scripts directly with
`--json` and consume JSONL events.

## Commands

```bash
scripts/install.sh --json --yes --profile full
scripts/uninstall.sh --json --yes --scope integration
scripts/uninstall.sh --json --yes --scope complete --replacement-theme Omarchy
scripts/aranea-doctor --json
scripts/aranea-doctor --json --fix
```

`--dry-run` is supported by install and uninstall. It emits the same event
shape without changing the system.

## Protocol contract

Every non-empty stdout line is one JSON object with `schema: 1`, `event`,
`operation`, and UTC `timestamp`. Event types are:

- `started`: operation and selected options in `data`;
- `step`: stable `id` and lifecycle `status`;
- `prompt`: an input is required for safe continuation;
- `recovery`: an actionable recovery instruction;
- `completed`: final status and summary.

Use `id`, `status`, and `code` for decisions. `message` is for display and
should not be parsed as a contract.

Install step IDs include `validate`, `persist-profile`, `install-theme`,
`install-hooks`, `activate-theme`, `install-cursor`, `install-icons`, and
`install-terminal`. Uninstall IDs include `remove-hooks`, `remove-plugins`,
`remove-timer`, `restore-managed-files`, `restore-settings`, `remove-state`,
and `remove-theme`. Doctor step IDs are its check IDs, such as `theme`,
`hooks`, `branding`, `icons`, `plugins`, `runtime`, and `health`.

## Exit codes

| Code | Meaning                                                         |
| ---- | --------------------------------------------------------------- |
| `0`  | Completed; doctor may still report a warning in its final event |
| `1`  | Operation failure                                               |
| `2`  | Invalid usage                                                   |
| `3`  | Cancelled or missing required decision                          |
| `4`  | Missing dependency, normally `jq`                               |

Treat the process exit code as authoritative and use the final event for the
explanation.

## Agent pattern

```bash
set -o pipefail
events_file="$(mktemp)"
if scripts/install.sh --json --yes --profile minimal >"$events_file"; then
  jq -s 'last | select(.event == "completed")' "$events_file"
else
  jq -c 'select(.event == "recovery" or .event == "completed")' "$events_file"
  exit 1
fi
rm -f "$events_file"
```

Do not invoke complete removal without making the replacement-theme decision
explicit. Prefer `--dry-run` before a destructive action and preserve recovery
events in logs.
