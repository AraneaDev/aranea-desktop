# Aranea Power

`araneadev.power` replaces Omarchy's `omarchy.power` bar dropdown with an
Aranea-native one. `Panel.qml` keeps stock's root logic (battery and power
profile polling every 5 s while open, the profile picker, the rotating hero
status phrases, the `showPercentage` setting and IPC) with `Model.js`
verbatim, and drops stock's system stats line (Aranea Health shows it).

The view, `PowerDropdown.qml` (with `PowerHero.qml`, `PowerHistory.qml` and
`PowerDraw.qml`), draws it in the shared keyboard frame:

- the hero: a drawn battery cell, the status line and the big percentage;
- the details grid (time, rate, size, cycles; stock's rules);
- CHARGE: the last 24 h from UPower's `GetHistory` over `busctl`, read on
  open and every 60 s while open, with breaks over gaps longer than 30 min;
- POWER DRAW: UPower's `EnergyRate`, sampled every 1.5 s while open (40
  samples, cleared on close), shown while current flows;
- POWER PROFILE: the profile pills, keyed by profile name.

Nothing polls while the dropdown is closed; the bar glyph comes from
Quickshell's UPower service. The cursor outline shows only during keyboard
navigation: the first key (Enter included) only reveals it, on the active
profile, and Enter then applies the outlined profile, only while it is
still the one shown there. Hover only draws a pill's fill; the active
profile's pill carries the selected highlight.

`Panel.qml` keeps stock's `manageIpc: false` and owns the `omarchy.power`
IpcHandler itself, so `omarchy-shell shell summon omarchy.power` still opens
it, and `togglePercentage` (right-click the bar icon) keeps working.

## Validation

Run `node --test tests/js/power-logic.test.js`, the view test
`tests/qml/power-dropdown.qml` (through `tools/check`) and `tools/check-docs
--root . plugins/araneadev.power/Panel.qml`.
