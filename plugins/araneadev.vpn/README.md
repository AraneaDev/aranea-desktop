# Aranea VPN

`araneadev.vpn` is a new (not cloned) bar-widget plugin for a dedicated VPN
dropdown: NetworkManager VPN/WireGuard profiles and own-app VPNs (Tailscale,
Mullvad, ProtonVPN, ...), moved out of `araneadev.network`'s VPN section.

## Current state (skeleton)

- `manifest.json` declares the `bar-widget` entry point, `Panel.qml`.
- `Panel.qml` is a placeholder: a `BarIconButton` carrying the VPN glyph
  (`0xf0582`, shared with `araneadev.network`'s VPN rows), kept at zero
  width so it stays invisible in the bar. The IPC target `aranea.vpn`
  already answers `open`/`close`/`show`/`hide`/`toggle` through `Panel`'s
  own `IpcHandler`, but there is no dropdown content yet.
- `VpnLogic.js` holds the pure rules a later task wires in: parsing nmcli's
  VPN connection list and per-connection session fields, building the
  Connected/Available rows (NetworkManager profiles and own-app VPNs), the
  secrets sent to nmcli on stdin, auth-failure detection, the nmcli argv
  for connect/disconnect, and small text helpers. See its header for the
  shared `splitTerse` facade note.
- `scripts/repair-shell-config` inserts `araneadev.vpn` into the bar layout
  right after the network entry (`araneadev.network`, or `omarchy.network`
  when the Aranea network clone isn't installed) once this plugin's
  manifest is deployed; `scripts/release-shell-config` removes it when
  Aranea steps aside. `scripts/deploy-plugins-safely` deploys it like any
  other plugin.

## View

Pure views (plain properties in, one `action(name, arg)` signal out, no
nmcli logic; the panel hands them ready strings):

- `VpnHeader`: `DropdownHeader` with the VPN glyph tinted by `iconState`,
  "VPN" and the connection caption. No switch.
- `VpnSection`: CONNECTED or AVAILABLE with a count; NetworkManager rows
  carry a `FilamentSwitch`, own-app rows an "open app" `FilamentPill`, both
  settled by their row. Connected rows show a `VpnSession`; the row the
  prompt names shows the shared `CredentialPrompt` (read-only username,
  password, optional 2FA code).
- `VpnSession`: IP, Server (when known) and Up, then `Aranea.LinkGraph`
  once there are samples.
- `VpnDropdown`: the header, pinned Connected, Available in a capped
  Flickable, the empty text and the key hint. Status, sessions, graphs and
  the prompt are separate properties keyed by row key, so they never
  rebuild a row.

## What's missing

The icon stays invisible and the panel shows no dropdown until a later task
wires real state (polling, the prompt state and the keyboard cursor) into
`Panel.qml` and hosts `VpnDropdown`.

## Validation

Run `node --test tests/js/vpn-logic.test.js`,
`tests/qml-behaviour.test.sh vpn-dropdown` and `tests/shell-config.test.sh`.
