# Aranea cursor integration

The repository ships SVG source artwork for the default, hand, busy, and error
pointer roles. The installer keeps those sources inspectable and compiles them
to native Xcursor files with `xcursorgen` when the host provides it. It then
selects `Aranea` in the desktop settings and refreshes the running Hyprland
cursor manager.

The intended visual roles are mint for the default/active pointer, violet for
busy or focus transitions, and red for error feedback. No cursor integration
may replace the user's existing theme without an ownership backup.

The managed theme is installed at `~/.config/icons/Aranea`. Hosts without
`xcursorgen` safely retain the active cursor theme; install `xorg-xcursorgen`
to enable the native cursor activation path.
