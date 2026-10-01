# Aranea Bluetooth

`araneadev.bluetooth` replaces Omarchy's `omarchy.bluetooth` bar dropdown.
For now it is a straight clone: `Panel.qml` and `Model.js` are copied
verbatim from stock (only documentation comments added), so behaviour and
look are unchanged. A later task gives it the Aranea-native view (Filament
components, the shared device-row glow and busy states) the same way
`araneadev.audio` replaced `omarchy.audio`.

`Panel.qml` keeps stock's `manageIpc: false` and owns the `omarchy.bluetooth`
IpcHandler itself, so `omarchy-shell shell summon omarchy.bluetooth` still
opens it.

## Validation

Run `node --test tests/js/bluetooth-logic.test.js` for `BluetoothLogic.js`.
A `tests/qml-behaviour.test.sh` suite for the dropdown's own view arrives
with its Aranea-native redesign.
