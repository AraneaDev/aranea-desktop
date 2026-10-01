# Aranea Bluetooth

`araneadev.bluetooth` replaces Omarchy's `omarchy.bluetooth` bar dropdown. It
keeps stock's logic in `Panel.qml` and `Model.js` (discovery and its clean
stop on close, pending actions, the audio hand-off after a connect, the
keyboard cursor and the bar icon) and draws an Aranea view,
`BluetoothDropdown.qml`: a Filament header and power switch, a scanning
pulse, and web-node device rows for Connected, Paired and Available, with a
busy pulse while a device connects and a signal glow on nearby devices.

The signal glow reads RSSI from BlueZ with one `busctl` call every 2 s, and
only while the open panel is scanning and has devices under Available.

`Panel.qml` keeps stock's `manageIpc: false` and owns the `omarchy.bluetooth`
IpcHandler itself, so `omarchy-shell shell summon omarchy.bluetooth` still
opens it.

## Validation

Run `node --test tests/js/bluetooth-logic.test.js` and
`tests/qml-behaviour.test.sh bluetooth-dropdown`.
