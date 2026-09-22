# Aranea session integration

Session assets are intentionally display-manager neutral. The installer places
the palette fragment at `~/.config/omarchy/session/aranea.css`; apply it only
through the installed session stack's native theme interface. If the host
greeter is unsupported, keep its existing theme and use the Aranea
lock/Plymouth assets instead.

Never write greeter configuration during a normal theme-set hook.
