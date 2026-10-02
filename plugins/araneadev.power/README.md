# Aranea Power

`araneadev.power` replaces Omarchy's `omarchy.power` bar dropdown. It keeps
stock's logic and view in `Panel.qml` and `Model.js` unchanged for now
(battery and system stats polling, the power profile picker, the rotating
hero status phrases and IPC) and adds only documentation comments.

`Panel.qml` keeps stock's `manageIpc: false` and owns the `omarchy.power`
IpcHandler itself, so `omarchy-shell shell summon omarchy.power` still opens
it, and `togglePercentage` (right-click the bar icon) keeps working.

## Validation

Run `node --test tests/js/power-logic.test.js` and `tools/check-docs --root
. plugins/araneadev.power/Panel.qml`.
