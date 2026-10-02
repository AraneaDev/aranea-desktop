# Aranea Clock

`araneadev.clock` replaces Omarchy's `omarchy.clock` bar entry (the date/time label and its
calendar popup) with an Aranea-native one.

`BarWidget.qml` keeps stock's label, format ring and IPC. `Panel.qml` keeps stock's root
logic (month and year stepping, Back to today, the week start setting, the Memento Mori edit,
`persistSettings`, the SystemClock rollover, the `hostWidget` / `barIdentity` owner contract,
`centerOnBar` and open / close / toggle) and draws it with `ClockDropdown` inside the shared
`KeyboardPanelFrame`. The settings (`format`, `formatAlt`, `verticalFormat`,
`verticalFormatAlt`, `weekStartDay`, `birthYear`, `lifeExpectancy`) are stock's.

`moduleName`, `ipcTarget` and the IPC target stay `"omarchy.clock"`, so
`omarchy-shell shell summon omarchy.clock` (and `hide`, `toggle`, `refresh`, `cycleFormat`,
`toggleWeekStart`) keep working unchanged.

Keys: left / right step the month, up / down the year, Enter or `t` go back to today, Esc
closes, and Tab moves to the bar's next dropdown. The calendar is a read-out with no cursor.

Added to stock:

- **Sun & moon:** today's sunrise, sunset and daylight with a small sun arc (its dot moves
  once a minute while open), and the moon's phase and illumination. The sun is computed
  locally (`ClockLogic.sunTimes`) for the weather location in
  `~/.local/state/omarchy/settings/weather.json` when it has coordinates. Otherwise it uses
  the place `https://wttr.in/?format=j1` resolves: one lookup a day, only on open, never
  while closed and stopped on close; a failed lookup tries again on the next open. Without a
  place only the moon shows.
- **`showcase` IPC:** replaces the place and its coordinates for README captures. It is
  display only, taken only while the dropdown is open, and cleared on open and on close. The
  leading space keeps qs from splitting the argument:

  ```sh
  omarchy-shell omarchy.clock showcase ' {"name":"Amsterdam","latitude":52.37,"longitude":4.90}'
  ```

The pure rules live in `ClockLogic.js` and `Model.js` (stock, verbatim apart from docs).

## Integration

- `scripts/repair-shell-config` retargets `omarchy.clock` to `araneadev.clock` in `bar.layout`
  (any section) and in `bar.centerAnchor`, once `araneadev.clock/manifest.json` is deployed
  beside `shell.json`; it keeps the entry's settings and records `araneadev.clock` in
  `cloneSourceRestores`.
- `scripts/release-shell-config` reverses both retargets.
- `scripts/deploy-plugins-safely` deploys the plugin directory.

## Validation

Run `node --test tests/js/clock-logic.test.js`, `tests/qml-behaviour.test.sh clock-dropdown`,
`tests/shell-config.test.sh`, `tests/shell-deploy.test.sh` and `tools/check-docs --root .
plugins/araneadev.clock/BarWidget.qml plugins/araneadev.clock/Panel.qml`.
