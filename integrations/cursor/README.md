# Aranea cursor integration

The repository ships SVG source artwork for the default, hand, busy, and error
pointer roles. Convert those sources to the host's Xcursor format when the
desktop supports it; otherwise keep the host cursor and use the Aranea Qt/GTK
focus colors. The SVG sources are intentionally kept inspectable rather than
pretending to be binary Xcursor files.

The intended visual roles are mint for the default/active pointer, violet for
busy or focus transitions, and red for error feedback. No cursor integration
may replace the user's existing theme without an ownership backup.

The managed source theme is installed at `~/.config/icons/Aranea`. Because the
included sources are SVG, a desktop that requires compiled Xcursor files can
convert them in place; unsupported hosts safely retain the active cursor.
