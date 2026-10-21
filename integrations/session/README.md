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
