# Aranea icon integration

Aranea does not replace every long-tail system icon. Instead, the `icons`
integration installs an `Aranea-icons` theme
(`integrations/icons/aranea/`) that overrides the Wave 1 file-manager core
(places, devices, status, actions, and common MIME types) with precise
technical artwork and semantic spider-silk accents, and inherits
`Yaru-prussiangreen-dark` — a muted, accent-toned variant already carried by
the `yaru-icon-theme` package Omarchy installs — for every other icon, with
`Adwaita` and `hicolor` as further fallbacks. It also shrinks Nautilus's
default grid/list zoom so icons stop dominating the theme's dark,
low-contrast surfaces.

Installed on `full` and `no_apps` profiles via
`scripts/install-integration icons`, which links the theme into
`~/.local/share/icons/Aranea-icons` and sets it as the active GTK icon theme.
