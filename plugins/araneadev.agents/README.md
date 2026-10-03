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

Refresh: `r`, Enter, the header's Refresh pill and IPC `refresh` share one path. The pill reads
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

Keys: left/right (or `h`/`l`) switch the selected agent, up/down scroll the panel, Enter or
`r`/`R` refresh, Esc closes and Tab moves to the bar's next dropdown. The keyboard outline shows
only while the keyboard drives it: after opening or any pointer use, the first navigation key or
Enter only reveals it (on the selected agent pill, or on the Refresh pill with one agent); `r`
refreshes at once.

The pure rules live in `AgentsLogic.js` (ring fraction/tone, row keys, refresh-pending state and its landing gate, the
"updated HH:MM" caption; tested under Node). `Panel.qml` builds `agentsView` from stock's own
limit/balance/day/model functions and adds the limits' pace tick (the elapsed share of each
window's span) and the mark probe that walks stock's light-twin fallback for the header.

## View

`AgentsDropdown.qml` is the pure Aranea view: one plain view
object in (`hero`, `refresh`, `agents`, `limits`, `balance`, `days`, `models`, `footer`, `empty`,
`cursor`, `keyHint`), one `action(name, arg)` signal out (`refresh`, `selectAgent` with
`{index, key}`, `hover` with `{section, index}`). Its sections are `AgentsHeader.qml` (mark,
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
