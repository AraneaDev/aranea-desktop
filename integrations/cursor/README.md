# Aranea cursor integration

The repository ships SVG source artwork for the default, hand, busy, and error
pointer roles. The installer compiles them to native Hyprcursor files for
Hyprland and native Xcursor files for compatibility. It then selects `Aranea`
in the desktop settings and refreshes the running Hyprland cursor manager.

The intended visual roles are mint for the default/active pointer, violet for
busy or focus transitions, and red for error feedback. No cursor integration
may replace the user's existing theme without an ownership backup.

The managed theme is installed at `~/.local/share/icons/Aranea`, the standard
Hyprcursor/Xcursor search path. The installer also writes
`~/.config/uwsm/env.d/aranea-cursor`, so UWSM selects Aranea again on the next
login instead of reverting to `default`.
