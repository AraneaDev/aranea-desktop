# Aranea session integration

Session assets are intentionally display-manager neutral. The installer places
the palette fragment at `~/.config/omarchy/session/aranea.css`; apply it only
through the installed session stack's native theme interface. If the host
greeter is unsupported, keep its existing theme and rely on the Aranea lock
screen and the `unlock.png` Plymouth logo instead.

Never write greeter configuration during a normal theme-set hook.

## Center bar layout

[`bar-center.json`](bar-center.json) records this order from left to right:
Screen recording → Set Reminder → Allow Idle Lock → Clock → Sudo passwordless
→ Updates → Night Light. Each native indicator has its own slot so active
states cannot reorder the group. Notification silence stays in Notifications.

This is a layout preset, not a full `shell.json` replacement. Use its `center`
list for `bar.layout.center` and its `centerAnchor` for `bar.centerAnchor`, keeping
the saved options on existing Clock, Sudo and Updates entries. Other bar sections
remain unchanged. Normal theme installation preserves the user's saved layout.

## Automatic screensavers and timing

Full installs link the session's `bin/omarchy-launch-screensaver` into
`$XDG_BIN_HOME` (default `~/.local/bin`) through the ownership ledger. The
launcher reads Omarchy's authoritative `theme.name` and dispatches active Aranea
to the owner in `~/.config/omarchy/themes/aranea`, which survives theme switches.
Other themes and missing owner prerequisites use the packaged launcher directly.
The owner alone handles renderer availability fallback; a failed owner is never
retried as stock. No PATH configuration is changed. Owner status checks the
owned link and resolves the command through bounded `bash -lc`, matching upstream
idle launch. `integration.reachable: false` means automatic activation has not
been established, even when manual Preview is accepted.

Enable the **Session** integration through Settings when inactive. A scene Apply
or Preview never enables idle or changes pause flags. Automatic launch still
requires Omarchy's idle service to be enabled and unpaused.

The picker offers nine Chromium/WebGL scenes: Silk Journey, Neon Weaver, Spiderfall,
Kanji Drift, Silken Flow, Neon Depths, Orbital Loom, Blackglass Foundry, and Crystal Bloom. The first three feature the spider.
Silk Chamber remains an experiment; Omarchy's terminal saver is an automatic
availability fallback rather than a picker entry. Selection/shuffle lives in Aranea's separate screensaver config;
timing remains in Omarchy. The supervisor uses one scene across active monitors,
exact Wayland class `org.omarchy.screensaver`, and bounded readiness/cleanup.
Supervised web sessions use Chromium kiosk mode; legacy standalone Preview keeps
app mode. Hyprland placement/restoration uses fixed allowlisted typed Lua calls
with encoded data literals, passed as separate `hyprctl` argv. Catalog text is
never executed. See the [model guide](../../branding/3d/README.md#picker-and-automatic-sessions).

`aranea-screensaver configure-idle SCREENSAVER_SECONDS LOCK_SECONDS --json` and
Settings `configure screensaver-timing SCREENSAVER_SECONDS LOCK_SECONDS --json`
save two inactivity deadlines in the XDG Omarchy `shell.json`. Both count from
last activity; lock is not an extra delay after the saver. Integer seconds from
0 through 86400 are accepted; 0 disables that deadline. When both are enabled,
lock must be later. Scene Apply and Preview never save timing, and timing Apply
does not depend on scene selection or installed renderers.

Timing edits preserve unrelated keys, symlink targets and existing file modes,
serialize through an adjacent lock, and atomically replace the target. Missing
configuration can be created from the packaged Omarchy defaults only on an
explicit save; malformed configuration is preserved and reported. Reads create
no configuration or state. Saving requests bounded `omarchy-shell shell
reloadConfig`; the response distinguishes persisted data from a rejected reload.
A successful reload acknowledgment does not independently verify the running
idle service's deadlines. Display the readback as configured timing. Timing
Apply never restarts the desktop or changes Stay awake/screensaver-off flags.
The owner reports those persisted pause indicators, or null when the host is
unavailable. Deactivate/uninstall removes only the owned launcher and restores
its predecessor; user replacements remain authoritative.
