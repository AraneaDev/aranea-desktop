# Aranea Desktop

![Aranea Desktop](screenshots/desktop.png)

Aranea is a cinematic Omarchy desktop theme built around obsidian surfaces,
mint signal lines, violet identity, and quiet atmospheric wallpapers. It turns
the shell, notifications, health, secure prompts, cursors, icons, and
application styling into one coherent desktop.

> A calm control surface for a busy system.

[Install](#install) · [Explore the showcase](#showcase) · [Read the docs](#documentation) · [Contribute](CONTRIBUTING.md)

## Install

From a checkout, start the guided installer:

```bash
./installer
```

The TUI can install/update Aranea, select a profile, diagnose and repair the
installation, remove the integration, or remove everything including the
installed theme directory.

For direct CLI and agent use:

```bash
scripts/install.sh --profile full --yes
scripts/install.sh --dry-run --yes
scripts/install.sh --json --yes --profile full
```

Aranea expects Omarchy. The TUI uses `gum` and `jq`; the direct human CLI only
needs the dependencies required by the selected operation. JSON mode requires
`jq`.

After installation:

```bash
omarchy theme set aranea
scripts/aranea-wallpaper list
scripts/aranea-wallpaper set day
```

## What you get

| Surface             | Experience                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------ |
| Command center      | A compact Omarchy menu with Aranea identity, Files, Terminal, Setup, Favorites, and Recent |
| Notifications       | A quiet center with critical-state emphasis instead of interruptive popups                 |
| System health       | Live CPU, memory, disk, network, process, service, reboot, and container status            |
| Clipboard and emoji | Fast pickers with secret masking, recent history, pinning, and keyboard actions            |
| Secure prompts      | A consistent polkit card for privileged actions                                            |
| Wallpapers          | Day, night, dawn, sparse, dense, dusk, monochrome, and ultrawide compositions              |
| Integrations        | Cursor, icons, terminal, browser, media, Qt, session, developer, and application styling   |

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

## Documentation

| You want to...                                           | Read                                       |
| -------------------------------------------------------- | ------------------------------------------ |
| Install, update, activate, or remove Aranea              | [Getting started](docs/getting-started.md) |
| See what the theme includes                              | [Features](docs/features.md)               |
| Configure profiles, wallpapers, motion, and integrations | [Configuration](docs/configuration.md)     |
| Repair an installation or recover safely                 | [Troubleshooting](docs/troubleshooting.md) |
| Automate the installer as an agent                       | [Agent interface](docs/agent-interface.md) |
| Browse the icon families                                 | [Icon gallery](docs/icons.md)              |
| Understand the design system                             | [Visual language](docs/visual-language.md) |
| Develop, test, or refresh screenshots                    | [Development](docs/development.md)         |

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
| `scripts/capture-screenshots` | Refresh the README capture set and hero GIF.      |

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

## Development

```bash
tests/run json-events install uninstall doctor installer
tools/check
```

See [Development](docs/development.md) and [CONTRIBUTING.md](CONTRIBUTING.md)
for the full workflow.

## Complete surface gallery

The compact showcase above highlights the most useful views. The repository
also includes captures for every supported surface:

`screenshots/menu.png` · `screenshots/menu-submenu.png` ·
`screenshots/menu-search.png` · `screenshots/menu-input.png` ·
`screenshots/desktop.png` · `screenshots/health.png` ·
`screenshots/lock.png` · `screenshots/plymouth.png` ·
`screenshots/btop.png` · `screenshots/file-manager.png` ·
`screenshots/neovim.png` · `screenshots/notifications.png` ·
`screenshots/notifications-empty.png` · `screenshots/clipboard.png` ·
`screenshots/emojis.png` · `screenshots/polkit.png` ·
`screenshots/network.png` · `screenshots/audio.png` ·
`screenshots/bluetooth.png` · `screenshots/agents.png` ·
`screenshots/power.png` · `screenshots/monitor.png` ·
`screenshots/clock.png` · `screenshots/weather.png` ·
`screenshots/image-picker.png` · `screenshots/apps.png` ·
`screenshots/favorites.png` · `screenshots/recent.png` ·
`screenshots/dawn.png` · `screenshots/osd.png` ·
`screenshots/hero-showcase.gif`

Refresh them with:

```bash
scripts/capture-screenshots --all --output screenshots
```

Notifications go to the center rather than interruptive popups. The center
keeps up to 100 items for 7 days; critical notifications stay until dismissed.
The health surface reports failed services, disk pressure, reboot state, and
containers; an exit code of 137 or 143 is treated as a memory-kill signal only
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
