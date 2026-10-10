# Aranea Agents

`araneadev.agents` replaces Omarchy's `omarchy.agents` bar entry (the Claude Code, Codex and
Fireworks usage dashboard) with an Aranea-native one.

`Panel.qml` keeps stock's root logic (Main's discovery and watching, the provider selection that
follows the provider id, the limit-window and balance normalisation, the day and model rows, the
30 s clock, the IPC target `omarchy.agents` with `open`/`close`/`show`/`hide`/`toggle`/`refresh`/
`next`, self-hiding when no agent has usage, sync, and the bar entry's settings handed to Main)
and draws it with the pure `AgentsDropdown` view inside the shared `KeyboardPanelFrame`.
`Main.qml` (agent discovery, watching and cross-device sync) and `Agent.qml` (the per-agent usage
record watcher) are stock, unchanged apart from docs and qmllint scoping.

The bar button keeps its glyph, clicks and alarm state, with `AgentsRing` drawn over the glyph
slot: it fills with the current agent's fullest limit window, in the accent below 80%, amber from
80% and urgent from 95%, and is absent for an agent without limits.

Refresh: `r`, Enter on Refresh, the header's Refresh pill and IPC `refresh` share one path. The pill reads
"Refreshing…" and pulses until every shown agent's record has been rewritten since the request
(`AgentsLogic.recordsLandedSince`, then Main's data revision lands it through `refreshLanded`) or
30 s pass; requests while it is pending are ignored. A forced run that stock queued behind a
run already going (any open starts a limits run) is waited for: that run's writes do not land it,
and the queued run's start rebases the landing time (`refreshRebase`); the 30 s still count from
the request. A shown agent whose collector fails writes nothing, so the pill pulses the full 30 s.

Settings form: the manifest keeps stock's `defaults`, `schema` and `aliases` in the `barWidget`
block, unlike Weather's named `settingsForm` string. The shell resolves a widget's settings
(defaults and schema) from its own manifest (keyed by its own plugin id, via
`BarWidgetRegistry.register`/`metadataFor` in `syncPluginWidgets`), not from `clonedFrom`, so
`araneadev.agents` registers its own `refreshIntervalSec`/`syncMode`/`syncDir`/`syncFileName`/
`syncDeviceId` schema entries independently of `omarchy.agents`; there is no named form to look
up (as there is for Weather), so no further fix was needed for settings-form parity.

The dropdown opens with every limit window (percentage, reset time and pace tick) and prepaid
balance visible. Usage history and Models start collapsed. Their headings indicate expansion;
click or Enter requests a host-owned toggle. Closing or changing providers resets both details,
while a refresh of the same provider preserves them. Primary state remains above the detail
viewport; unusually long errors or limit lists get a separate capped scrolling fallback.

Keys: left/right (or `h`/`l`) switch the selected agent; up/down move between Refresh and the
available detail headings; Enter or Space activates the focused target. `r`/`R` refreshes at once,
Esc closes and Tab moves to the bar's next dropdown. After opening or a pointer click, the first
navigation key or Enter only reveals the cursor. Focus follows stable keys and scrolls headings
into view; a removed target cannot activate its replacement. Hover only draws a fill and never
hides the outline. Expansion, scrolling and real re-sorts stamp layout changes so stale pointer
clicks settle for 300 ms. The font family and external mint/violet frame remain host-controlled.

The pure rules live in `AgentsLogic.js` (ring fraction/tone, row keys, refresh-pending state and its landing gate, the
"updated HH:MM" caption; tested under Node). `Panel.qml` builds `agentsView` from stock's own
limit/balance/day/model functions and adds the limits' pace tick (the elapsed share of each
window's span) and the mark probe that walks stock's light-twin fallback for the header.

- **`showcase` IPC:** for README captures (`scripts/capture-screenshots --surface agents`),
  stand-in agents replace the real ones: `{"agents": [{id, name, plan, updatedMinutesAgo,
todayPrompts, todaySessions, limits: [{label, percent, resetsInMinutes}], days: [...counts,
oldest first, today last], models: [{id, input, output, cacheRead, cacheWrite}], balance?:
{remaining, funded, spent, currency}}]}` (`AgentsLogic.parseShowcase`, which refuses anything
  malformed). The first stand-in is selected. Display only: no collector runs, the sync footer
  hides, IPC `refresh` answers `refused` and the Refresh pill, `r`, Enter on Refresh and the right-click
  agent picker do nothing while it is shown, and it clears when the dropdown opens or closes.
  Closed, the call answers `closed`; a bad payload, `invalid`. The stand-in choice of agent is
  kept apart from the real one (`AgentsLogic.selectId`), so a capture never changes which agent
  the user had selected, and a refresh pending when it starts is dropped.

  ```bash
  omarchy-shell omarchy.agents showcase ' {"agents":[{"id":"claude","name":"Claude Code","plan":"Pro","updatedMinutesAgo":3,"todayPrompts":46,"todaySessions":5,"limits":[{"label":"Session (5-hour)","percent":0.42,"resetsInMinutes":134}],"days":[182400000,128300000],"models":[{"id":"claude-sonnet-5","input":4200000,"output":9800000,"cacheRead":1186000000,"cacheWrite":52000000}]}]}'
  ```

## View

`AgentsDropdown.qml` is the pure Aranea view: one plain view
object in (`hero`, `refresh`, `agents`, `limits`, `balance`, `days`, `models`, `footer`, `empty`,
`details` (`historyExpanded`, `modelsExpanded`), `cursor`, `keyHint`), one `action(name, arg)` signal out (`refresh`, `selectAgent` with
`{index, key}`, `toggleDetails` with `{section: "history" | "models"}`, `hover` with `{section, index}`). Its sections are `AgentsHeader.qml` (mark,
tool, plan and the Refresh pill), `AgentsSwitch.qml` (agent pills), `AgentsBalanceSection.qml`,
`AgentsLimitsSection.qml` and `AgentsUsageSection.qml` (days and models). `AgentsRing.qml` is
the bar ring: a canvas arc taking `fraction` and `tone` from `AgentsLogic.js`, hidden at tone
`none`. `tests/qml/agents-dropdown.qml` covers both.

## Integration

- `scripts/repair-shell-config` retargets `omarchy.agents` to `araneadev.agents` in
  `bar.layout` (any section), once `araneadev.agents/manifest.json` is deployed beside
  `shell.json`; it keeps the entry's settings (`providers`, `refreshIntervalSec`, `sync*`) and
  records `araneadev.agents` in `cloneSourceRestores`. Agents has no `bar.centerAnchor`
  handling: that anchor is the clock. Agents is a bar-widget clone like Weather, Tray, Audio,
  Bluetooth, Clock, Monitor, Network and Power: its enablement lives entirely in
  `bar.layout` (the entry's presence there, and absence from `disabledPlugins`), never in the
  `plugins`/`disabledPlugins` arrays that the always-on chrome clones (notifications, health,
  clipboard, emojis, polkit, lock, osd, menu, workspaces, updates) use; `omarchy plugin enable`
  re-adds the bar entry, which this retarget then picks up the same as a user-authored one.
- `scripts/release-shell-config` reverses the retarget.
- `scripts/deploy-plugins-safely` deploys the plugin directory.

## Validation

Run `tests/shell-config.test.sh`, `tests/shell-deploy.test.sh` and `tools/check-docs --root .
plugins/araneadev.agents/Panel.qml plugins/araneadev.agents/Main.qml
plugins/araneadev.agents/Agent.qml`.

## Local Tasks

Tasks sits alongside Usage and stays visible for task-only activity. Attention
selects Tasks initially; your deliberate tab choice is retained. Arrow/j/k moves
the task cursor, Enter opens details, Tab changes Tasks/Usage, and Escape returns
from details before closing. Task selection follows stable IDs across sorting.

Empty Tasks provides copyable Claude/Codex opt-in commands and Project settings.
Configured hooks are separate from provider trust and observed runtime activity.
Verification is a separate reported fact; Ready for review does not mean tests
passed. Native focus targets a proven hosting terminal, without a tmux pane claim.
See [Activity setup and contract](../araneadev.activity/README.md).

The activity owner survives bar/panel closure. Notification activation calls
`omarchy.agents showTask TASK_ID`: inspection waits for a fresh owner snapshot,
selects only the exact retained task, and never automatically resumes or answers.
`taskInspection` exposes pending/selected/unavailable lookup status. Capture and
Usage showcase modes refuse this route. A missing bar widget leaves the panel
unavailable while CLI activity reporting and the persistent owner continue.

Use `tools/render-agents-preview` for isolated screenshots of the actual Tasks
components. This offscreen route includes empty, attention, result, lost and
partial-operation fixtures, with narrow/large-font variants. The existing Usage
showcase remains separate; no mock Tasks design or live activity is introduced.
