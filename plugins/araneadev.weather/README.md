# Aranea Weather

`araneadev.weather` replaces Omarchy's `omarchy.weather` bar entry (the weather pill and its
detail popup) with an Aranea-native one.

`BarWidget.qml` keeps stock's pill, click handling and popup host. `Panel.qml` keeps stock's
root logic (the wttr.in and open-meteo fetches, the refresh timer and retry schedule, the
click-to-edit location flow with debounced geocoding suggestions, `omarchy-weather-location`
persistence, the `hostWidget` / `barIdentity` owner contract, `centerOnBar` and open / close /
toggle) and draws it with stock's markup inside the shared `KeyboardPanel`. The settings
(`unit`, `refreshMinutes`) are stock's.

`BarWidget.qml` and `Panel.qml` run as `omarchy.weather` for now: this is the Task 2 clone, so
the stock root logic, markup and IPC target are unchanged from Omarchy's Weather and the bar
entry keeps working identically until the Aranea-native dropdown view lands in a later task.
`omarchy-shell shell summon omarchy.weather` (and `hide`, `toggle`, `refresh`, `edit`) keep
working unchanged.

Settings form: the manifest keeps stock's `settingsForm: "weatherSettings"` in the `barWidget`
block. The shell resolves a widget's settings form from its own manifest (keyed by its own
plugin id, via `BarWidgetRegistry.metadataFor`), not from `clonedFrom`, so `araneadev.weather`
registers its own `weatherSettings` entry the same way `omarchy.weather` would; no fix was
needed for settings-form parity.

Keys: Enter opens the location editor, Esc closes (or cancels an edit in progress), and Tab
moves to the bar's next dropdown. Up/down and typing in the location field walk and filter the
geocoding suggestions; the field's own Enter and Escape commit or cancel the edit.

The pure rules live in `Model.js` (stock, verbatim apart from docs) and `WeatherLogic.js` (the
new open-meteo extras added in Task 1, tested under Node).

## Integration

- `scripts/repair-shell-config` retargets `omarchy.weather` to `araneadev.weather` in
  `bar.layout` (any section), once `araneadev.weather/manifest.json` is deployed beside
  `shell.json`; it keeps the entry's settings and records `araneadev.weather` in
  `cloneSourceRestores`. Weather has no `bar.centerAnchor` handling: that anchor is the clock.
- `scripts/release-shell-config` reverses the retarget.
- `scripts/deploy-plugins-safely` deploys the plugin directory.

## Validation

Run `tests/shell-config.test.sh`, `tests/shell-deploy.test.sh` and `tools/check-docs --root .
plugins/araneadev.weather/BarWidget.qml plugins/araneadev.weather/Panel.qml`.
