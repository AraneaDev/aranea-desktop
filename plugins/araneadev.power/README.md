# Aranea Battery / System

`araneadev.power` replaces Omarchy's `omarchy.power` bar dropdown with an
Aranea-native one. `Panel.qml` keeps stock's root logic (battery and power
profile polling every 5 s while open, the profile picker, the rotating hero
status phrases, the `showPercentage` setting and IPC) with `Model.js`
verbatim, and drops stock's system stats line (Aranea Health shows it).

The battery control now owns one popup with **Power**, **Display**, and
**Health** pages. Power opens by default; `P`, `D`, and `S` (Health) switch pages.
Display reuses the existing brightness, night light, keyboard light, scaling,
and display controls. Health keeps expanded resource details and the existing
guided issue resolution actions. Its service counts only the selected open
Health page for resource sampling. The Health tab shows the current issue count.
A system glyph keeps these controls reachable on machines without a battery.

The Display controller still owns `omarchy.monitor` IPC; its open/toggle routes
select the Display page while embedded. Optional Display and Health plugins
load by URL, so Power remains usable when
either plugin is absent. Display and Health retain standalone
widget support, with the embedded mode suppressing their own bar icons and
popup windows. Closing an embedded page closes the shared System popup.

The Power view, `PowerDropdown.qml` (with `PowerHero.qml`, `PowerHistory.qml` and
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
`omarchy-shell omarchy.power showPage power|display|health` selects an available
page and returns `ok`, `invalid`, or `unavailable`; capture uses this route for
Display and Health.

## Validation

Run `node --test tests/js/power-logic.test.js`, the view test
`tests/qml/power-dropdown.qml`, `tests/qml/system-embedded.qml` (through
`tools/check`), `bash tests/system-optional.test.sh`, and `tools/check-docs
--root . plugins/araneadev.power/Panel.qml`.
