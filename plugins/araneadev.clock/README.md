# Aranea Clock

`araneadev.clock` replaces Omarchy's `omarchy.clock` bar entry (the date/time label and its
calendar popup) with an Aranea-native one.

This is the Task 2 clone: `BarWidget.qml`, `Panel.qml` and `Model.js` are copied from stock
verbatim apart from docs comments, so the bar label, the calendar popup, its keyboard handling
and its settings (`format`, `formatAlt`, `verticalFormat`, `verticalFormatAlt`, `weekStartDay`,
`birthYear`, `lifeExpectancy`) all behave exactly as they do in stock Clock. `BarWidget.qml`
keeps stock's `moduleName`/`ipcTarget`/IPC target of `"omarchy.clock"`, so
`omarchy-shell shell summon omarchy.clock` (and `hide`/`toggle`/`refresh`/`cycleFormat`/
`toggleWeekStart`) keep working unchanged.

`ClockLogic.js` (added in Task 1) holds the pure sun/moon/location math for the sun & moon
section that a later task wires into the view; it is not yet used by `Panel.qml`.

The Aranea-native dropdown view (`Aranea.KeyboardPanelFrame` hosting a pure `ClockDropdown`,
plus the sun & moon section) replaces `Panel.qml`'s markup in a later task, which also removes
this task's temporary qmllint allowance.

## Integration

- `scripts/repair-shell-config` retargets `omarchy.clock` to `araneadev.clock` in `bar.layout`
  (any section) and in `bar.centerAnchor`, once `araneadev.clock/manifest.json` is deployed
  beside `shell.json`; it keeps the entry's settings and records `araneadev.clock` in
  `cloneSourceRestores`.
- `scripts/release-shell-config` reverses both retargets.
- `scripts/deploy-plugins-safely` deploys the plugin directory.

## Validation

Run `node --test tests/js/clock-logic.test.js`, `tests/shell-config.test.sh`,
`tests/shell-deploy.test.sh` and `tools/check-docs --root . plugins/araneadev.clock/BarWidget.qml
plugins/araneadev.clock/Panel.qml`.
