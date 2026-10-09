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

Focus proves the actual native process, its executable/hash and ancestor chain,
then the exact hosting terminal PID/address and current compositor instance.
It makes no multiplexer pane claim. Resume supports native Claude UUID session
identities with private native SessionStart evidence. The fixed command is
`claude --resume SESSION_UUID`, launched through a supported saved terminal.
An observed terminal alone never proves a resumed native session. The owner
waits for fresh, proven same-session evidence in a new process epoch, otherwise
returns partial. Codex resume and native mapping remain unavailable here.

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
aranea agents adapter status|install|remove claude [--json]
```

Read/report/register/dismiss work without a desktop. Public JSON uses schema-1
JSONL envelopes. Exit zero means observed; partial and ordinary errors use 1,
usage errors 2, missing tool selection 3 and missing dependencies 4.
`aranea capabilities --json` retains project schemas and adds activity schemas,
limits and adapter readiness. Adapter installation is explicit and opt-in.

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
