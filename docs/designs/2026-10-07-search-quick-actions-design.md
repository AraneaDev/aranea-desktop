# Search clarity and quick actions

Date: 2026-10-07

Status: Chat design approved; written specification awaiting review.

## Purpose

Make the command center faster to scan and useful for frequent desktop actions.
Keep Aranea's quiet obsidian surfaces, mint activity, violet identity, Inter UI
text, and JetBrains Mono technical text. This is the first stage of the approved
search and whole-desktop refinement direction.

## Scope and sequence

First refine the existing mixed search results. Then add three action families:
Do not disturb, audio output selection, and wallpaper selection. Preserve apps,
commands, windows, workspaces, settings, scoped submenu search, and dmenu input.
VPN actions are a future feature because authentication and 2FA require a
separate design. Bar customization and desktop modes are outside this stage.

## Search presentation

Keep one ranked result list; do not split results into independently navigated
groups. Every result uses a consistent icon column, prominent name, quieter
description, and restrained trailing type label. Use app icons when available
and dedicated type glyphs as fallbacks. Labels continue to identify types even
when an icon or color cannot be distinguished.

Use neutral pointer hover and a crisp mint keyboard selection outline. Maintain
the menu's existing pointer and keyboard activation rules. Titles and context
must elide within their columns rather than pushing type labels outside the
viewport. Retain the adaptive result viewport and existing refinement hint.

Keep canonical keys across refreshes. Query changes select the highest-ranked
result as today; source refreshes retain its identity. If that identity vanishes,
clear selection instead of substituting a different target under Enter.

## Action behavior

Add an Action result type and the optional `action:` query prefix. Existing
prefixes keep their meaning. Action labels, aliases, and descriptions use the
existing matcher and relevance ordering; actions receive no blanket ranking
boost over exact app or window matches. Current state belongs in result context.

| Family    | Search examples                          | Results and activation                                                                                                                                  |
| --------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DND       | `dnd`, `do not disturb`, `notifications` | One stable result offering Enable or Disable according to the manual preference. Show quiet hours separately when effective suppression remains active. |
| Audio     | `audio`, `output`, a device name         | One result per currently available output, marked Current when confirmed. Enter requests that exact output.                                             |
| Wallpaper | `wallpaper`, a manifest name             | One result per installed manifest wallpaper, marked Current when active. Enter applies that manifest ID.                                                |

Activating an already-current audio output or wallpaper is a no-op. Wallpaper
selection follows the existing manual selection behavior and leaves schedule
configuration intact. Its context indicates that an enabled schedule can later
change the wallpaper. DND changes the manual preference without changing quiet
hours. Do not duplicate existing settings or panel destinations as action rows.

## Feedback and lifecycle

An action keeps the menu open. Its row shows Pending, then confirmed state or a
failure message. Changing query or closing the menu does not cancel a submitted
operation; lifecycle ownership stays with the relevant service. Reopening reads
the actual state, and an old completion cannot overwrite a newer request.

For each family allow one pending request and reject further activation until
it settles. This deliberately keeps search simpler than the audio panel's
existing queued device interactions. Other result families remain usable.

Use the existing three-second DND and four-second audio confirmation windows.
A timeout clears Pending and shows observed state plus a retryable error.
Wallpaper uses a tracked process with a fifteen-second confirmation deadline;
success requires successful command completion and matching active wallpaper
state. A late state update may refresh Current but must not revive an obsolete
request's feedback. The menu must never label detached dispatch as success.

Failures remain visible while the result remains in the query. Retry is Enter
on the same valid target. Offer Open audio controls or Open Appearance as an
explicit recovery destination when appropriate. Missing capabilities omit
their action records; existing control and settings destinations remain.

## Architecture and ownership

Extend `DesktopSearchRanking.js` with the Action type and prefix. Keep the
generated `DesktopSearchLogic.js` facade generated. `DesktopSearchTargets.js`
adapts action snapshots into typed records with stable keys; names and queries
remain display data, never executable text.

Add a local action controller consumed by `DesktopSearchSources.qml` and the
menu host. It owns action snapshots, request identities, and feedback
projection. Pure normalization and transition rules live in focused JS modules.
The host still owns query, cursor, ranking, and menu lifecycle.

Notifications remain authoritative for DND. Audio's owning plugin must expose
a narrow snapshot/request boundary using its existing node identity validation,
PipeWire updates, and request logic; the menu must not copy that state machine
or maintain a competing default-output controller. Extend that owner boundary
to report confirmed outcomes to search without changing existing panel queuing.

Wallpaper operations use `scripts/aranea-wallpaper` with argument arrays and
manifest IDs. Resolve IDs and current installation state immediately before
execution. Snapshot reads and outcome delivery must work while dropdowns are
closed. Where plugin lifetime currently prevents this, move only the required
state into its owning service; do not move service ownership into shared QML.

Refresh runtime sources only while search is active, using event subscriptions
and coalescing. Pending operations may finish outside that subscription window.
Activation always re-resolves the selected key against fresh authoritative
state, including device identity, availability, and current DND preference.

## Validation and acceptance

- JS checks cover Action normalization, prefixes, mixed relevance, stable keys,
  unavailable capabilities, and pending/confirmed/failed transitions.
- QML checks cover selection across refresh, device removal before Enter,
  repeated activation, stale completions, and close/reopen during an operation.
- Verify DND during quiet hours, audio confirmation/timeout, and wallpaper
  command failure and active-state confirmation with replaceable boundaries.
- Use inert fixtures for rendered comparisons of mixed results, each action
  family, pending states, errors, long labels, and empty results.
- Check keyboard and pointer navigation, small logical screens, larger font
  choices, scale changes, and reduced motion. Capture fixtures cannot execute
  real system actions.
- Run generator drift checks, relevant JS/QML suites, and `tools/check` before
  declaring implementation complete. Update menu and feature documentation.

Acceptance means all three families execute from search with current-state
context and observed outcomes, existing search contracts remain intact, and
rendered results remain readable at the supported sizes.
