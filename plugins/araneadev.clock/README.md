# Aranea Clock

`araneadev.clock` replaces Omarchy's `omarchy.clock` bar entry (the date/time label and its
calendar popup) with an Aranea-native one.

`BarWidget.qml` keeps stock's label, format ring and IPC. `Panel.qml` keeps stock's root
logic (month and year stepping, Back to today, the week start setting, the Memento Mori edit,
`persistSettings`, the SystemClock rollover, the `hostWidget` / `barIdentity` owner contract,
`centerOnBar` and open / close / toggle) and draws it with `ClockDropdown` inside the shared
`KeyboardPanelFrame`. The settings (`format`, `formatAlt`, `verticalFormat`,
`verticalFormatAlt`, `weekStartDay`, `birthYear`, `lifeExpectancy`) are stock's.

`BarWidget.qml` runs as `araneadev.clock`: the bar sets its `moduleName` to the entry's id, and
every settings write (the format cycle, the week start and the life bar) goes under that id,
since the plugin shell refuses any other. Only `Panel.qml`'s `moduleName` and `ipcTarget`, and
the IPC target, stay `"omarchy.clock"`, so `omarchy-shell shell summon omarchy.clock` (and
`hide`, `toggle`, `refresh`, `cycleFormat`, `toggleWeekStart`) keep working unchanged.

Keys: left / right or `[` / `]` step the month, up / down or `{` / `}` the year, Enter or `t`
go back to today, `w` switches the week start, Esc closes, and Tab moves to the bar's next
dropdown. The calendar is a read-out with no cursor.

Added to stock:

- **Sun & moon:** today's sunrise, sunset and daylight with a small sun arc (its dot moves
  once a minute while open), and the moon's phase and illumination. The sun is computed
  locally (`ClockLogic.sunTimes`) for the weather location in
  `~/.local/state/omarchy/settings/weather.json` when it has coordinates. Otherwise it uses
  the place `https://wttr.in/?format=j1` resolves. The lookup runs at most once per day, on
  the first open, and never while closed. Each monitor's bar hosts its own clock, and they
  share that one lookup: an instance takes today's place from another before fetching. A
  failed lookup, or one cancelled by closing the dropdown, retries on the next open; there is
  no retry loop. Without a place only the moon shows, and after sunset the section reads
  "Night".
- **`showcase` IPC:** replaces the place and its coordinates for README captures. It is
  display only, taken only while the dropdown is open, and cleared on open and on close. The
  instance the IPC target lands on hands it to whichever monitor's dropdown is open. The
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
