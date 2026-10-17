# Agent interface

Aranea exposes installation, desktop state, projects, actions, and agent activity
through local commands. Use the public `aranea` CLI with `--json` for projects
and tasks; use the operation scripts for installation and repair. Internal
helpers have a different response shape.

| Interface                                              | Output                                    |
| ------------------------------------------------------ | ----------------------------------------- |
| Install, uninstall, doctor, public `aranea ... --json` | Schema-1 JSONL lifecycle events           |
| Wallpaper, updates, Settings                           | One JSON document, specific to the helper |
| Registry, activity store, provider adapter             | One `{ok,state,error}` object             |
| `omarchy-shell` routes                                 | Native IPC strings or documents           |

For current command schemas and host availability, run:

```bash
scripts/aranea capabilities --json | jq -s 'last | .data'
```

Capabilities are inside the completed event's `data`, including `operations`,
`activity`, `projectActions`, and `availability`. They do not initialize the
project registry.

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

For install, uninstall, and doctor, every non-empty stdout line is one JSON
object with `schema: 1`, `event`,
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
`install-terminal`. Uninstall IDs include `stop-actions`, `remove-hooks`, `remove-plugins`,
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

## Desktop state and panel routes

Wallpaper status/catalog and package checks use JSON documents rather than the
lifecycle JSONL stream:

```bash
scripts/aranea-wallpaper list --json
scripts/aranea-wallpaper status --json
scripts/aranea-update-status
scripts/aranea-settings status --json
```

