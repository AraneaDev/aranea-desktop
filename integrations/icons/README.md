# Aranea icon integration

Aranea does not replace a complete system icon collection. Instead, the
`icons` integration installs a small `Aranea-icons` theme
(`integrations/icons/aranea/`) that overrides only the folder glyphs with
accent-gradient artwork matching the spider mark, and inherits
`Yaru-prussiangreen-dark` — a muted, accent-toned variant already carried by
the `yaru-icon-theme` package Omarchy installs — for every other icon, with
`Adwaita` and `hicolor` as further fallbacks. It also shrinks Nautilus's
default grid/list zoom so icons stop dominating the theme's dark,
low-contrast surfaces.

Installed on `full` and `no_apps` profiles via
`scripts/install-integration icons`, which links the theme into
`~/.local/share/icons/Aranea-icons` and sets it as the active GTK icon theme.
