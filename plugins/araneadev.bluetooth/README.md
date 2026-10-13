# Aranea Bluetooth

`araneadev.bluetooth` replaces Omarchy's `omarchy.bluetooth` bar dropdown. It
keeps stock's logic in `Panel.qml` and `Model.js` (discovery and its clean
stop on close, pending actions, the audio hand-off after a connect, the
keyboard cursor and the bar icon) and draws an Aranea view,
`BluetoothDropdown.qml`: a Filament header and power switch, a scanning
pulse, and web-node device rows for Connected, Paired and Available, with a
busy pulse while a device connects and a signal glow on nearby devices.

The power switch shows its new state at once and pulses until BlueZ reports
it; clicks made meanwhile queue (the last one wins), and after 5 s it falls
back to the adapter's real state. Device actions are keyed by the device's
address and refused when the row changed underneath the click; a click on a
busy device queues until it is idle (the last one wins, and one equal to the
action in flight is dropped). Clicks settle for 300 ms after the layout
shifts. After `x` forgets a device, the keyboard cursor moves to the
neighbouring row.

The signal glow reads RSSI from BlueZ with one `busctl` call every 2 s, and
only while the open panel is scanning and has devices under Available.

`Panel.qml` keeps stock's `manageIpc: false` and owns the `omarchy.bluetooth`
IpcHandler itself, so `omarchy-shell shell summon omarchy.bluetooth` still
opens the Bluetooth page inside Network when embedded. The hosted controller
creates no separate popup or bar entry. Network owns page selection (`n`, `v`,
`b`) and forwards device navigation, Enter, and `x` to the existing Bluetooth
cursor. Leaving the page closes its discovery lifecycle; moving the popup
between monitors hands the discovery debt to the controller on the new monitor.
The hosted page uses `t` for power while `b` selects the Bluetooth page.
The standalone fallback keeps its original dropdown and `b` power shortcut.

## Validation

Run `node --test tests/js/bluetooth-logic.test.js` and
`tests/qml-behaviour.test.sh bluetooth-dropdown bluetooth-keyed bluetooth-forget-hover bluetooth-embedded`.
