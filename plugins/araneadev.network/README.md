# Aranea Network

`araneadev.network` replaces Omarchy's `omarchy.network` bar dropdown. It
keeps stock's root logic in `Panel.qml` and `Model.js` (connection details,
throughput and ping polling, Wi-Fi scanning and actions, the passphrase
prompt and enterprise connect, DNS and band selection, the cursor model,
the bar icon and IPC) and draws an Aranea view, `NetworkDropdown.qml`, in
place of stock's.

Stock's root code is kept except for three edits: the caption fade animates
`captionOpacity` instead of stock's caption Text, `updateDetails` ends by
recording a Link graph sample, and `keyCatcher` names the frame's key
catcher so stock's prompt-close focus hand-back still resolves. Stock's
per-row NetworkManager hooks (connect failures, completion checks) and the
2 s "Wrong password" timer moved from the stock row to the root, and the
prompt's submit moved there too.

The extras, all hidden when they have nothing to show:

- **Link graph:** the receive and send rates stock already computes, the
  last 40 samples (60 s), cleared on close.
- **Interfaces, VPN, Saved:** one poll every 4 s while open (and on open):
  `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device`,
  `nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,TIMESTAMP connection show` and
  `ip -j -4 -br addr`, in one `bash -c` that prints nothing without
  `nmcli`. Saved profiles' SSIDs come from
  `nmcli -g 802-11-wireless.ssid connection show uuid <uuid>`, run on open
  and after a forget only.
- **VPN toggle:** `nmcli connection up|down uuid <uuid>`; the row breathes
  while it runs and reads "Couldn't connect" for 4 s if it fails.
- **Saved forget:** `nmcli connection delete uuid <uuid>`, then a re-read.

The keyboard walks header, VPN, band, DNS, Wi-Fi and Saved
(`NetworkLogic.moveVertical`); Enter activates, `x` forgets a known Wi-Fi
or Saved row, `r` refreshes and `w` toggles Wi-Fi. The cursor outline
shows only while the keyboard drives it.

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
