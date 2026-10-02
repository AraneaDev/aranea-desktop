# Aranea VPN

`araneadev.vpn` is a new (not cloned) bar-widget plugin: a VPN icon in the
bar and its dropdown. It runs two kinds of VPN side by side:

- **NetworkManager VPNs** (OpenVPN, WatchGuard Firebox SSL imported from
  its `.ovpn`, OpenConnect / GlobalProtect, WireGuard): each row has a
  switch that connects or disconnects the profile, with an inline
  password / 2FA prompt when the profile needs secrets.
- **Own-app VPNs** (Azure VPN Client, Palo Alto's GlobalProtect client,
  anything with its own sign-in): listed from a config file, their state
  read from a network interface and/or a process; a click opens the app.
  The dropdown never signs in or out of them.

## What it shows

- **The bar icon:** dim when no VPN is up, accent when any is, urgent for
  4 s after a connect fails or a VPN drops without being turned off here.
  It's hidden (zero width) when there are no NetworkManager VPN profiles
  and no apps. Left-click toggles the dropdown.
- **Header:** "VPN" and "N of M connected" (or "Not connected").
- **CONNECTED** (pinned) then **AVAILABLE** (scrolls): NetworkManager rows
  first, then apps, each by name. Under each connected row: its IP, server
  and uptime ("since before open" when it was already up the first time
  the shell looked), and a receive/send graph of its tunnel's traffic
  while the dropdown is open.
- **Empty states:** "No VPNs yet" (only reachable through IPC, as the icon
  is hidden then) and "NetworkManager isn't running".

## Connecting

- A switch first runs `nmcli --wait 30 connection up uuid <uuid>`. When
  NetworkManager answers that secrets are required, the row opens the
  prompt: the profile's username (read-only, from `vpn.data`), the
  password and an optional 2FA code.
- Connect runs `nmcli --wait 60 connection up uuid <uuid> passwd-file
/dev/stdin`, and only with a non-empty password. On submit the password
  and code are copied out of the prompt (whose fields clear at once); the
  copy is written to nmcli's **stdin** the moment the process starts, then
  cleared, and only then is stdin closed, so a started nmcli always gets
  the submitted password. They never appear in argv, logs or files.
  Closing the prompt or the dropdown meanwhile doesn't cancel the connect:
  it goes ahead and its outcome shows on the row and the bar icon. While
  nmcli waits (push 2FA), the row reads "Connecting… approve on phone"
  after 5 s.
- A rejected password reopens the prompt ("Couldn't connect, check password
  or code"); any other failure reads "Couldn't connect" for 4 s.
- The switch on a connected row runs `nmcli --wait 20 connection down uuid
<uuid>`.

## Keyboard

↑/↓ move across Connected then Available (the first press only reveals
the cursor); Enter toggles a NetworkManager row or opens an app; Tab and
Shift+Tab switch dropdowns; Esc closes. While the prompt is open it owns
the keys: Enter moves to the next field and connects from the last, Esc
cancels. The cursor follows the profile it was put on, never a position:
a row that vanished or moved under it is refused, not replaced, and an
open (or a reveal) chooses no row until you move or hover. Until a row
is chosen, the key hint offers only the moves, Tab and Esc.

## The config file

`~/.config/aranea/vpn-apps.json` (`$XDG_CONFIG_HOME/aranea/` when set) is
optional and yours: the theme never writes it. It's watched, so edits
apply without a shell restart. A file with any error (invalid JSON, an
entry without a `name` or an array `open`, two entries with the same
`name`) is ignored as a whole, apps and profiles alike, with one warning in
the shell log per distinct error.

A bare array lists the apps:

```json
[
  {
    "name": "Azure (Contoso)",
    "label": "Azure VPN Client",
    "detect": { "interface": "tun*", "process": "microsoft-azurevpnclient" },
    "open": ["microsoft-azurevpnclient"]
  },
  {
    "name": "GlobalProtect (HQ)",
    "label": "GlobalProtect",
    "detect": { "interface": "gpd0" },
    "open": ["globalprotect", "launch-ui"]
  }
]
```

- `detect.interface`: a name or glob (`*`, `?`) matched against `ip -j
addr`; up with an address counts as connected, and the first matching
  interface that is up with an address gives the session IP and graph.
  Prefer the client's own interface name over a glob: `tun*` also matches
  NetworkManager OpenVPN's `tun0`, so an OpenVPN profile coming up would
  read as this app being connected too (and could lend it its IP and
  graph). Where the client always uses the same device, give its exact
  name, as `gpd0` above; keep a glob such as `tun*` only alongside a
  `detect.process`, as the Azure entry does, so both have to match.
- `detect.process`: a process name matched exactly with `pgrep -x` (its
  characters are literal: a `.` or `+` in it matches only itself). With both
  given, both must match for connected.
  The kernel cuts process names to 15 bytes, so a longer name (such as
  `microsoft-azurevpnclient`) is matched on its first 15 bytes
  (`microsoft-azure`): any process whose name starts with them counts.
- `open`: an argv array run detached, never through a shell. When its
  binary isn't a program on `PATH` (a shell builtin or alias doesn't count)
  the row reads "Couldn't open <name>" for 4 s.

