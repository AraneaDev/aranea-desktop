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

## View sections

Pure views for the Aranea dropdown (assembled by `NetworkDropdown`): plain
properties in, signals out, no panel state. Hover reaches the host only
through the `pointerGate` each section receives.

- `NetworkHeader`: `DropdownHeader` with QR, speed test and the Wi-Fi
  switch (each only when it applies) and a scan `FilamentPulse` under it.
- `NetworkLinkSection`: "LINK", the `NetworkGraph` trace and stock's stats
  grid; the IP address and gateway copy on click.
- `NetworkGraph`: a `Canvas` drawing `NetworkLogic.graphPoints`.
- `NetworkInterfacesSection`: read-only interface rows, shown with two or
  more links.
- `NetworkVpnSection`: VPN and WireGuard rows with a switch each.
- `NetworkBandSection`, `NetworkDnsSection`: `FilamentPill` rows.
- `NetworkWifiSection`: the Wi-Fi list with stock's section titles, a lock
  on secured rows, forget, status text and the inline passphrase prompt
  (identity first for enterprise).
- `NetworkSavedSection`: saved profiles out of range, dimmed, with forget.
- `NetworkForgetButton`: Bluetooth's forget button, shared by both lists.
- `NetworkDropdown`: every section, the Wi-Fi/Saved scroll area, the empty
  text and the key hint, reporting user actions through one
  `action(name, arg)` signal.

## Validation

Run `node --test tests/js/network-logic.test.js`,
`tests/qml-behaviour.test.sh network-sections network-dropdown` and `tools/check-docs
--root . plugins/araneadev.network/Panel.qml`.
