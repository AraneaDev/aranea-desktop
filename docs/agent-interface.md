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
    [--retry-role editor|terminal] [--reobserve-role editor|terminal]
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
`--new-window`, `--retry-role` and `--reobserve-role` are mutually exclusive. Tool arguments are
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

### Project outcomes and safe recovery

A completed public event retains the operation identity and exact owner result.
For example (IDs and timestamp are illustrative):

```json
{
  "schema": 1,
  "timestamp": "2026-01-01T00:00:00Z",
  "operation": "projects.open",
  "operationId": "op-example",
  "event": "completed",
  "status": "partial",
  "data": {
    "outcome": "partial",
    "operation": {
      "id": "op-example",
      "projectId": "p-example",
      "checkoutId": "c-example",
      "sessionId": "session-example",
      "generation": 1,
      "state": "completed",
      "outcome": "partial",
      "steps": [
        { "role": "editor", "status": "observed" },
        { "role": "terminal", "status": "failed", "code": "TOOL_MISSING" }
      ]
    }
  }
}
```

Partial results exit `1`. Read `projects operation OPERATION_ID --json` to reconnect
without resubmitting. Retry only the reported failed role when appropriate:
`projects open PROJECT_ID --checkout CHECKOUT_ID --retry-role terminal --json`.
An accepted but unconfirmed launch can already have created a window; never
infer failure or automatically retry it. Use
`projects open PROJECT_ID --checkout CHECKOUT_ID --reobserve-role terminal --json`
to check a retained accepted identity again without launching. Each explicit
check has a bounded observation period and a new operation ID; the original
launch deadline and completed result remain unchanged. The original pre-launch
window baseline and process identity still apply. Missing or old-session evidence
stays unconfirmed. Role steps expose `reobserveAvailable` when this recovery is
available in project details. `--new-window terminal` explicitly permits an
additional window. Existing owned copies can still make recovery
conservative. Desktop status and project search expose current owner evidence,
not proof that every intended application window exists. After an owner reload,
an occupied saved association with lost ownership evidence holds unknown roles
unconfirmed until an explicit per-role New window choice. Runtime bindings are
never restored from workspace membership or persisted to the registry.

Search, details and JSON all resolve the registered checkout ID to the same
canonical path. Register every desired worktree explicitly. `--separate` preserves
a separate association; `--use-current-workspace` explicitly overrides dedicated
allocation. These flags do not confer ownership on unrelated windows.

## Claude activity adapter

The activity adapter is opt-in and has a single-object `{ok,state,error}` response:

```bash
scripts/aranea-agent-adapter status claude
scripts/aranea-agent-adapter install claude
scripts/aranea-agent-adapter remove claude
scripts/aranea-agent-store snapshot
```

Installation atomically merges this installation's exact command into
`~/.claude/settings.json`. Removal deletes only that command handler, preserving
siblings, unrelated groups, permissions and file mode. Malformed settings and
symlinks are refused without replacing the file. Commands use a quoted absolute
reporter path, fixed `/bin/bash` and `/usr/bin/timeout`, and `/usr/bin:/bin` PATH.
The reporter reads native JSON stdin, stays silent and exits successfully even
when reporting fails; it never supplies an approval decision.

Status distinguishes `commandAvailable`, `configured`, `runtimeObserved`, and
`connectionProven`. Configuration entries do not prove hooks enabled or the
project trusted: `enabled` and `trusted` remain `"unconfirmed"`.
`runtimeObserved` requires a hook observed through proven native process ancestry;
`connectionProven` also requires fresh receipt time and current executable,
PID/start time, boot and ancestor proof. Neither establishes desktop window
ownership.

Baseline installation includes SessionStart, UserPromptSubmit, PreToolUse,
PermissionRequest, PostToolUse, Stop, SessionEnd and Notification. The mapper
also supports PostToolUseFailure, StopFailure, SubagentStart, SubagentStop and
TaskCompleted. These optional handlers are installed only after that particular
native event has been observed through proven provider ancestry. Status reports
mapper support, observation, availability and owned installation separately.
Existing owned optional handlers remain until explicit removal, even if retained
evidence is lost. No version string proves capability. API-error, subagent,
tool-failure and task-completion coverage can therefore be unavailable; explicit
structured activity reports remain the fallback.

A prompt's first nonblank line supplies its label, limited to 160 characters;
full prompts, tool arguments and provider argv are not persisted. Native prompt,
tool, agent and task identities provide correlation. Canonical no-ID deliveries
provide exact replay within the retained 512 receipts. Retained callbacks use their
original task and sequence, including no-ID lifecycle replay across main turns.
Tool results follow the task established by their native tool ID; contradictory
turn identities or changed reuse of an event ID are refused. Native turn identity
and duplicate-delivery certainty are unavailable without `prompt_id`.
PermissionRequest has no native tool ID, so permission resolution stays
unconfirmed. Matching AskUserQuestion/ExitPlanMode results resolve only their
own blockers; unmatched failures append diagnostics. Stop means review handoff,
StopFailure means reported failure, and TaskCompleted finishes only that native
task. None supplies verification evidence.

A genuinely new main turn preserves the earlier turn's state, question and
blockers as inactive history. Fresh session heartbeats cannot revive it; late
callbacks cannot select it as the current turn. Independent child tasks remain
active. The private session metadata contains `currentTaskId`, native `turns`,
optional `inactiveTaskIds`, optional `observedHooks` and optional `callbackOwners`. Only the native mapper
can change these fields; ordinary register/report requests cannot manufacture
hook-observation or callback-ownership evidence. `callbackOwners` retains at most
512 unique records with hashed callback identity, original task/event IDs and
optional bounded native tool ID. Records are pruned with their retained tasks and
receipts; public event labels cannot manufacture ownership.

Legacy epochs without callback ownership remain readable. Explicit mapped native
turn identities remain usable, but uncorrelated callbacks are refused for that
epoch. Start a new Claude provider/session epoch to establish ownership; duplicate
SessionStart or another prompt within the legacy epoch does not enable it.
Status `capabilities.callbackOwnership` reports legacy session count,
`restartRequired` for fresh legacy activity, and recovery text. The count includes
retained legacy history; that history does not block a modern active session.
Historical optional-hook observations alone
do not establish that a legacy epoch has callback coverage.

The private heartbeat runs once per proven process epoch, updates connection
receipts every 15 seconds, and exits on provider identity, session or epoch loss.
Transient store or lock failures retain the same helper and retry at the bounded
15-second cadence, with current process identity revalidated on every attempt.
Only definitive process, session, epoch or ownership loss ends the helper.
It never terminates the provider. Helper ownership lives in private
`$(aranea_state_root)/agent-heartbeats/` identity files; there is no sequence
sidecar. Provenance stores an absolute executable identity and a SHA256 command
fingerprint, never raw argv. Navigation consumers must revalidate process and
window proof immediately before focus.
