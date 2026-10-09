# Aranea activity

A keep-loaded menu plugin owns local activity projection and navigation operations.
It creates no window. Closing a panel or CLI observer does not cancel accepted work.
The activity store remains the authority for reported lifecycle, verification,
connection receipts, retention, association and dismissal.

## IPC and clients

`aranea.activity` exposes `snapshot()`, `request(json)`, `operation(id)`,
`reobserve(id)` and `dismiss(taskId)`. Requests contain exactly `action` and
`taskId`; actions are `focus`, `reopen` and `open-checkout`. Acceptance returns
`{ok,operationId,ownerId,error}`. Read an accepted ID to observe its outcome:
`observed`, `partial` or `failed`. An owner restart returns `OPERATION_LOST`;
accepted work may still be running and must never be resubmitted automatically.

`ActivityClient` exposes `snapshot`, `available`, structured `error`, `pending`,
`operationId`, `currentOperation`, `request(payload)`, `refresh()`,
`reconnect(id?)`, `reobserve()` and `dismiss(taskId)`. Snapshot read generations
are independent of operation observation. Only explicit `OWNER_NOT_READY`
refusals retry the original submission. Reconnect reads the accepted ID.
Reobserve explicitly checks a retained partial resume without launching,
preparing, moving or focusing anything.

A launch submission outlives the observation deadline. `submissionPending`
protects its operation from eviction and repeat submission; unrelated actions
can continue. A late accepted identity remains on the original partial operation
for reconnect and explicit reobserve. The short-lived launcher transport is
bounded to two seconds. Timeout or malformed acceptance sets
`submissionUnconfirmed`; it does not prove that no agent started and does not
permit another automatic or duplicate submission. Inspect the retained operation
and running terminals. Until identity is known, reobserve returns
`SUBMISSION_PENDING`; neither observer timeout nor transport timeout terminates a
detached agent.

Focus proves the actual native process, its executable/hash and ancestor chain,
then the exact hosting terminal PID/address and current compositor instance.
It makes no multiplexer pane claim. Resume supports native Claude and Codex CLI
UUID session identities with private native SessionStart evidence. Fixed commands
are `claude --resume SESSION_UUID` and `codex resume SESSION_UUID --cd CHECKOUT`,
launched through a supported saved terminal. Codex uses the exact registered
checkout, overriding any saved resume directory preference.
An observed terminal alone never proves a resumed native session. The owner
waits for fresh, proven same-session evidence in a new process epoch, otherwise
returns partial. Codex app/server processes and unsupported session IDs cannot
establish CLI ownership or enable reopening.

Workspace preparation delegates to `aranea.projects prepareWorkspace(json)`.
That narrow endpoint uses the existing allocation, association and focus queue
without requiring or launching an editor or generic terminal. Ordinary project
open retains its existing behavior and separate pending-request identity.

## Public commands

```text
aranea agents status|list [--json]
aranea agents inspect TASK_ID [--json]
aranea agents register --json-input [--json]
aranea agents report --json-input [--json]
aranea agents focus|reopen|open-checkout TASK_ID [--json]
aranea agents dismiss TASK_ID [--json]
aranea agents operation OPERATION_ID [--reobserve] [--json]
aranea agents adapter status|install|remove claude|codex [--json]
```

Read/report/register/dismiss work without a desktop. Public JSON uses schema-1
JSONL envelopes. Exit zero means observed; partial and ordinary errors use 1,
usage errors 2, missing tool selection 3 and missing dependencies 4.
`aranea capabilities --json` retains project schemas and adds activity schemas,
limits and adapter readiness. Adapter installation is explicit and opt-in.

Codex installation merges only this adapter's owned command into
`$CODEX_HOME/hooks.json` (default `~/.codex/hooks.json`). Removal preserves unrelated
handlers and matcher fields. Inline `config.toml` hooks, permissions and trust
settings remain untouched. Review and trust the current hook definition in Codex;
disabled hooks or managed-only policy can prevent execution. `configured` describes
the file, while `enabled` and `trusted` remain unconfirmed. Runtime observations
and current process proof are reported separately.