The object form adds per-profile settings for NetworkManager VPNs, keyed
by profile name. `otp` says how the 2FA code is sent: `append` (the
default; appended to the password, the WatchGuard / RADIUS convention) or
`challenge` (OpenVPN's static-challenge response):

```json
{ "apps": [ ... ], "profiles": { "Office (Firebox)": { "otp": "append" }, "Client A": { "otp": "challenge" } } }
```

## Installing VPN support (not automated)

```sh
# OpenVPN profiles (and WatchGuard Firebox SSL)
sudo pacman -S networkmanager-openvpn
# OpenConnect, including GlobalProtect's gp protocol
sudo pacman -S networkmanager-openconnect
# Microsoft's Azure VPN Client (AUR)
yay -S microsoft-azure-vpn-client-bin
# Palo Alto's GlobalProtect client (AUR), when SSO needs it
yay -S globalprotect-bin
```

Import a Firebox (or any OpenVPN) `.ovpn` as a NetworkManager profile:

```sh
nmcli connection import type openvpn file X.ovpn
```

## IPC

Target `aranea.vpn`: `open`, `close`, `show`, `hide`, `toggle`, plus two
display-only screenshot calls, accepted only while the dropdown is open
and cleared on open and close:

- `showcase ' ["Alpha", "Beta"]'` relabels the rows in display order;
- `showcaseFixture ' [{"name": "Office", "kind": "nm", "connected": true}]'`
  replaces the rows with stand-ins
  (`[{name, label, kind: "nm"|"app", connected, ip, server, upMinutes}]`),
  so a capture works on a machine without VPNs. Every action is refused
  while a fixture is shown.

Keep the leading space inside the quotes: `qs` reads an argument that
starts with `[` as a list, not as the JSON string, so
`omarchy-shell aranea.vpn showcaseFixture ' [...]'` works where `'[...]'`
doesn't (`scripts/capture-screenshots` does the same).

## Files

- `Panel.qml`: the root logic (polling, actions, the prompt, the apps
  file, sessions, uptimes, rates, the cursor, IPC), hosting the view in
  the shared keyboard frame.
- `VpnLogic.js`: every pure rule (parsing, rows, secrets stdin text,
  outcomes, uptimes, rates, cursor moves, fixtures).
- `VpnDropdown`, `VpnHeader`, `VpnSection`, `VpnSession`: the pure view
  (plain properties in, one `action(name, arg)` signal out). Status,
  sessions, graphs and the prompt are separate properties keyed by row key,
  so they never rebuild a row.
- `scripts/repair-shell-config` inserts `araneadev.vpn` into the bar
  layout right after the network entry, once: it leaves
  `$XDG_STATE_HOME/aranea/vpn-widget-placed`, so an icon you take out of
  the bar stays out. `scripts/release-shell-config` removes it and, when
  it was in the bar, parks it (`vpn-widget-parked`) so the next return to
  Aranea puts it back, as the bell and health icons do.

## Polling

While open: connections every 2 s, links and app processes every 2 s,
rates every 1.5 s; sessions are read when a profile appears or its state
changes, never polled. While closed: one 5 s poll for the bar icon, and
none at all when there are no NetworkManager VPN profiles and no apps
(a 60 s re-check, and the watched apps file, notice new ones).

## Validation

Run `node --test tests/js/vpn-logic.test.js`,
`tests/qml-behaviour.test.sh vpn-dropdown` and `tests/shell-config.test.sh`.
