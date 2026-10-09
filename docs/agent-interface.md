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

## Internal project registry

`scripts/aranea-project-store snapshot` reads the versioned registry at
`$(aranea_state_root)/projects.json`. `mutate` accepts one JSON object on stdin
with `action`, `args`, and optional `expectedRevision`. It returns a single
`{ok,state,error}` object and exits `0` on success or `1` on failure. This
internal helper has its own response contract rather than the JSONL event
protocol above.

Project paths may contain Unicode, spaces, quotes, and shell metacharacters.
Raw paths and their canonical targets must contain no ASCII control characters
(`U+0000` through `U+001F`, or `U+007F`), including tabs and newlines. Such paths
return `INVALID_PATH` before mutation; choose or rename a folder whose canonical
path contains no ASCII controls. The helper never silently trims a selected
path to a different sibling.

`CHECKOUT_INVALID` means the selected folder is missing or is not an exact Git
checkout root. `CHECKOUT_CONFLICT` means an existing checkout already owns the
path or relocation would mix unrelated repository groups. Locate a checkout
from the same group; when moving a whole repository, locate its moved checkouts
explicitly. `REGISTRY_CONFLICT` requires refreshing the snapshot and retrying
with its current revision. Invalid or unsupported registry data returns
`REGISTRY_INVALID` and leaves the original file intact for backup and repair.

## Public project commands

Use `scripts/aranea` for the public Phase 1 interface. Every command accepts
`--json`; without it, output is human readable. `capabilities --json` describes
all argument schemas, installed supported tools, dependency availability, and
owner availability. Capabilities does not initialize or mutate the registry.

```text
aranea capabilities
aranea projects list
aranea projects inspect PROJECT_ID
aranea projects roots add PATH
aranea projects roots remove ROOT_ID
aranea projects discover [--root ROOT_ID]
aranea projects register --path PATH [--path PATH ...]
aranea projects ignore --path PATH
aranea projects ignored
aranea projects unignore --path PATH
aranea projects configure PROJECT_ID [--name NAME] [--editor code|nvim]
    [--terminal alacritty|kitty|foot|ghostty] [--workspace dedicated|current]
aranea projects relocate PROJECT_ID --checkout CHECKOUT_ID --path PATH
aranea projects remove PROJECT_ID
aranea projects open PROJECT_ID [--checkout CHECKOUT_ID] [--separate]
    [--use-current-workspace] [--new-window editor|terminal]
    [--retry-role editor|terminal]
aranea projects operation OPERATION_ID
aranea projects details PROJECT_ID
aranea desktop status
```

For example, review candidates with `scripts/aranea projects discover --json`,
then explicitly register selected folders:

```bash
scripts/aranea projects roots add '/home/me/Work' --json
scripts/aranea projects register --path '/home/me/Work/My Project' --json
scripts/aranea projects list --json
scripts/aranea projects open p-REPLACE-WITH-REGISTERED-ID --json
scripts/aranea projects operation op-REPLACE-WITH-RETURNED-ID --json
```

IDs come from registry responses; names and paths are never IDs. `inspect`
returns the registered record, and `desktop status` returns the timestamped
owner snapshot, including raw registered projects, current session, availability,
operations, and independently validated bindings. An unavailable owner prevents
live observations while registration and inspection remain usable. Removing a
root or registration never deletes repository files or closes applications.

The selected checkout is resolved from a fresh registry snapshot and validated
against its exact canonical Git path and common-directory identity before Open.
A missing selected checkout is never silently replaced. Discovery alone does
not register anything; register and relocate revalidate under the store lock.
Mutations carry the snapshot revision and return `REGISTRY_CONFLICT` if another
writer changes it. Invalid IDs and contradictory options are rejected before
IPC. `--separate` and `--use-current-workspace` are mutually exclusive;
`--new-window` and `--retry-role` are mutually exclusive. Tool arguments are
fixed supported adapter IDs; custom shell commands are unsupported.

New CLI envelopes use the existing schema 1 lifecycle and add `operationId`
when an owner operation exists. Existing installer/helper envelopes remain
unchanged. A `step` with `status: accepted` means the owner accepted the request;
only `completed.data.outcome: observed` reports observed success. Role steps
retain their own status/code, and changed step records are emitted once per
observer. A configured `TOOL_MISSING` role can produce a partial result while
another role succeeds.

Open submits one accepted operation and polls that ID every 250 ms for up to
30 seconds. Only rejected `OWNER_NOT_READY` responses with a null operation ID
may be retried, for at most five seconds. Accepted requests are never
resubmitted automatically. Timeout (`OBSERVATION_TIMEOUT`), disconnection
(`OWNER_UNAVAILABLE`), and interruption (`OBSERVER_CANCELLED`) stop only the
CLI observer; owner work continues. Preserve the returned operation ID and
reconnect with `projects operation OPERATION_ID --json`. A session/generation
change or evicted result returns `OPERATION_LOST`; inspect state before deciding
to create a new operation. A submission whose reply is lost, empty, malformed, or nonconforming may already
have been accepted. These indeterminate replies return `OWNER_UNAVAILABLE` and
instruct inspection of owner state before any new submission. Only a conforming
explicit refusal is trusted as a rejection.

`details` sends a Settings summon payload `{section:"projects",projectId:ID}`.
It reports observed only after the read-only
`aranea.settings.capture captureSnapshot` endpoint confirms `opened`, the
Projects section, and the exact `projectId`. The Settings Projects destination
must provide this field; earlier Settings versions return partial
`DETAILS_UNCONFIRMED` with `data.accepted: true`. The CLI never invokes capture
mutation methods or claims that summon acceptance proves the destination.

For this public CLI, exit codes are `0` observed, `1` partial/failed,
`2` invalid usage, `3` missing required choice (including `TOOL_CHOICE_REQUIRED`),
and `4` missing dependency. Stable failure codes include `CHECKOUT_MISSING`,
`REGISTRY_CONFLICT`, `TOOL_MISSING`, `COMPOSITOR_UNAVAILABLE`,
`OWNER_UNAVAILABLE`, `OBSERVATION_TIMEOUT`, and `OPERATION_LOST`. Missing Git or
flock is actionable only for commands that need them. Missing jq still emits a
valid dependency-failure JSONL envelope and exits `4`. Its UTC timestamp comes
from validated clock output without jq; only a failed/unusable clock returns
`timestamp: null` with `data.timestampAvailable: false`.
