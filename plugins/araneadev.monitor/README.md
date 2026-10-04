# Aranea Display

`araneadev.monitor` replaces Omarchy's `omarchy.monitor` bar dropdown with an
Aranea-native one. `Panel.qml` keeps stock's root logic (the
`omarchy-monitor-state` poll, the debounced and queued brightness setter, the
display toggle with its last-display guard, scale, text size with its reflow
guard, the bar wheel accumulator and the 5 s refresh while open) and draws it
with `DisplaysDropdown` inside the shared `KeyboardPanelFrame`.

Added to stock:

- **Night light:** `omarchy-toggle-nightlight --status` on open and every
  refresh; the switch runs `omarchy-toggle-nightlight`.
- **Keyboard light:** the first `*kbd_backlight*` LED (found once), read with
  `brightnessctl -d <device> -m`; a switch for on/off devices, a stepped
  slider otherwise.
- **Instant feedback:** every command (night light, keyboard light, text size,
  scale, displays) shows its new state at once and pulses until it exits and
  the state is re-read; a request while one runs is queued, the last one
  winning.
- **Keyed keyboard cursor:** brightness, night light, keyboard light, text
  size, scale, displays (`DisplaysLogic.sectionsFor`). The outline shows only
  while the keyboard drives it, the first key (Enter included) only reveals
  it, and Enter then acts on the outlined row while it still shows there.
  Hover only draws the control's fill; the current scale and the displays
  in use carry the selected highlight.

The brightness slider's wheel steps 5 per event; the sub-notch accumulator
stays on the bar icon's wheel, as in stock.

The pure rules live in `DisplaysLogic.js`, `Model.js` (stock, verbatim apart
from docs) and the shared `CursorLogic.js`.

`Panel.qml` keeps stock's `manageIpc: false` and owns the `omarchy.monitor`
IpcHandler itself, so `omarchy-shell shell summon omarchy.monitor` still
opens it, and the `brightness`/`state` IPC methods keep working.

## Validation

Run `node --test tests/js/displays-logic.test.js` and `tools/check-docs
--root . plugins/araneadev.monitor/Panel.qml`.
