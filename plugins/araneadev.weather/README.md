# Aranea Weather

`araneadev.weather` replaces Omarchy's `omarchy.weather` bar entry (the weather pill and its
detail popup) with an Aranea-native one.

`BarWidget.qml` keeps stock's pill, click handling and popup host. `Panel.qml` keeps stock's
root logic (the wttr.in and open-meteo fetches, the refresh timer and retry schedule, the
click-to-edit location flow with debounced geocoding suggestions, `omarchy-weather-location`
persistence, the `hostWidget` / `barIdentity` owner contract, `centerOnBar` and open / close /
toggle) and draws it with `WeatherDropdown` inside the shared `KeyboardPanelFrame`. The
settings (`unit`, `refreshMinutes`) are stock's, and only read: the dropdown writes no
settings.

Only `Panel.qml`'s `moduleName` and `ipcTarget`, and the IPC target, stay `"omarchy.weather"`,
so `omarchy-shell shell summon omarchy.weather` (and `hide`, `toggle`, `edit`) keep working
unchanged. The bar sets `BarWidget.qml`'s `moduleName` to the entry's id, which the instances
use to find each other.

Settings form: the manifest keeps stock's `settingsForm: "weatherSettings"` in the `barWidget`
block. The shell resolves a widget's settings form from its own manifest (keyed by its own
plugin id, via `BarWidgetRegistry.metadataFor`), not from `clonedFrom`, so `araneadev.weather`
registers its own `weatherSettings` entry the same way `omarchy.weather` would.

Keys: up / down / left / right walk the place and "updated" labels. The first key, Enter
included, only shows the cursor (on the place label after opening); then Enter acts on the
outlined label (edit the place, or refresh). `e` edits the place, `r` refreshes, Esc closes and
Tab moves to the bar's next dropdown. Hover only draws a label's tint and never moves the cursor.
In the place field, typing looks places up, up / down move the highlighted suggestion (outlined
from the start, as Enter's target; hover never moves it), Enter saves it (or the typed name; an
empty field goes back to automatic) and Esc cancels.

Added to stock, all from open-meteo on the same refresh:

- **Rain soon:** one line from the 15-minute precipitation of the next 3 hours.
- **Details:** feels, humidity, wind with a direction arrow and compass label, gusts, pressure
  with its 3-hour trend, and visibility, in the active units.
- **Next 24 h:** a temperature trace over rain-chance bars, with "now → min → max".
- **Air & UV:** the European AQI and the UV index as chips, from one extra air-quality request
  per refresh. A failed request hides the chips.
- **Four days:** today and the next three.
- **One fetch for every monitor:** each monitor's bar hosts its own instance. An automatic
  refresh (the timer, an open, a location change) adopts a report any instance fetched in
  the last `refreshMinutes` minus one minute, waits while another instance is fetching, and
  only otherwise fetches; each fetch is handed to the other instances as it lands. Clicking
  "updated", `r` and the pill's middle click always fetch.
- **Pending place:** a saved or cleared place shows at once and pulses until
  `omarchy-weather-location` exits; the file is then read back.

Without configured coordinates, the open-meteo and air requests use the coordinates wttr.in
reports for the automatic place.

The pure rules live in `Model.js` (stock, verbatim apart from docs) and `WeatherLogic.js`
(tested under Node).

## Integration

- `scripts/repair-shell-config` retargets `omarchy.weather` to `araneadev.weather` in
  `bar.layout` (any section), once `araneadev.weather/manifest.json` is deployed beside
  `shell.json`; it keeps the entry's settings and records `araneadev.weather` in
  `cloneSourceRestores`. Weather has no `bar.centerAnchor` handling: that anchor is the clock.
- `scripts/release-shell-config` reverses the retarget.
- `scripts/deploy-plugins-safely` deploys the plugin directory.

## Validation

Run `node --test tests/js/weather-logic.test.js`, `tests/qml-behaviour.test.sh
weather-dropdown`, `tests/shell-config.test.sh`, `tests/shell-deploy.test.sh` and
`tools/check-docs --root . plugins/araneadev.weather/BarWidget.qml
plugins/araneadev.weather/Panel.qml`.
