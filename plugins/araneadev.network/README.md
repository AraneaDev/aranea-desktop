# Aranea Network

`araneadev.network` replaces Omarchy's `omarchy.network` bar dropdown. It
keeps stock's logic and view in `Panel.qml` and `Model.js` unchanged for
now (connection details, throughput/ping polling, Wi-Fi scanning and
actions, DNS and band selection, the keyboard cursor and IPC) and adds only
documentation comments.

`Panel.qml` keeps stock's `manageIpc: false` and owns the `omarchy.network`
IpcHandler itself, so `omarchy-shell shell summon omarchy.network` still
opens it. `omarchy.wifiqr` and `omarchy.speedtest` are summoned by id and
need nothing from this plugin.

## Validation

Run `node --test tests/js/network-logic.test.js` and `tools/check-docs
--root . plugins/araneadev.network/Panel.qml`.
