# Aranea Display

`araneadev.monitor` replaces Omarchy's `omarchy.monitor` bar dropdown. It
keeps stock's logic and view in `Panel.qml` and `Model.js` unchanged for now
(brightness, text size, scale and display controls, the keyboard cursor and
IPC) and adds only documentation comments. `DisplaysLogic.js` holds the pure
rules for the Aranea-native view coming next (night light, keyboard
backlight, section and header rules, and the pending/queue helpers); nothing
in this panel calls it yet.

`Panel.qml` keeps stock's `manageIpc: false` and owns the `omarchy.monitor`
IpcHandler itself, so `omarchy-shell shell summon omarchy.monitor` still
opens it, and the `brightness`/`state` IPC methods keep working.

## Validation

Run `node --test tests/js/displays-logic.test.js` and `tools/check-docs
--root . plugins/araneadev.monitor/Panel.qml`.
