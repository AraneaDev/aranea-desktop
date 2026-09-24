# Aranea icon integration

Aranea does not replace a complete system icon collection. Instead, the
`icons` integration
selects `Yaru-prussiangreen-dark` — a muted, accent-toned variant already
carried by the `yaru-icon-theme` package Omarchy installs — and shrinks
Nautilus's default grid/list zoom so icons stop dominating the theme's dark,
low-contrast surfaces.

Installed on `full` and `no_apps` profiles via
`scripts/install-integration icons`. If `Yaru-prussiangreen-dark` is not
present on the host, the step is skipped and the active icon theme remains in
place.
