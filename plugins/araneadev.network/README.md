# Aranea Network

`araneadev.network` replaces Omarchy's `omarchy.network` bar dropdown. It
keeps stock's root logic in `Panel.qml` and `Model.js` (connection details,
throughput and ping polling, Wi-Fi scanning and actions, the passphrase
prompt and enterprise connect, DNS and band selection, the cursor model,
the bar icon and IPC) and draws an Aranea view, `NetworkDropdown.qml`, in
place of stock's.

Stock's root code is kept except for four edits: the caption fade animates
`captionOpacity` instead of stock's caption Text, `updateDetails` ends by
recording a Link graph sample, `keyCatcher` names the frame's key catcher
so stock's prompt-close focus hand-back still resolves, and `setDns`
leaves the dropdown open on a DNS provider pick instead of closing it
immediately (stock's own behaviour). Stock's per-row NetworkManager hooks
(connect failures, completion checks) and the 2 s "Wrong password" timer
moved from the stock row to the root, and the prompt's submit moved there
too.

Picking a DNS provider (DHCP, Cloudflare, Google) shows it chosen and
pulsing busy at once (`pendingDnsProvider` / `selectedDnsProvider`, as the
Power dropdown's profile pills do) instead of closing the dropdown the way
stock did; the pill settles once `actionProc` exits, to the real provider
on success. A pick that lands while `actionProc` is already busy (running
a DNS change or a band pin) queues, the latest replacing any earlier one,
and runs the moment the current one exits -- the last click wins
(`actionProcKind` says which of a DNS or band change just finished, since
the two share one `Process`). Custom still opens the floating terminal and
closes immediately, since it hands off rather than running a command here.
The DNS and band pill rows (`dnsRows`, `bandRows`) carry no `selected`
flag, so `CursorLogic.keepRows` keeps handing back the same array across a
selection change and their `Repeater`s never rebuild; which pill is chosen
comes from the view's `selectedDnsProvider`/`bandEffective` instead.

The extras, all hidden when they have nothing to show:

- **Link graph:** the receive and send rates stock already computes, the
  last 40 samples (60 s), cleared on close.
- **Interfaces, Saved:** one poll every 4 s while open (and on open):
  `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device`,
  `nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE,TIMESTAMP,STATE connection show` and
  `ip -j -4 -br addr`, in one `bash -c` that prints nothing without
  `nmcli`. Saved profiles' SSIDs come from
  `nmcli -g 802-11-wireless.ssid connection show uuid <uuid>` (one
  `uuid<TAB>ssid` line per profile, an empty SSID when the lookup fails),
  run on open and after a forget only. A read asked for while one runs
  (a forget landing mid-poll, even after the output was read) runs again
  once it finishes.
- **VPN status line:** one muted line under the header, "VPN · <name> up"
  (or "VPN · N up"), hidden when nothing is up. It's `VpnApps.statusLine`
  over `VpnApps.upNames` (`araneadev.shared`): NetworkManager VPN/WireGuard
  connections from the same extras poll (only fully "activated" ones) plus
  own-app VPNs, by name, from the optional
  `~/.config/aranea/vpn-apps.json` (`VpnApps.parseAppsConfig`, read through
  a `FileView`; a file with any error is ignored as a whole,
  `VpnApps.appsToApply`, as `araneadev.vpn` does) detected by interface
  against the same poll's `ip -j -4 -br addr` output (`VpnApps.appState`).
  The `showcase` stand-ins relabel it too. Showing or hiding it moves
  every section below, so clicks there settle for 300 ms after it does
  (see `araneadev.shared`'s `ClickSettle.js`). Pointer-only: clicking it closes
  this dropdown and opens `araneadev.vpn`'s
  (`bar.shell.summon("araneadev.vpn")`), which owns every other VPN
  behaviour (connect/disconnect, sessions, uptimes, traffic).
- **Saved forget:** `nmcli connection delete uuid <uuid>`; the row breathes
  and reads "Forgetting…" until the next extras read that started after
  the delete finished. A failed delete reads "Couldn't forget" in the
  urgent colour for 4 s.

The keyboard walks header, band, DNS, Wi-Fi and Saved
(`NetworkLogic.moveVertical`); `r` refreshes and `w` toggles Wi-Fi. Enter
does what the key hint under the list says for the cursor's section:

- **Header, band, DNS:** runs the action or applies the pill.
- **Wi-Fi:** connects (or opens the passphrase prompt), or disconnects the
  connected network; on the forget action (→) it forgets.
- **Saved:** moves onto the row's forget action, as → does; Enter there
  forgets.

The VPN status line isn't in this chain: it's pointer-only, drawing no
cursor outline.

`x` forgets a known Wi-Fi or Saved row. The cursor outline shows only while
the keyboard drives it.

**No key press ever acts on a row the user didn't choose and can see.**

- Each section's cursor holds the key of the row (header action, band pill
  or Automatic switch, network or profile) it was deliberately put on
  (an arrow, a left/right pick in the header, band or DNS, a hover, a
  click, or open's Wi-Fi row 0) and follows that row when the list
  re-sorts. Revealing the outline never chooses a row.
- When the row disappears, the cursor is clamped but its key is dropped.
  Enter and `x` then do nothing until the user picks a row
  (`CursorLogic.followCursor`, `araneadev.shared`, imported directly; `cursorConfirmed`
  generated into `NetworkLogic.js` by `tools/js-facade-generator.mjs`). A hidden SSID never
  confirms (it still works by mouse).
- The same goes for a cursor moved automatically into another section, for
  example when Saved or the band section empties or hides under it
  (`NetworkLogic.keyTargetConfirmed`).
- Enter or `x` on a cursor the pointer placed (no outline) only reveals it
  (`NetworkLogic.pressOutcome`), so the row that slid into a lost key's
  place is never adopted by a reveal.
- Pointer actions carry their row's key and are refused when the row
  changed.
- A row or forget button created under a still pointer ignores clicks for
  300 ms unless the pointer really moves over its row or button.
- Unchanged refreshes keep the same row arrays, so delegates aren't
  rebuilt.
- While a Wi-Fi action runs, the Wi-Fi rows are dimmed, as stock disabled
  them.

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
- `NetworkLinkSection`: "LINK", the shared `Aranea.LinkGraph` trace
  (`GraphLogic.graphPoints`, `araneadev.shared`) and stock's stats grid;
  the IP address and gateway copy on click.
- `NetworkInterfacesSection`: read-only interface rows, shown with two or
  more links.
- `NetworkBandSection`, `NetworkDnsSection`: `FilamentPill` rows.
- `NetworkWifiSection`: the Wi-Fi list with stock's section titles, a lock
  on secured rows, forget, status text and the inline passphrase prompt
  (the shared `Aranea.CredentialPrompt`, identity first for enterprise).
- `NetworkSavedSection`: saved profiles out of range, dimmed, with forget.
- Both lists use the shared `Aranea.ForgetButton` (as Bluetooth does).
- `NetworkDropdown`: every section, the VPN status line (drawn inline,
  under the header), the Wi-Fi/Saved scroll area, the empty text and the
  key hint, reporting user actions through one `action(name, arg)` signal.

## Validation

Run `node --test tests/js/network-logic.test.js`,
`tests/qml-behaviour.test.sh network-sections network-dropdown` and `tools/check-docs
--root . plugins/araneadev.network/Panel.qml`.
