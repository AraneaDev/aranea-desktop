# Aranea session integration

Session assets are intentionally display-manager neutral. Apply the palette,
lock-screen mark, and wallpaper through the installed Omarchy session stack's
native theme interface. If the host greeter is unsupported, keep its existing
theme and use the Aranea lock/Plymouth assets instead.

Never write greeter configuration during a normal theme-set hook.
