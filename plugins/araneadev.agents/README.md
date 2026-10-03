# Aranea Agents

`araneadev.agents` replaces Omarchy's `omarchy.agents` bar entry (the Claude Code, Codex and
Fireworks usage dashboard) with an Aranea-native one.

`Panel.qml` keeps stock's root logic (the provider switch, the limit-window and balance
normalisation, the day and model rows, the IPC methods, the `hostWidget` / `barIdentity` owner
contract, and open / close / toggle) and draws it with stock's markup inside the shared
`KeyboardPanel`. `Main.qml` (agent discovery, watching and cross-device sync) and `Agent.qml`
(the per-agent usage record watcher) are stock, unchanged apart from docs.

`Panel.qml` runs as `omarchy.agents` for now: this is the Task 2 clone, so the stock root logic,
markup and IPC target are unchanged from Omarchy's Agents and the bar entry keeps working
identically until the Aranea-native dropdown view lands in a later task.
`omarchy-shell shell summon omarchy.agents` (and `hide`, `toggle`, `refresh`, `next`) keep
working unchanged.

Settings form: the manifest keeps stock's `defaults`, `schema` and `aliases` in the `barWidget`
block, unlike Weather's named `settingsForm` string. The shell resolves a widget's settings
(defaults and schema) from its own manifest (keyed by its own plugin id, via
`BarWidgetRegistry.register`/`metadataFor` in `syncPluginWidgets`), not from `clonedFrom`, so
`araneadev.agents` registers its own `refreshIntervalSec`/`syncMode`/`syncDir`/`syncFileName`/
`syncDeviceId` schema entries independently of `omarchy.agents`; there is no named form to look
up (as there is for Weather), so no further fix was needed for settings-form parity.

Keys: left/right (or `h`/`l`) switch the selected provider, up/down scroll the panel, Enter (or
`r`/`R`) forces a refresh, and Esc closes. Tab moves to the bar's next dropdown.

The pure rules live in `AgentsLogic.js` (ring fraction/tone, row keys, refresh-pending state;
tested under Node). `Main.qml`'s discovery and sync logic, and `Panel.qml`'s limit/balance/day/
model formatting, stay stock's own functions for this clone.

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