Wallpaper catalog entries include stable `id`, human `label`, absolute `path`,
and `available`. Signal Shrine has ID `signal-shrine`; labels such as Neural Deck
and Ghost in the Wire keep legacy IDs `cockpit` and `monochrome`. Refer to
[Configuration](configuration.md#wallpapers) for the complete thirteen-scene map.
Status reports the observed active wallpaper, rather than a last requested choice.
Package checks report `updates`, `rebootRequired`, and an optional `error`, with a
nonzero exit on an unavailable source. They never install packages.

The live shell retains native IPC entry points for consolidated tabs:

```bash
omarchy-shell omarchy.network show
omarchy-shell aranea.vpn show
omarchy-shell omarchy.bluetooth show
omarchy-shell omarchy.power showPage display
omarchy-shell omarchy.power showPage health
omarchy-shell omarchy.agents selection
omarchy-shell omarchy.agents select codex
```

VPN/Bluetooth open their Network page while hosted, and standalone controls
otherwise. `showPage` returns `ok`, `invalid`, or `unavailable`. Agents `selection`
returns preferred/active provider IDs; `select` persists an available Usage
provider, returning `unavailable` if undiscovered or `refused` during an inert
capture/showcase. These routes open panels or select display preferences; they do
not connect a VPN, toggle Bluetooth, resolve a Health issue, or enable task hooks.
Their return strings are native IPC responses, not lifecycle JSONL events.

### Daily wallpaper schedule

Settings status exposes sorted `state.schedule.entries` objects with `time` and
`wallpaper` fields. Save one or more unique local `HH:MM` times with available
catalog IDs:

```bash
scripts/aranea-settings configure schedule --entries '[{"time":"07:00","wallpaper":"day"},{"time":"20:00","wallpaper":"signal-shrine"}]' --json
```

The Settings adapter delegates to `aranea-wallpaper schedule configure --entries`.
The legacy `configure schedule DAWN DAY DUSK NIGHT --json` interface remains
supported. Saving entries and enabling the schedule are separate operations.

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

Use `scripts/aranea` for the public project interface. Every command accepts
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
    [--open-roles editor,terminal,agent]
aranea projects relocate PROJECT_ID --checkout CHECKOUT_ID --path PATH
aranea projects remove PROJECT_ID
aranea projects open PROJECT_ID [--checkout CHECKOUT_ID] [--separate]
    [--use-current-workspace] [--roles editor,terminal,agent] [--agent claude|codex]
    [--new-window editor|terminal|agent] [--retry-role editor|terminal|agent]
    [--reobserve-role editor|terminal|agent]
aranea projects switch
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

`projects switch` (`projects.switch`, no arguments) opens the compact quick
switcher and launches nothing. It opens the switcher even when it is already
open, never closes it, and reports `Quick switcher opened.` only after reading
back that the switcher is showing. When Projects keeps its full layout because
of unsaved changes or a running setup, it exits 1 with `partial` and
`SWITCHER_BLOCKED`. Without a running Aranea shell it fails with
`OWNER_UNAVAILABLE`.

IDs come from registry responses; names and paths are never IDs. `inspect`
returns the registered record, and `desktop status` returns the timestamped
owner snapshot, including raw registered projects, current session, availability,
operations, and independently validated bindings. An unavailable owner prevents
live observations while registration and inspection remain usable. Removing a
root or registration never deletes repository files or closes applications.

`--open-roles` saves the ordinary Open defaults; `--roles` selects roles for one
request. Each CSV is a nonempty distinct subset of `editor`, `terminal`, `agent`,
normalized by the CLI to that canonical order. Missing saved `openRoles` means
`["editor","terminal"]`. Empty lists, duplicates and unknown roles are invalid.
The owner Open payload accepts `roles` (an optional role array) and `agentId`
(optional `"claude"` or `"codex"`). `--agent` sets `agentId` and requires agent to
be requested, either explicitly, through saved defaults, or as the recovery
target. `--new-window agent` defaults to agent-only when `--roles` is omitted;
with an explicit list, the owner includes the new-window target. Retry and
reobserve target only their named role. Omitted `--agent` uses the owner's
suggestion; reobserve retains the original launch provider.

The owner snapshot adds `agents: {tools, usage}`: `tools` contains the supported
provider probe records, and `usage` maps `claude` and `codex` to local usage
records or null. These are observations, not proof of reporting-hook trust or
window ownership. Suggestions use known headroom and project provider history;
see [the selection rules](workflows.md#start-an-agent-in-a-project). History is
saved before an actual launch attempt, including a failed attempt, and does not
change for focus-only Open or reobserve.

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

`details` sends `{projectId:ID}` to the standalone `araneadev.projects` menu
entry. It reports observed only after the read-only `aranea.projects.capture
captureSnapshot` endpoint confirms `opened` and the exact `projectId`. An
accepted but unconfirmed destination returns partial `DETAILS_UNCONFIRMED` with
`data.accepted: true`. The CLI never invokes capture mutation methods or claims
that summon acceptance proves the destination.

For this public CLI, exit codes are `0` observed, `1` partial/failed,
`2` invalid usage, `3` missing required choice (including `TOOL_CHOICE_REQUIRED`),
and `4` missing dependency. Stable failure codes include `CHECKOUT_MISSING`,
`REGISTRY_CONFLICT`, `TOOL_MISSING`, `AGENT_MISSING`, `COMPOSITOR_UNAVAILABLE`,
`OWNER_UNAVAILABLE`, `OBSERVATION_TIMEOUT`, and `OPERATION_LOST`. Missing Git or
flock is actionable only for commands that need them. Missing jq still emits a
valid dependency-failure JSONL envelope and exits `4`. Its UTC timestamp comes
from validated clock output without jq; only a failed/unusable clock returns
`timestamp: null` with `data.timestampAvailable: false`.

`AGENT_MISSING` means no requested or suggested provider CLI is available. Choose
an installed alternative or install Claude Code or Codex; agents also require a
supported terminal. A missing terminal remains a tool-choice/tool failure rather
than proof that an agent window opened.

### Profiles and environments

All commands accept `--json` and preserve the existing schema-1 JSONL/exit conventions:

```text
aranea projects profiles list PROJECT_ID
aranea projects profiles save PROJECT_ID --definition JSON [--expected-profile-revision N]
aranea projects profiles remove PROJECT_ID PROFILE_ID --expected-profile-revision N
aranea projects profiles seed PROJECT_ID
aranea projects start PROJECT_ID --profile PROFILE_ID
aranea projects environments list --project PROJECT_ID
aranea projects environments return ENVIRONMENT_ID
aranea projects environments forget ENVIRONMENT_ID
aranea projects activation ACTIVATION_ID
```

Profile list returns `data.profiles` and `lastProfileId`. Save/remove return the
acknowledged `data.state`. Configuration works without a desktop owner.
Registration saves default profiles (VS Code, Terminal + Agent, Neovim and
Terminal, each only when its tools are installed). `profiles seed` saves them
for a project that has none; it never changes a project that already has
profiles. Its result reports `seeded` and, when 0, `reason`
(`HAS_PROFILES` or `NO_SUPPORTED_TOOLS`). When the check for installed tools
itself fails or times out, the seed fails with `PROBE_FAILED` and saves
nothing. Saving a profile never launches anything. To save a custom profile:

```bash
aranea projects profiles save PROJECT_ID --definition '{"name":"Focus","roles":["editor","terminal"],"tools":{"editorId":"code","terminalId":"kitty","agentId":null}}' --json
```

For an update include the existing `id` in that definition and supply its positive
`--expected-profile-revision`; omit the expected revision for a new draft. A stale
revision returns `PROFILE_CONFLICT` without overwriting concurrent changes. Roles
are a nonempty distinct subset in editor, terminal, agent order; tool IDs come from
capabilities. There is no profile checkout override or arbitrary shell command.

Start reads the currently selected checkout and exact saved profile revision once,
generates a fresh `a-UUID`, and submits this immutable target to the owner. Preflight
validates current checkout identity, tools, and the workspace for the project's mode:
dedicated takes the lowest workspace without windows or an in-flight reservation (saved
environments and associations alone never reserve one); current shares the focused
workspace beside existing windows and refuses with `INVALID_WORKSPACE` when no current
workspace is known. Acceptance snapshots `checkoutSnapshot`, `profileSnapshot`,
`resolvedTools`, workspace, `mode` (`dedicated` or `current`; absent on older records
means `dedicated`), session, time and UUID identities. The newest placement on a
workspace owns it: environments and dedicated associations record `placedAt` when they
take a workspace. Return refuses with `ENVIRONMENT_CHANGED` when another record was
placed on the saved workspace later; Recover then moves a dedicated environment to a
fresh workspace, and a current-mode environment recovers in place. Open allocates a
fresh workspace instead of reusing an association whose workspace was placed later. Branch is observed at launch, including null for
detached/unborn state. Later edits do not relabel earlier work. Start never runs saved
actions; accepted work continues after the CLI observer exits. Existing ordinary
`projects open` output and behavior are unchanged.

Start may retry only an explicit OWNER_NOT_READY refusal with no operation identity,
within five seconds. Lost, malformed, or contradictory acceptance replies return
`ACCEPTANCE_UNKNOWN`, exit 1, and `data.acceptanceUnknown: true`, preserving
`data.activationId`, immutable `data.target`, known `data.sessionId`, and a concrete
`projects activation a-… --json` recovery command. Never replay that request automatically.

Activation lookup sends only read-only `environmentActivation({activationId})` to the
owner. It validates the current-session retained receipt and returns `data.found`,
`sessionId`, `activationId`, `operationId`, `environmentId`, and a detached `operation`
snapshot when found, including completed operations evicted from ordinary lookup.
Exit 0 means the receipt was observed; inspect `data.operation.outcome` for launch
success. Pending work can be followed with `projects operation OPERATION_ID --json`.
Not-found is partial/unconfirmed with exit 1: receipts are scoped to the current owner,
and a restart or missing receipt does not prove rejection. A later deliberate Start
uses a new identity and may coexist with an earlier request that still finishes.

Environment list returns saved `data.environments`; these records alone do not prove
windows are live. Return resolves the exact environment across registered projects,
observes focus on its saved workspace, and never starts missing roles or another
profile. Forget removes saved metadata and closes no windows. Start/Return require a
live owner; no headless launch is reported. Partial or failed launch outcomes exit 1.
Current-session process/window evidence is required to call a role observed, including
after owner restart. Terminal commands, editor buffers and session contents are never
claimed restored.

The additive owner IPC methods are `prepareEnvironment`, `startEnvironment`,
`returnEnvironment`, `environmentActivation`, and `recoverEnvironment`. Preparation
accepts `{projectId,checkoutId,profileId,profileRevision,activationId}` and reserves
without launching; Start consumes that exact target. Return accepts only
`{projectId,environmentId}`. Recovery accepts those two IDs plus a fresh activation ID
and exactly one original `retryRole`, `newWindowRole` or `reobserveRole`; it retains
the original environment snapshots and workspace. It is separate from Return and
does not dismiss Projects. External occupancy can race after final compositor
readback; after first native dispatch the environment cannot relocate.

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

## Agent activity commands

Usage providers and activity tasks are separate. Usage selection changes the bar
ring; activity comes from explicit reports or opt-in native provider adapters.
All public commands below accept `--json`:

```text
aranea agents status
aranea agents list
aranea agents inspect TASK_ID
aranea agents register --json-input
aranea agents report --json-input
aranea agents focus TASK_ID
aranea agents reopen TASK_ID
aranea agents open-checkout TASK_ID
aranea agents dismiss TASK_ID
aranea agents operation OPERATION_ID [--reobserve]
aranea agents adapter status|install|remove claude|codex
```

Status/list/inspect read the headless store. Focus, reopen, and open-checkout use
the live activity owner and retain an operation ID. Focus targets a proven
hosting terminal; reopen requires a native UUID and current provider evidence.
The observer polls for up to 30 seconds. Disconnection, timeout, or interruption
does not cancel accepted work. Reconnect by operation ID; `--reobserve` checks
that same operation without submitting another action. Dismissal is serialized
through the desktop owner where required. The store's `dismiss-many` mutation
(`{"action":"dismiss-many","args":{"taskIds":[...]}}`) removes a set in one
write. It skips IDs it no longer has, keeps live tasks, and reports
`result.removed`, `result.missing` and `result.refused`. The Tasks panel's Clear
inactive uses it.

Register reads one producer-epoch object on stdin; report reads one event.
For example, after assigning an absolute checkout path to `checkout_path`:

```bash
scripts/aranea agents register --json-input --json <<'JSON'
{"provider":"claude","providerSessionId":"example-session","producerEpoch":"example-epoch","tasks":[]}
JSON
jq -n --arg cwd "$checkout_path" '{schemaVersion:1,eventId:"example-event-1",provider:"claude",providerSessionId:"example-session",producerEpoch:"example-epoch",sequence:1,taskId:"example-task",kind:"snapshot",payload:{cwd:$cwd,reportedState:"working",description:"Review parser"}}' |
  scripts/aranea agents report --json-input --json
```

Session/epoch/task identities and increasing sequences are required. Exact event
replay is retained; conflicting IDs, stale sequences, and old epochs are refused.
Reported working/finished state, blockers, connection freshness, process/window
ownership, and verification are independent. A finish or native Stop does not
verify the work. Structured verification records use reported-pass/reported-fail;
absent evidence remains unknown. Full schemas live in
`scripts/lib/agent-activity.jq`, with public examples exercised in
`tests/agents-cli.test.sh` and `tests/agent-activity.test.sh`.

## Claude activity adapter

The public adapter route supports Claude and Codex. Internal inspection uses:

```bash
scripts/aranea-agent-adapter status claude
scripts/aranea-agent-adapter status codex
scripts/aranea-agent-store snapshot
```

Installation atomically merges only this installation's exact reporter command;
removal deletes that handler while preserving unrelated settings, sibling
handlers, and file mode. Malformed files and symlinks are refused. Claude uses
`~/.claude/settings.json`; Codex uses `${CODEX_HOME:-$HOME/.codex}/hooks.json`,
leaving inline `config.toml` hooks unchanged. Installation does not grant trust
or change permission policies. The native reporter stays silent, returns
success on reporting failure, and supplies no approval decision.

Adapter status separates `commandAvailable`, `configured`, `runtimeObserved`,
and `connectionProven`. Enabled/trusted state remains unconfirmed. Runtime
observation requires native ancestry proof; connection proof adds fresh receipt,
current executable, PID/start-time, boot, and ancestry checks. Neither proves a
desktop window belongs to a task.

Claude's baseline hooks cover session, prompt, tool, permission, Stop, and
Notification events. Optional failure/subagent/completion handlers are installed
only after their particular event has been observed through proven ancestry.
Codex maps its native events with `turn_id`; unsupported Claude-only event names
cannot manufacture Codex tasks. Review each adapter's reported capabilities for
available coverage. Codex user-input and native permission resolution can remain
unconfirmed; explicit structured reports supply the missing state.

The mapper retains only bounded labels/results and correlation evidence, not
full prompts, tool arguments, or raw provider argv. New main turns retain prior
turns as inactive history. Late callbacks and fresh heartbeats cannot revive
an old turn. Native callback ownership fixes the original task/sequence for
replays; contradictory turn reuse is refused. Legacy epochs without that
ownership require a new provider/session epoch for uncorrelated callbacks;
`capabilities.callbackOwnership` reports the restart requirement.

One private heartbeat runs per proven epoch at a 15-second cadence. Transient
store/lock failures retry after identity revalidation; process/session/epoch
loss ends the helper without terminating the provider. Focus always revalidates
process and window evidence immediately before navigation.

## Configured project actions and retained runs

These commands work through the shared headless backend, independently of the
project workspace owner. Every command accepts `--json` and preserves the
schema 1 JSONL protocol. IDs below are opaque IDs returned by list/configure/run.

```text
aranea projects actions list PROJECT_ID
aranea projects actions configure PROJECT_ID --json-input
aranea projects actions remove PROJECT_ID ACTION_ID
aranea projects actions detect PROJECT_ID [--checkout CHECKOUT_ID]
aranea projects actions run PROJECT_ID ACTION_ID [--checkout CHECKOUT_ID]
    [--request-id REQ_ID] [--definition-revision INTEGER]
aranea projects runs list [--project PROJECT_ID]
aranea projects runs inspect RUN_ID
aranea projects runs refresh RUN_ID
aranea projects runs stop RUN_ID
aranea projects runs restart RUN_ID [--request-id REQ_ID]
aranea projects runs logs RUN_ID
aranea projects runs open-preview RUN_ID
```

Configure reads one definition draft from stdin. Save is inert; it does not
require an installed executable or a reachable user manager. For example,
after assigning a registered project ID to `project_id`:

```bash
aranea projects actions configure "$project_id" --json-input --json <<'JSON'
{"name":"Run checks","kind":"command","argv":["npm","test"],"cwdRelative":".","timeoutSeconds":300,"previewUrl":null}
JSON
aranea projects actions configure "$project_id" --json-input --json <<'JSON'
{"name":"Start preview","kind":"service","argv":["npm","run","dev","--","--host","127.0.0.1","--port","5173"],"cwdRelative":".","timeoutSeconds":null,"previewUrl":"http://127.0.0.1:5173/"}
JSON
```

Each `argv` element is one literal argument, including spaces or an empty later
argument. No shell splitting, expansion or evaluation occurs. An explicit shell
must itself be saved as the executable with its arguments. There are no runtime
command overrides, environment-value fields, repository manifests, automatic
dependency installation, privilege prompts, automatic execution or automatic
restart. Configuration is local to Aranea, outside the repository.

`detect` reads the selected exact checkout's own command declarations and
returns suggestions; it saves and runs nothing. Sources are `package.json`
scripts (package manager from `packageManager`, else the lockfile), Composer
scripts and Laravel `artisan`, Makefile targets, justfile recipes (through
`just --dump`), Cargo and `pyproject.toml` (through `python3 -I` and
`tomllib`). Only the root and workspaces declared by `package.json` or
`pnpm-workspace.yaml` are read. Each suggestion's `definition` is a
`configure` draft; `alreadySaved` compares `argv` and `cwdRelative`. Per-source
`status` is `found`, `absent`, `unavailable` (helper missing), `invalid` or
`truncated`; one failing source, including one that cannot be read, never
fails the request. Names starting with `-` are never suggested, so no entry
reaches its runner as an option. Files must be regular files inside the checkout without
symlinks; limits are 1 MiB per file, 32 workspace packages, 100 suggestions,
2 s per helper and 5 s overall. Preview URLs are set only from explicit command
text (`--port N`, `--port=N`, `-p N`, or a leading `PORT=N` assignment) or a
framework's fixed default, and `previewEvidence` says which. Reading
declarations does not make them repository manifests: saved actions remain
local definitions. Detection is read-only, but like other action operations it
is refused while action ingress is retired or draining.

The `detect` backend response, carried as the final CLI event's `data`, is
`{ok,state,error,projectId,checkoutId,suggestions,sources}`; `state` is always
`null`, and `checkoutId` names the exact checkout that was read. Each
suggestion has `key` (`source:cwdRelative:entry`, stable across reads),
`source`, `sourcePath` (checkout-relative declaring file), `entry`, `label`,
`definition`, `previewEvidence` (or `null`) and `alreadySaved`. Each `sources`
row is `{source,status,reason}`, with `reason` `null` unless there is something
to explain. Refusals use `PROJECT_NOT_FOUND` (the project is not registered),
`CHECKOUT_INVALID` (the exact checkout is not registered or unavailable),
`REGISTRY_INVALID` (the project registry could not be read), `DETECTION_FAILED`
(the detector itself failed; individual source failures never do this) and
`INVALID_REQUEST` (malformed request fields). `just --dump` resolves the
justfile's own `import` and `mod` statements; just only parses them and runs
no recipe.

To edit, include the saved action `id`. For revision-checked edits, stdin may
instead be exactly `{"definition":{...},"expectedRevision":42}`, where 42 is the
latest action-state revision. A conflict preserves the saved definition; refresh
and review before explicitly retrying. Editing preserves existing runs' immutable
command snapshots. Removing an action refuses while any run remains protected.

A fresh run uses the selected exact registered checkout, or resolves that
project's current default once when `--checkout` is omitted. It revalidates Git
identity and the working folder; a missing/changed checkout never falls back.
`--definition-revision` optionally guards the reviewed command revision. Omission
uses the current saved definition. CLI Restart explicitly stops the original
exact run and uses the current saved definition; it has no revision option.
The UI instead guards Start and Restart with its displayed revision, and asks
for command review when a run's saved revision differs from today's action.

Start/restart generates a `req-UUID` unless supplied. Keep the request and run IDs.
An accepted event identifies a durably recorded intent, not successful execution.
Exact request replay returns its original run; conflicting reuse refuses.
A fresh Start coalesces with a protected run for the same project, checkout and
action, even after an edit. No postacceptance retry occurs automatically.

The CLI observes for up to ten seconds; transport/final reporting can add time.
Running services or commands return observed running without waiting for exit.
Closing the observer or its deadline yields a partial result and does not cancel
accepted work. Reconnect with inspect (retained metadata), refresh (fresh manager
evidence), or logs. Use stop for explicit cancellation; Restart never launches a
replacement until exact cleanup is confirmed. Exit 0 means successful observation,
1 means partial/domain failure, 2 invalid usage and 4 missing required dependency.
The completed event retains backend errors/recovery and available run/request IDs.

Operation `state`/`outcome`, `processState`, and preview `readiness` are independent.
Exit 0 proves only that command succeeded, not project or agent-task verification.
Pending/running/unconfirmed processes **or** `submissionUnconfirmed:true` remain
protected. Even a succeeded main process may have unconfirmed child cleanup.
Missing manager, changed invocation or uncertain submission cannot establish Stop,
permit duplicate execution, or discard ownership evidence. Boot, transient unit,
immutable command marker and pinned invocation must match before control.

`aranea capabilities --json` includes action operation schemas, `projectActions`
lifetime/bounds contracts and `availability.projectActions` execution, userManager,
journal, previewProbe and opener flags, plus `detectJust` (`just` is present)
and `detectToml` (a `python3` with `tomllib` is present), the helpers `detect`
needs. Execution requires a responsive systemd user manager and systemd-run
254+; the shell panel may be closed. Execution uses
transient user services, noninteractive stdin, no automatic restart, and whole
control-group stopping. Services are not enabled at login and do not promise to
survive logout, user-manager shutdown or reboot. Definition/status metadata remains
local across shell restarts. Project removal retains accepted runs addressable by
run ID; new starts require a registered project.

Service preview reachability is a separate optional one-second numeric-loopback
HTTP(S) probe; it proves neither port ownership nor application correctness.
`open-preview` requires current exact owned running-service proof and a saved URL;
it requests the external opener without claiming the browser displayed anything.
No preview opens automatically. Missing curl/opener affects those capabilities.

Logs are explicit bounded plaintext reads from the local system journal, filtered
by exact unit, invocation and boot. They contain at most 200 entries / 256 KiB,
with sanitization and explicit truncation. Aranea stores no extra output archive;
journal retention follows system policy and is not erased by metadata cleanup.
State is limited to 16 MiB; requests to 1 MiB; definitions to 200 total / 50 per
project; protected runs to 50; terminal history to 100 / seven days; request
receipts to 512. Protected evidence does not silently expire. Command timeout is
1–3600 seconds (default 300); service timeout is null. argv permits 1–64 entries,
1024 characters each / 16 KiB total. Working folders stay inside the exact checkout;
preview URLs use HTTP(S), numeric 127.0.0.1 or [::1] and an explicit port.

Install/deployment and uninstall hold the existing dispatch mutex through their
full lifecycle operation; a busy/unsafe lock reports `action_lifecycle_busy` before
destructive work. Both uninstall scopes fence action ingress, drain dispatch and stop only proven
owned runs before removing definitions/history or installed recovery tools. A
failed drain reports `action_teardown_failed`, keeps protected payload/tools and
blocks reinstall activation until recovery. Inspect/refresh/stop the retained run
ID, restore manager access as needed, then retry uninstall. Successful removal
retains only the inert action coordination files `project-actions.json.lock` and
`project-actions.json.dispatch.lock`, alongside `agent-activity.json.lock` and
necessary ancestors; reinstall preserves their inodes while activating a fresh
generation. Journal data, repositories, unrelated services and editor/provider
processes are not removed by action cleanup.

## Task checkouts and Git

These commands create and remove task checkouts, fetch, pull or push a checkout, and read or mark a task checkout review.
Every command accepts `--json` and preserves the schema 1 JSONL protocol. When
`--checkout` is omitted for `git fetch`/`git pull`, the project's selected
checkout is used.

```text
aranea projects git fetch PROJECT_ID [--checkout CHECKOUT_ID]
aranea projects git pull PROJECT_ID [--checkout CHECKOUT_ID]
aranea projects git push PROJECT_ID [--checkout CHECKOUT_ID]
aranea projects review PROJECT_ID --checkout CHECKOUT_ID
aranea projects review mark PROJECT_ID --checkout CHECKOUT_ID
aranea projects task new PROJECT_ID --branch BRANCH
aranea projects task remove PROJECT_ID --checkout CHECKOUT_ID
    [--check] [--confirm-unpushed]
```

Agents that want an isolated working copy should use `aranea projects task new`
and work in the returned `path`; remove it with `task remove` when done.

Git runs without prompts: `GIT_TERMINAL_PROMPT=0`, no askpass, stdin from
`/dev/null`, and `-o BatchMode=yes` appended to the SSH command (your
`core.sshCommand` or `GIT_SSH_COMMAND`, else `ssh`). Your own Git config,
credentials and hooks apply. Network operations and `worktree add` stop after
60 s; every local Git call (status, ref reads, `worktree remove`) stops after
15 s with `GIT_TIMEOUT`. One operation runs per repository at a time; a
second waits up to 75 s.

Result fields, carried as the final CLI event's `data`:

- `git fetch`: `{projectId,checkoutId,remote}`. The remote is the current
  branch's upstream remote, else `origin`, else the only remote.
- `git pull`: `{projectId,checkoutId,remote,from,to,updated}`. It fetches, then
  runs `git merge --ff-only @{upstream}`; it never creates a merge commit or
  stashes.
- `git push`: `{projectId,checkoutId,remote,branch,upstream,pushed}`. It runs
  `git push --set-upstream <remote> <branch>` for the checkout's current branch
  only. It never forces and never pushes other branches, tags or submodules.
  The remote is chosen as for `git fetch`.
- `review`: read-only, and it never fetches.
  `{projectId,checkoutId,branch,base,mergeBase,head,ahead,behind,commits,files,uncommitted,truncated}`.
  Only task checkouts can be reviewed. The base is chosen as for `task new`
  (`refs/remotes/<remote>/HEAD`, then `<remote>/main`, `<remote>/master`, then
  local `main`, `master`). `commits` is `[{sha,subject}]`, newest first, at most 50. `files` is `[{path,added,removed}]` from the numstat of the merge base against `HEAD`, at most 200; binary files report `added` and `removed`
  as `null`. `uncommitted` is `{dirty,untracked}`. `truncated` is true when
  either list was cut.
- `review mark`: `{projectId,checkoutId,head,taskFinishedAt}`. It saves the
  checkout's current head and the time of its latest finished agent task
  (`null` when there is none or the activity state cannot be read) as reviewed.
  The review card returns when the head changes or a task finishes later.
  Removing the checkout drops the mark.
- `task new`: `{projectId,checkoutId,path,branch,base}`. It fetches, then starts
  the new branch (with `--no-track`) from `refs/remotes/<remote>/HEAD`, else
  `<remote>/main`, else `<remote>/master`; without a remote, from local `main`,
  else `master`. The folder is
  `<dirname of the primary path>/<basename>-worktrees/<branch with / as ->`. It
  is registered and selected; nothing launches.
- `task remove --check`:
  `{projectId,checkoutId,path,branch,dirty,untracked,ignored,busy,unpushed,detached,missing}`.
  Nothing is changed. `ignored` is the count of ignored paths that would be
  deleted with the folder; they warn but never refuse. `busy` is true while an
  action run for that checkout is pending, running or unconfirmed, or has
  `submissionUnconfirmed`. `unpushed`
  counts commits on no remote (without remotes, commits not on local
  `main`/`master`). `detached` counts commits reachable from no branch and no
  remote when HEAD is detached, else 0 (always 0 when `missing`). It blocks
  removal. Ignore rules include your own `core.excludesFile`. `missing` is true when the folder is gone.
- `task remove`: `{projectId,checkoutId,path,branch,removed}`. It never uses
  `--force` and always keeps the branch. A task checkout whose folder was
  deleted by hand can still be removed: `missing` is `true` and removal only
  forgets it (with `GIT_ERROR` if other stale worktrees would also be pruned).
  A detached HEAD with commits on no branch is always refused with
  `UNPUSHED_COMMITS`, even with `--confirm-unpushed`.

Refusals use these codes:

- `REGISTRY_INVALID`: the project registry could not be read.
- `CHECKOUT_INVALID`: the exact checkout is not registered or does not prove as
  that repository.
- `PROJECT_NOT_FOUND`: the project is not registered (no checkout to default to).
- `INVALID_REQUEST`: malformed or unsupported arguments.
- `DEPENDENCY_MISSING`: `jq`, `git`, `timeout`, `flock`, `mktemp`, `sha256sum`
  or `realpath` is not installed.
- `GIT_BUSY`: another operation on the repository held the lock for more than 75 s.
- `AUTH_REQUIRED`: the remote needs credentials; run `git fetch` once in a terminal.
- `GIT_TIMEOUT`: Git did not finish in time. Nothing is deleted after a timeout.
- `GIT_ERROR`: any other Git failure, with Git's first error line.
- `NO_REMOTE`: fetch or push with no remote.
- `NO_BRANCH`: push from a detached HEAD.
- `PUSH_REJECTED`: the remote has newer commits ("The remote has newer commits;
  fetch and update first."). Nothing is forced.
- `NO_UPSTREAM`: pull on a branch that tracks nothing, or a detached HEAD.
- `NOT_FAST_FORWARD`: pull on diverged branches.
- `LOCAL_CHANGES`: pull would overwrite local changes.
- `INVALID_BRANCH`: not a valid branch name, starts with `-`, or contains `@{`.
- `BRANCH_EXISTS`: a local branch of that name exists.
- `NO_DEFAULT_BRANCH`: no remote default, `main` or `master` to start from or
  to review against.
- `PATH_EXISTS`: the target folder already exists.
- `REGISTER_FAILED`: the checkout was created (or Git stopped after creating
  its folder, for example in a slow `post-checkout` hook) but could not be
  registered; the recovery names the folder and how to register or remove it.
- `PRIMARY_CHECKOUT`: removal, `review` or `review mark` of the main checkout
  was requested.
- `CHECKOUT_DIRTY`: uncommitted or untracked changes.
- `CHECKOUT_BUSY`: a protected action run exists for the checkout.
- `ACTIONS_UNAVAILABLE`: the action store could not be read, so removal fails closed.
- `UNPUSHED_COMMITS`: commits on no remote without `--confirm-unpushed`, or any
  commits on a detached HEAD that are reachable from no branch and no remote. It
  never fires for a checkout whose folder is missing, which has no unpushed gate
  because the branch is kept.
- `UNREGISTER_FAILED`: the folder was removed but Projects could not forget it.

The `capabilities` result carries `projectGit`:
`{schemaVersion:1,worktreeLocation:"<repo>-worktrees/<branch>",base:"remote default branch, else local main/master",pull:"fast-forward only",removeKeepsBranch:true,networkSeconds:60,localSeconds:15}`,
and lists the operations `projects.git.fetch`, `projects.git.pull`,
`projects.git.push`, `projects.review`, `projects.review.mark`,
`projects.task.new` and `projects.task.remove`.
