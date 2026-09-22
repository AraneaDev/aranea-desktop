<div align="center">

# Aranea

**A quiet, obsidian Omarchy desktop with a living spider mark.**

An Omarchy theme by [AraneaDev](https://aranea-development.nl), built around
deep black surfaces, mint light, violet focus states, and a restrained network
wallpaper.

[Omarchy](https://omarchy.org) · [AraneaDev](https://aranea-development.nl)

</div>

![Aranea desktop](screenshots/desktop.png)

## The experience

Aranea carries one visual language from boot to desktop:

- **Obsidian surfaces** — low-noise dark backgrounds with readable muted text.
- **Mint and violet signal** — mint for activity, violet for focus and depth.
- **Spider identity** — the AraneaDev mark appears in the bar, lock screen,
  idle branding, fastfetch, and Plymouth. The wallpaper is intentionally mark-free:
  its network topology keeps the desktop calm behind the UI.
- **Transparent shell bar** — the wallpaper remains visible behind the bar;
  widgets stay compact and interactive.
- **Useful motion, little noise** — notifications, panels, and diagnostics are
  available when needed and stay out of the way when they are not.

## Install

The recommended path is the bundled installer. From a checkout:

```bash
./scripts/install.sh
```

It installs the theme, registers both hooks, and offers to install
`conky-cairo-wayland-git` when `paru` or `yay` is available. Conky is never
started automatically. Use `--yes` for a non-interactive run or `--skip-conky`
to omit the optional diagnostics dependency:

```bash
./scripts/install.sh --yes
./scripts/install.sh --skip-conky
```

Installation profiles are available when you want to audit scope first:

```bash
./scripts/install.sh --dry-run --profile minimal --yes
./scripts/install.sh --dry-run --profile full --yes
./scripts/install.sh --dry-run --profile no_apps --yes
```

Optional integrations can be checked and installed independently:

```bash
./scripts/aranea-doctor --json
./scripts/install-integration terminal --dry-run
./scripts/aranea-wallpaper list
./scripts/aranea-showcase list
```

Managed optional links can be restored with `scripts/uninstall.sh --dry-run`
followed by `scripts/uninstall.sh --yes`.

Preview the actions without changing the system:

```bash
./scripts/install.sh --dry-run --yes
```

To install a fork or a local mirror, set `ARANEA_THEME_REPO_URL` before running
the installer. Without `paru` or `yay`, the theme still installs and the
optional Conky step is reported as skipped.

The shell layout lives in `~/.config/omarchy/shell.json`. The supplied setup
keeps the spider menu and workspaces on the left, the clock and indicators in
the center, and system controls on the right.

## Interactive shell

The bar is transparent and remains fully interactive:

- Click the **spider** to open the Omarchy command menu.
- Right-click the spider to open a terminal.
- Click workspaces to switch sessions.
- Click the center indicators for idle/screensaver and status controls.
- Click the network, audio, Bluetooth, monitor, power, tray, and agent widgets
  to open their native panels.

The custom bar preserves Omarchy's normal widget and popup behavior while
adding Aranea's layout, spider menu mark, and visual restraint.

## Screens

The screenshots below are fresh captures from the installed theme.

### Desktop

Transparent bar, centered indicators, workspaces, system controls, and the
ambient network wallpaper.

![Aranea desktop with transparent bar](screenshots/desktop.png)

### Command menu

The spider opens the familiar Omarchy command surface without leaving the
Aranea visual system.

![Aranea command menu](screenshots/menu.png)

### Notifications

Critical notifications use a finite, high-visibility treatment so routine web
alerts do not remain on screen forever.

![Aranea notification](screenshots/notifications.png)

### Diagnostics

The optional Conky layer is available on demand for a clean system overview.

![Aranea diagnostics panel](screenshots/diagnostics.png)

### Lock screen

The lock surface centers the corrected spider mark above the secure-session
prompt.

![Aranea lock screen](screenshots/lock.png)

### Plymouth boot splash

Apply the Aranea Plymouth bootscreen separately; this rebuilds the initramfs and
requires `sudo`:

```bash
omarchy plymouth set-by-theme aranea
```

The boot splash is logo-only; the password field belongs to the separate lock
screen above. Plymouth uses the same `unlock.png` spider asset as its centered
logo.

![Aranea Plymouth boot screen](screenshots/plymouth.png)

### Branding and idle surfaces

The theme also carries the Aranea mark into the Omarchy About/fastfetch view
and the idle screensaver. Those are terminal-rendered surfaces rather than
static desktop panels, so their source artwork is kept directly inspectable:

- [`branding/about.txt`](branding/about.txt) — fastfetch/About logo.
- [`branding/screensaver.txt`](branding/screensaver.txt) — idle screensaver logo.

Together with the bar, menu, notifications, diagnostics, lock screen, and
Plymouth captures above, these files cover every user-facing customization
shipped by the theme.

## Applications

Aranea also carries its visual language into the applications that make up the
working desktop:

### About / fastfetch

The About view uses the Aranea mark and the mint/violet terminal palette.

![Aranea fastfetch](screenshots/fastfetch.png)

### File manager

GTK theming keeps the file manager aligned with the dark desktop surfaces.

![Aranea file manager](screenshots/file-manager.png)

### Neovim

The supplied Neovim integration brings the same contrast and accent colors into
the editor.

![Aranea Neovim](screenshots/neovim.png)

### Cava

The theme ships a matching [`cava-theme`](cava-theme) and activates it through
the theme hook. Cava is audio-driven, so it is intentionally not represented by
a static capture: with no active playback it correctly renders an empty canvas.

## Palette

| Role | Value |
| --- | --- |
| Background | `#08090b` |
| Mint accent | `#3bff9e` |
| Violet accent | `#7a5cff` |
| Foreground | `#e7ecf3` |
| Muted foreground | `#8b96a6` |

The integration contract also defines `motion_enabled = true` with a static
`reduced_motion_fallback`. Optional integrations are grouped into three
installer profiles: `minimal`, `full`, and `no_apps`; the base install remains
usable with Omarchy alone.

The source palette is in [`colors.toml`](colors.toml); shell-specific surface
tokens are in [`shell.toml`](shell.toml).

## Optional diagnostics

Conky is intentionally not started during login. Toggle it when you want the
system panel:

```bash
aranea-diagnostics-toggle
```

The supplied Hyprland binding is `SUPER + CTRL + SHIFT + D`. The diagnostics
layer requires a Conky build with real Wayland layer-shell support, such as
`conky-cairo-wayland-git` from the AUR.

## Branding and files

- `backgrounds/` — coordinated day and night wallpapers; the topology is
  deliberately free of the spider mark.
- `backgrounds/manifest.toml` — stable wallpaper IDs, contrast metadata, and
  motion capabilities.
- `integrations/` — optional terminal, developer-tool, cursor, Qt, browser,
  session, media, and icon integrations with explicit fallbacks.
- `branding/` — fastfetch and idle screensaver marks.
- `unlock.png` — shared spider asset for the bar, lock screen, and boot flow.
- `plugins/araneadev.bar/` — transparent interactive bar composition.
- `plugins/araneadev.menu/` — spider menu widget and command menu.
- `plugins/araneadev.lock/` — Aranea lock surface with native PAM handling.
- `plugins/araneadev.notifications/` — finite critical notification treatment.
- `hooks/` — theme-set and post-boot integration.

## License

See the repository's upstream project and asset licenses before redistributing
modified branding or wallpapers.
