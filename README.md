<div align="center">

# Aranea Desktop

**A quiet, obsidian Omarchy desktop experience with a living network of light.**

Deep black surfaces, mint activity, violet focus, atmospheric wallpapers, and
the AraneaDev mark carried consistently from boot to desktop.

[![Release](https://img.shields.io/github/v/release/AraneaDev/aranea-desktop?label=release)](https://github.com/AraneaDev/aranea-desktop/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/AraneaDev/aranea-desktop/ci.yml?label=CI)](https://github.com/AraneaDev/aranea-desktop/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/tests-19%20passing-2b8a3e)](tests/screenshot-coverage.test.sh)
[![Language](https://img.shields.io/github/languages/top/AraneaDev/aranea-desktop)](https://github.com/AraneaDev/aranea-desktop)
[![Last commit](https://img.shields.io/github/last-commit/AraneaDev/aranea-desktop?label=last%20commit)](https://github.com/AraneaDev/aranea-desktop/commits/master)
[![Conventional Commits](https://img.shields.io/badge/commits-conventional-fe5196?logo=conventionalcommits&logoColor=white)](https://www.conventionalcommits.org/)

[Omarchy](https://omarchy.org) · [AraneaDev](https://aranea-development.nl)

</div>

![Aranea desktop showcase](screenshots/hero-showcase.gif)

Static fallback: [desktop capture](screenshots/desktop.png) · [full showcase GIF](screenshots/hero-showcase.gif)

## What it feels like

Aranea Desktop is designed as one calm visual system rather than a collection
of unrelated tweaks:

- transparent, interactive shell bar with spider menu and native controls;
- obsidian surfaces with mint activity states and violet focus states;
- day, night, and atmospheric wallpaper variants built around edge topology;
- matching lock, idle, boot, terminal, editor, browser, cursor, and media art;
- optional diagnostics and application integrations that stay out of the way.

Aranea is still installed by Omarchy as the `aranea` theme, but the project is
larger than a theme: it combines the shell surface, custom plugins, artwork,
desktop integrations, cursors, Plymouth, installer, diagnostics, and showcase
tooling into one cohesive desktop experience.

The wallpaper is intentionally mark-free. The spider identity belongs to the
bar, menus, lock screen, boot splash, idle branding, and fastfetch surfaces.

## Install

From a checkout:

```bash
./scripts/install.sh
```

For a non-interactive full install:

```bash
./scripts/install.sh --yes
```

The installer installs Aranea Desktop, registers the `aranea` theme hooks, and
installs the managed integrations. On a full profile it also installs the
selected terminal integration (Alacritty, Kitty, or Foot) and offers the
optional Wayland Conky package when `paru` or `yay` is available. It does not
start Conky automatically.

Choose an installation profile when needed:

```bash
./scripts/install.sh --profile minimal --yes
./scripts/install.sh --profile full --yes
./scripts/install.sh --profile no_apps --yes
```

To install the exact checkout you are testing instead of fetching the default
remote repository, pass a local source explicitly:

```bash
./scripts/install.sh --source "$PWD" --yes --skip-conky
```

If installation fails after a previous theme was detected, the installer prints
the exact `omarchy theme set ...` command needed to restore it.

`minimal` keeps the core and GTK experience, `full` enables every supported
application integration, and `no_apps` keeps the theme, cursor, icon, wallpaper,
and branding assets without application integrations. The selected profile is
stored in `~/.local/state/aranea/profile`.

Preview or diagnose without changing the system:

```bash
./scripts/install.sh --dry-run --yes
./scripts/aranea-doctor --json
```

## Activate

After installation, select the theme and a wallpaper with Omarchy:

```bash
omarchy theme set aranea
./scripts/aranea-wallpaper list
./scripts/aranea-wallpaper set day
```

The wallpaper picker also exposes `night`, `sparse`, `dense`, `dusk`,
`monochrome`, and `ultrawide`. The bar remains transparent so the network art
can breathe behind it.

### Project layers

- **Theme layer:** Omarchy colors, wallpapers, GTK, terminal, cursor, lock, and Plymouth assets.
- **Shell layer:** Aranea bar, menu, lock, and notification plugins.
- **Integration layer:** browser, media, developer, Qt, session, and application styling.
- **Tooling layer:** installer, diagnostics, deployment helpers, screenshot capture, and validation.

The command menu uses a hybrid command-center layout: the root view adds
Aranea identity, fixed Files and Terminal tiles, and a favorite/recent action;
submenus retain a compact mark and breadcrumb. The primary, reduced, and
ceremony marks live under [`branding/marks`](branding/marks/aranea-primary.svg)
alongside their reduced and ceremony variants. Shared ready/active/attention
state glyphs and the menu’s network, node, and edge motifs live under
[`branding/glyphs`](branding/glyphs/ready.svg) and
[`branding/motifs`](branding/motifs/menu-network.svg).

## Artwork

### Desktop and shell

The hero above is the primary desktop view; the capture set below focuses on
interaction states rather than repeating the same wallpaper.

| Command center | Menu states | Shell telemetry |
| --- | --- | --- |
| ![Aranea command menu](screenshots/menu.png) | ![Aranea command menu — compact submenu](screenshots/menu-submenu.png) | ![Aranea diagnostics](screenshots/diagnostics.png) |
| ![Aranea command menu — search](screenshots/menu-search.png) | ![Aranea command menu — input](screenshots/menu-input.png) | ![Aranea notifications](screenshots/notifications.png) |

### System popups

| Network | Audio | Bluetooth |
| --- | --- | --- |
| ![Aranea network popup](screenshots/network.png) | ![Aranea audio popup](screenshots/audio.png) | ![Aranea Bluetooth popup](screenshots/bluetooth.png) |

| Agents | Power | Displays |
| --- | --- | --- |
| ![Aranea agent popup](screenshots/agents.png) | ![Aranea power popup](screenshots/power.png) | ![Aranea display popup](screenshots/monitor.png) |

### Wallpaper collection

The day/night pair anchors the collection. The variants keep the same fine silk
topology, edge-weighted composition, and quiet center while changing density,
color, contrast, or aspect ratio.

| Sparse | Dense | Dusk |
| --- | --- | --- |
| ![Sparse wallpaper](backgrounds/variants/sparse.png) | ![Dense wallpaper](backgrounds/variants/dense.png) | ![Dusk wallpaper](backgrounds/variants/dusk.png) |

| Monochrome | Ultrawide | Day / Night |
| --- | --- | --- |
| ![Monochrome wallpaper](backgrounds/variants/monochrome.png) | ![Ultrawide wallpaper](backgrounds/variants/ultrawide.png) | [Day](backgrounds/background-day.png) · [Night](backgrounds/background-night.png) |

### Secure and boot surfaces

![Aranea lock screen](screenshots/lock.png)

![Aranea Plymouth boot screen](screenshots/plymouth.png)

Apply the boot splash separately; rebuilding the initramfs requires `sudo`:

```bash
omarchy plymouth set-by-theme aranea
```

### Cursor artwork

| Pointer | Hand | Activity | Crosshair |
| --- | --- | --- | --- |
| ![Aranea pointer cursor](integrations/cursor/cursors/left_ptr.svg) | ![Aranea spider hand cursor](integrations/cursor/cursors/hand2.svg) | ![Aranea web activity cursor](integrations/cursor/cursors/watch.svg) | ![Aranea crosshair cursor](integrations/cursor/cursors/crosshair.svg) |

The busy cursor animation is shipped as eight matching SVG frames:

[`watch-01.svg`](integrations/cursor/cursors/watch-01.svg) ·
[`watch-02.svg`](integrations/cursor/cursors/watch-02.svg) ·
[`watch-03.svg`](integrations/cursor/cursors/watch-03.svg) ·
[`watch-04.svg`](integrations/cursor/cursors/watch-04.svg) ·
[`watch-05.svg`](integrations/cursor/cursors/watch-05.svg) ·
[`watch-06.svg`](integrations/cursor/cursors/watch-06.svg) ·
[`watch-07.svg`](integrations/cursor/cursors/watch-07.svg) ·
[`watch-08.svg`](integrations/cursor/cursors/watch-08.svg)

### Application surfaces

| Btop | File manager | Neovim |
| --- | --- | --- |
| ![Aranea btop](screenshots/btop.png) | ![Aranea file manager](screenshots/file-manager.png) | ![Aranea Neovim](screenshots/neovim.png) |

| Apps | Favorites | Recent |
| --- | --- | --- |
| ![Aranea Apps](screenshots/apps.png) | ![Aranea Favorites](screenshots/favorites.png) | ![Aranea Recent](screenshots/recent.png) |

Refresh the complete README capture set in one pass. Menu, desktop,
notification, diagnostics, and application surfaces are captured from the
running session, while lock and Plymouth use canonical artwork renders:

```bash
./scripts/capture-screenshots --all --output screenshots
```

Lock and Plymouth entries use canonical artwork renders, so refreshing the
capture set does not lock or reboot the session.

The repository also ships matching Cava, browser/session, Qt, media, cursor,
and icon integrations.

## Interaction

- Click the spider to open the Omarchy command menu.
- Right-click the spider to open a terminal.
- Click workspaces to switch sessions.
- Use the center indicators for idle and status controls.
- Use the right-side widgets for network, audio, Bluetooth, displays, power,
  tray, and agent controls.

The optional diagnostics layer can be toggled with:

```bash
aranea-diagnostics-toggle
```

The supplied Hyprland binding is `SUPER + CTRL + SHIFT + D`. It requires a
Wayland layer-shell Conky build such as `conky-cairo-wayland-git`.

## Palette

| Role | Value |
| --- | --- |
| Background | `#08090b` |
| Mint accent | `#3bff9e` |
| Violet accent | `#7a5cff` |
| Foreground | `#e7ecf3` |
| Muted foreground | `#8b96a6` |

The source tokens are in [`colors.toml`](colors.toml) and
[`shell.toml`](shell.toml). Wallpaper metadata and stable picker IDs are in
[`backgrounds/manifest.toml`](backgrounds/manifest.toml).

## Repository map

- `backgrounds/` — day/night artwork and the named wallpaper collection.
- `branding/` — identity marks, semantic glyphs, motifs, fastfetch, and idle artwork.
- `integrations/` — terminal, editor, browser, cursor, Qt, media, session, and
  icon integrations.
- `plugins/` — the Aranea bar, menu, lock, and notification surfaces.
- `hooks/` — theme activation and post-boot integration hooks.
- `scripts/` — installer, diagnostics, wallpaper, showcase, and health tools.
- `screenshots/` — representative captures used throughout this README.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for local git hooks, the test suite,
commit message conventions, and how releases are cut.

## License

See the repository's upstream project and asset licenses before redistributing
modified branding or wallpapers.