The Codex mapper uses `session_id` and stable `turn_id`; `agent_id` keeps children
separate from their parent. Stop means Ready for review, never verified success.
Interrupt adds a diagnostic and preserves unfinished state. Permission requests
lack a guaranteed correlation ID, so unrelated tool completion cannot clear them.
Native user-question coverage is unconfirmed; explicit structured reports cover
that gap, task completion, API failures and verification. The adapter does not
invent Claude-only Codex hooks and emits no decisions, text or added context.
See the official [Codex hooks](https://learn.chatgpt.com/docs/hooks) and
[CLI reference](https://learn.chatgpt.com/docs/cli/reference).

Manual reporting starts by explicitly registering a session epoch. This does
not register a project or checkout. Supply one bounded JSON object on stdin:

```json
{
  "provider": "claude",
  "providerSessionId": "manual-session",
  "producerEpoch": "manual-epoch-1",
  "tasks": []
}
```

Registration accepts the existing complete session snapshot fields. Provenance
must be absent or null; explicit producers cannot manufacture native evidence.
A new epoch requires the complete task snapshot and retires the previous epoch.
Then `report --json-input` accepts one strict schemaVersion-1 event with
`eventId`, `provider`, `providerSessionId`, `producerEpoch`, positive `sequence`,
`taskId`, `kind` and `payload`. A `snapshot` event creates a task and supplies
its exact `cwd` and `reportedState`. Association only resolves against already
registered exact checkouts. Unknown fields, multiple stdin values and oversized
input fail without resetting state. Manual reports cannot authorize native
session focus or verified resume.

Reported state and verification remain separate from connection freshness.
Heartbeat loss after 60 seconds never invents completion. Reported review,
failure and finished results remain historical. Store read errors retain the
last valid snapshot. `captureActive` refuses all external I/O.

## Setup and attention

Open Agents → Tasks; Usage stays available as the neighboring tab. Reporting is
local to this machine and opt-in. Register the exact checkout in Project settings
first. An event never registers a project automatically.

```sh
aranea agents adapter status claude
aranea agents adapter install claude
aranea agents adapter status codex
aranea agents adapter install codex
aranea agents status --json
```

Install only the provider you want. Review the provider's hook/trust settings,
then start a new native CLI session. `configured` only confirms owned hook entries;
`enabled` and `trusted` remain unconfirmed. `runtimeObserved` records actual hook
receipts; `connectionProven` additionally needs fresh native process evidence.
Missing providers and disabled/untrusted hooks can still use explicit reports.
Codex question-event coverage is unconfirmed; explicit reporting is the fallback.
No setup action changes provider approvals, permissions, TOML or trust policy.

Only Needs input, Ready for review and Failed transitions notify. The persistent
owner coalesces each task's burst for two seconds and deduplicates unchanged
state/blocker identities. DND, active quiet hours and unavailable policy consume
attention without replay when suppression ends. The first snapshot after an
owner restart is historical and silent. Normal-urgency notifications never
bypass DND. Native notification observers expire after at most 15 seconds.
`notifications.status` distinguishes suppressed, unavailable, accepted and
requested; native popup visibility is never claimed observed. Headless reports
update state without claiming notification delivery.

Clicking **Open task** rereads the exact task ID, then calls the existing Agents
panel's `showTask(taskId)` IPC endpoint. The panel waits for a fresh owner snapshot
before selecting that task's details. Missing tasks cannot select another row.
This performs inspection only; use the explicit task buttons to navigate or
reopen. Missing Agents widget/IPC leaves inspection unavailable: add Agents to
the bar, or use `aranea agents list` and `aranea agents inspect TASK_ID`.
`omarchy.agents taskInspection` returns the most recent lookup status; `selected`
means content selection, not observed native popup placement.

Verification is independently unknown, reported-pass or reported-fail. Stop or
ready-for-review does not imply tests passed. Focus needs fresh native identity,
process ancestry and a unique current terminal window; workspace, title and class
are insufficient. Focus reaches the hosting terminal, with no tmux/pane claim.
A partial accepted resume is never retried automatically, including owner loss.

## Explicit report example

Register a manual session once, then send ordered schema-1 events. Replace the
example directory with an existing checkout; project association requires prior
explicit project registration. Native process proof cannot be supplied manually.

```sh
printf '%s\n' '{"provider":"claude","providerSessionId":"manual-demo","producerEpoch":"demo-1","tasks":[]}' |
  aranea agents register --json-input
printf '%s\n' '{"schemaVersion":1,"eventId":"demo-1","provider":"claude","providerSessionId":"manual-demo","producerEpoch":"demo-1","sequence":1,"taskId":"demo-task","kind":"snapshot","payload":{"cwd":"/path/to/checkout","reportedState":"working","description":"Review navigation"}}' |
  aranea agents report --json-input
printf '%s\n' '{"schemaVersion":1,"eventId":"demo-2","provider":"claude","providerSessionId":"manual-demo","producerEpoch":"demo-1","sequence":2,"taskId":"demo-task","kind":"needs-input","payload":{"blockerId":"choice","question":"Which checkout should receive the change?"}}' |
  aranea agents report --json-input
```

Events require stable IDs and increasing sequence numbers within an epoch.
Duplicate exact events are idempotent; mismatched replay or malformed fields are
rejected. Reports are bounded display data, never executable commands. Heartbeats
run every 15 seconds; connection loss is projected after 60 seconds. Retention
keeps at most 500 inactive tasks for 14 days, with at most 200 live tasks and an
explicit capacity error rather than silent live eviction.

## Deployment and removal

The `keepLoaded` activity owner deploys with the theme independently of the Agents
bar entry. Theme release/return preserves activity state and running applications.
Both uninstall scopes remove owned activity state and exact proven heartbeat
helpers; provider processes, repositories and transcripts survive. Uninstall
removes only this installation's exact adapter commands using the same safe
removal transport. Unrelated hooks, permissions and Codex TOML remain intact.
Unsafe/malformed settings are preserved with explicit repair/removal guidance.
To opt out without uninstalling the theme:

```sh
aranea agents adapter remove claude
aranea agents adapter remove codex
```

## Inert production preview

`tools/render-agents-preview --fixture mixed --output /tmp/agents.png` renders the
actual production Tasks/navigation/details components in an offscreen host.
Fixtures: `empty`, `working`, `needs-input`, `review`, `failed`, `lost`, `finished`,
`long`, `mixed`, `partial`, `pending`. Set `ARANEA_AGENTS_RENDER_DETAILS=1` for
first-task details, `ARANEA_AGENTS_RENDER_WIDTH=420` for narrow content, and
`ARANEA_AGENTS_RENDER_FONT_SCALE=1.5` for large fonts. Height is configurable with
`ARANEA_AGENTS_RENDER_HEIGHT`; partial/pending show details by default.

The renderer isolates HOME/XDG/state/theme paths, replaces absolute theme helper
paths and PATH commands with execution traps, and checks for state/settings
writes. It constructs no activity runtime, clients, collectors or provider.
Captures cannot validate native popup placement, actual desktop notifications,
provider trust or multiplexer focus; those remain separate host checks.
