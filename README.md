<div align="center">

# Aranea Desktop

**A quiet, obsidian Omarchy desktop experience with a living network of light.**

Deep black surfaces, mint activity, violet focus, atmospheric wallpapers, and
the AraneaDev mark carried consistently from boot to desktop.

[![Release](https://img.shields.io/github/v/release/AraneaDev/aranea-desktop?label=release)](https://github.com/AraneaDev/aranea-desktop/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/AraneaDev/aranea-desktop/ci.yml?label=CI)](https://github.com/AraneaDev/aranea-desktop/actions/workflows/ci.yml)
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
- live system health in the bar and application integrations that stay out of the way.

Aranea is still installed by Omarchy as the `aranea` theme, but the project is
larger than a theme: it combines the shell surface, custom plugins, artwork,
desktop integrations, cursors, Plymouth, installer, system health, and showcase
tooling into one cohesive desktop experience.

The wallpaper is intentionally mark-free. The spider identity belongs to the
bar, menus, lock screen, boot splash, idle branding, and fastfetch surfaces.

## Install

For a guided human installation from this checkout, run:

```bash
./installer
```

The TUI supports install/update, profile selection, diagnosis/repair, and two
explicit removal choices: remove Aranea's integration while keeping the theme
directory, or remove everything including the installed theme. It uses the
same CLI operations documented below.

For direct CLI and agent use:

```bash
scripts/install.sh
scripts/install.sh --profile full --yes
scripts/install.sh --dry-run --yes
scripts/install.sh --json --yes --profile full
```

The installer installs Aranea Desktop, registers the `aranea` theme hooks, and
installs managed integrations. Aranea expects Omarchy. The TUI uses
[`gum`](https://github.com/charmbracelet/gum) and `jq`; JSON mode requires
`jq`.

After installation:

```bash
omarchy theme set aranea
scripts/aranea-wallpaper list
scripts/aranea-wallpaper set day
```

The wallpaper picker also exposes `night`, `dawn`, `sparse`, `dense`, `dusk`,
`monochrome`, and `ultrawide`. Aranea Pulse adds an opt-in four-phase schedule
and a filament OSD:

```bash
scripts/aranea-wallpaper schedule configure 06:00 08:00 18:00 20:00
scripts/aranea-wallpaper schedule on
scripts/aranea-integrations status --json
```

Integrations can be activated and rolled back individually with
`scripts/aranea-integrations activate <id> --yes` and
`scripts/aranea-integrations deactivate <id>`; managed files are backed up in
the Aranea state directory before changes are made.

## What you get

| Surface             | Experience                                                                                                                                                                                                                      |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Command center      | A compact Omarchy menu with Aranea identity, Files, Terminal, Setup, Favorites, and Recent                                                                                                                                      |
| Notifications       | A quiet center with critical-state emphasis instead of interruptive popups                                                                                                                                                      |
| System health       | Live CPU, memory, disk, network, process, service, reboot, and container status                                                                                                                                                 |
| VPN                 | Connect NetworkManager and app-based VPNs (OpenVPN, WireGuard, Azure VPN Client, GlobalProtect) from one dropdown; see [plugins/araneadev.vpn/README.md](plugins/araneadev.vpn/README.md) for the apps file and client installs |
| Clipboard and emoji | Fast pickers with secret masking, recent history, pinning, and keyboard actions                                                                                                                                                 |
| Secure prompts      | A consistent polkit card for privileged actions                                                                                                                                                                                 |
| Wallpapers          | Day, night, dawn, sparse, dense, dusk, monochrome, and ultrawide compositions                                                                                                                                                   |
| Integrations        | Cursor, icons, terminal, browser, media, Qt, session, developer, and application styling                                                                                                                                        |

## Showcase

### Command center

![Aranea command menu](screenshots/menu.png)

| System submenu                                  | Search                                      | Input                                     |
| ----------------------------------------------- | ------------------------------------------- | ----------------------------------------- |
| ![System submenu](screenshots/menu-submenu.png) | ![Menu search](screenshots/menu-search.png) | ![Menu input](screenshots/menu-input.png) |

### System surfaces

| Notifications                                   | Health                            | Authentication                            |
| ----------------------------------------------- | --------------------------------- | ----------------------------------------- |
| ![Notifications](screenshots/notifications.png) | ![Health](screenshots/health.png) | ![Authentication](screenshots/polkit.png) |

| Filament OSD                | Wallpaper picker                                  | Empty notification center                                   |
| --------------------------- | ------------------------------------------------- | ----------------------------------------------------------- |
| ![OSD](screenshots/osd.png) | ![Wallpaper picker](screenshots/image-picker.png) | ![Empty notifications](screenshots/notifications-empty.png) |

| Workspace overview                                | Update center                             |
| ------------------------------------------------- | ----------------------------------------- |
| ![Workspace overview](screenshots/workspaces.png) | ![Update center](screenshots/updates.png) |

### Pickers and application styling

| Clipboard                               | Emoji                            | File manager                                  |
| --------------------------------------- | -------------------------------- | --------------------------------------------- |
| ![Clipboard](screenshots/clipboard.png) | ![Emoji](screenshots/emojis.png) | ![File manager](screenshots/file-manager.png) |

| Neovim                            | Btop                          | Apps                          |
| --------------------------------- | ----------------------------- | ----------------------------- |
| ![Neovim](screenshots/neovim.png) | ![Btop](screenshots/btop.png) | ![Apps](screenshots/apps.png) |

### Wallpapers

| Day                                              | Night                                                | Dusk                                             |
| ------------------------------------------------ | ---------------------------------------------------- | ------------------------------------------------ |
| ![Day wallpaper](backgrounds/background-day.png) | ![Night wallpaper](backgrounds/background-night.png) | ![Dusk wallpaper](backgrounds/variants/dusk.png) |

The visual system is described in [Visual language](docs/visual-language.md).

### The full visual system

The showcase GIF is the quick impression; these are the individual interaction
states and application surfaces behind it.

| Network                                   | VPN                               | Audio                                 | Bluetooth                                     |
| ----------------------------------------- | --------------------------------- | ------------------------------------- | --------------------------------------------- |
| ![Network popup](screenshots/network.png) | ![VPN popup](screenshots/vpn.png) | ![Audio popup](screenshots/audio.png) | ![Bluetooth popup](screenshots/bluetooth.png) |

| Agents                                  | Power                                 | Displays                                  |
| --------------------------------------- | ------------------------------------- | ----------------------------------------- |
| ![Agents popup](screenshots/agents.png) | ![Power popup](screenshots/power.png) | ![Display popup](screenshots/monitor.png) |

| Tray menu                                | Tray manage                                       |
| ---------------------------------------- | ------------------------------------------------- |
| ![Tray menu popup](screenshots/tray.png) | ![Tray manage popup](screenshots/tray-manage.png) |

| Calendar                                 | Weather                                   | Wallpaper picker                                  |
| ---------------------------------------- | ----------------------------------------- | ------------------------------------------------- |
| ![Calendar popup](screenshots/clock.png) | ![Weather popup](screenshots/weather.png) | ![Wallpaper picker](screenshots/image-picker.png) |

| Lock screen                          | Plymouth boot screen                              | OSD                                  |
| ------------------------------------ | ------------------------------------------------- | ------------------------------------ |
| ![Lock screen](screenshots/lock.png) | ![Plymouth boot screen](screenshots/plymouth.png) | ![Filament OSD](screenshots/osd.png) |

| Sparse wallpaper                                     | Dense wallpaper                                    | Dawn wallpaper                                   |
| ---------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------ |
| ![Sparse wallpaper](backgrounds/variants/sparse.png) | ![Dense wallpaper](backgrounds/variants/dense.png) | ![Dawn wallpaper](backgrounds/variants/dawn.png) |

| Monochrome wallpaper                                         | Ultrawide wallpaper                                        | Desktop capture                     |
| ------------------------------------------------------------ | ---------------------------------------------------------- | ----------------------------------- |
| ![Monochrome wallpaper](backgrounds/variants/monochrome.png) | ![Ultrawide wallpaper](backgrounds/variants/ultrawide.png) | ![Desktop](screenshots/desktop.png) |

| Btop                          | File manager                                  | Neovim                            |
| ----------------------------- | --------------------------------------------- | --------------------------------- |
| ![Btop](screenshots/btop.png) | ![File manager](screenshots/file-manager.png) | ![Neovim](screenshots/neovim.png) |

| Apps                          | Favorites                               | Recent                            |
| ----------------------------- | --------------------------------------- | --------------------------------- |
| ![Apps](screenshots/apps.png) | ![Favorites](screenshots/favorites.png) | ![Recent](screenshots/recent.png) |

## Documentation

| You want to...                                           | Read                                       |
| -------------------------------------------------------- | ------------------------------------------ |
| Install, update, activate, or remove Aranea              | [Getting started](docs/getting-started.md) |
| See what the theme includes                              | [Features](docs/features.md)               |
| Configure profiles, wallpapers, motion, and integrations | [Configuration](docs/configuration.md)     |
| Rebrand the visual identity                              | [Rebranding guide](docs/rebranding.md)     |
| Repair an installation or recover safely                 | [Troubleshooting](docs/troubleshooting.md) |
| Automate the installer as an agent                       | [Agent interface](docs/agent-interface.md) |
| Browse the icon families                                 | [Icon gallery](docs/icons.md)              |
| Understand the design system                             | [Visual language](docs/visual-language.md) |

The [documentation hub](docs/README.md) is the best place to start when you
already know what kind of information you need.

## Helper scripts

The helpers are available as `scripts/<name>` from a checkout or as
`~/.config/omarchy/themes/aranea/scripts/<name>` after installation.

| Script                        | Purpose                                           |
| ----------------------------- | ------------------------------------------------- |
| `scripts/install.sh`          | Install or update Aranea with a selected profile. |
| `scripts/uninstall.sh`        | Remove the integration or complete installation.  |
| `scripts/aranea-doctor`       | Check or repair the installation.                 |
| `scripts/aranea-integrations` | Inspect and toggle supported integrations.        |
| `scripts/aranea-wallpaper`    | List, select, schedule, and animate wallpapers.   |
| `scripts/aranea-motion`       | Inspect or toggle Hyprland and shell animations.  |
| `scripts/aranea-about`        | Print version, active theme, and health summary.  |
| `scripts/aranea-showcase`     | List documented surfaces.                         |

The command menu keeps Favorites and Recent in `~/.local/state/aranea/menu.json`;
`Ctrl+P` pins the app under the cursor. The complete icon and mark inventory is
documented in [Icon gallery](docs/icons.md).

## Agent-friendly CLI

The CLI stays human-readable by default and emits JSONL when `--json` is
explicit:

```bash
scripts/install.sh --json --yes --profile minimal
scripts/uninstall.sh --json --yes --scope integration
scripts/aranea-doctor --json
```

Every JSON line is a versioned event with stable step IDs and the process exit
code remains authoritative. Read the complete contract in
[Agent interface](docs/agent-interface.md).

## Uninstall

Keep the theme directory and remove Aranea's integration:

```bash
scripts/uninstall.sh --scope integration --yes
```

Remove the integration and the installed theme directory:

```bash
scripts/uninstall.sh --scope complete --replacement-theme Omarchy --yes
```

Use `--dry-run` before either operation when inspecting an unfamiliar system.

## Repository

```text
backgrounds/       wallpapers and stable picker IDs
branding/          identity marks, glyphs, motifs, and idle artwork
integrations/      cursor, icons, terminal, browser, Qt, media, and session
plugins/           bar, menu, lock, notifications, health, pickers, and OSD
hooks/             theme activation and post-boot behavior
scripts/           installer, doctor, integrations, wallpaper, and tooling
tests/              shell, QML, JavaScript, asset, and screenshot contracts
```

## Interaction notes

The command menu keeps Favorites and Recent in `~/.local/state/aranea/menu.json`;
`Ctrl+P` pins the app under the cursor. Notifications go to the center rather
than interruptive popups. The center keeps up to 100 items for 7 days.

- critical notifications stay until dismissed.

The health surface reports failed services, disk pressure, reboot state, and
containers. An exit code of 137 or 143 is treated as a memory-kill signal only
when the container was stopped for that reason. Clipboard secrets are masked
and expire according to `ARANEA_CLIPBOARD_SECRET_TTL_MS`.

If the polkit prompt is disabled manually with
`omarchy plugin disable araneadev.polkit`, run `omarchy restart shell` so
Omarchy's fallback prompt can take over.

The project publishes its CI status from
`actions/workflow/status/AraneaDev/aranea-desktop/ci.yml`.

## License

The code is released under the [MIT License](LICENSE). Check the upstream
project and asset licenses before redistributing modified branding or artwork.
