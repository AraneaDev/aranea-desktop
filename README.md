<div align="center">

# Aranea Desktop

**A cyberpunk command center for Omarchy.**

Obsidian instruments, mint light, violet depth, animated controls, and
twenty distinct cyberpunk wallpapers. Signal Shrine brings the Aranea spider
to the desktop; the same identity carries through the command center, lock, and boot.

[![Release](https://img.shields.io/github/v/release/AraneaDev/aranea-desktop?label=release)](https://github.com/AraneaDev/aranea-desktop/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/AraneaDev/aranea-desktop/ci.yml?label=CI)](https://github.com/AraneaDev/aranea-desktop/actions/workflows/ci.yml)
[![Language](https://img.shields.io/github/languages/top/AraneaDev/aranea-desktop)](https://github.com/AraneaDev/aranea-desktop)
[![Last commit](https://img.shields.io/github/last-commit/AraneaDev/aranea-desktop?label=last%20commit)](https://github.com/AraneaDev/aranea-desktop/commits/master)
[![Conventional Commits](https://img.shields.io/badge/commits-conventional-fe5196?logo=conventionalcommits&logoColor=white)](https://www.conventionalcommits.org/)

[Omarchy](https://omarchy.org) · [AraneaDev](https://aranea-development.nl)

</div>

![Aranea desktop showcase](screenshots/hero-showcase.gif)

Static fallback: [desktop capture](screenshots/desktop.png) · [full showcase GIF](screenshots/hero-showcase.gif)

[Install](#install) · [Daily controls](#daily-controls) · [Projects and agents](#projects-and-agents) · [Gallery](#gallery) · [Documentation](#documentation)

## Install

Aranea runs on [Omarchy](https://omarchy.org). Clone the repository and open the
guided installer:

```bash
git clone https://github.com/AraneaDev/aranea-desktop.git
cd aranea-desktop
./installer
```

Choose **Install/update**, then a profile. The installer also offers diagnosis,
repair, and removal. It uses `gum` and `jq`, alongside Omarchy's own commands.

| Profile   | What you get                                                                                  |
| --------- | --------------------------------------------------------------------------------------------- |
| `full`    | The desktop and all supported application integrations. This is the CLI default.              |
| `minimal` | The core theme and GTK styling.                                                               |
| `no_apps` | The theme and GTK styling, plus cursor and icons, without the extra application integrations. |

For a direct installation or a preview:

```bash
scripts/install.sh --profile full --yes
scripts/install.sh --profile full --dry-run --yes
```

To update, run the installer again with your selected profile. See
[Getting started](docs/getting-started.md) for activation, local development
sources, the optional boot splash, and removal.

## Daily controls

Open the command center from the spider on the bar. **Files**, **Terminal**, and
**Projects** are the three top tiles. The list below groups applications,
actions, software management, settings, help, and system commands in one column.
Type to search; use a prefix such as `app:`, `window:`, or `project:` to narrow
results.

The right side of the bar groups related controls:

| Control           | Inside                                                           | Page shortcuts                               |
| ----------------- | ---------------------------------------------------------------- | -------------------------------------------- |
| **Network**       | Wi-Fi and wired connections, VPN profiles, Bluetooth devices     | `N` Network · `V` VPN · `B` Bluetooth        |
| **Audio**         | Output and microphone levels, devices, and application streams   | Keyboard controls follow the focused channel |
| **System**        | Power, display controls, and resource details with health issues | `P` Power · `D` Display · `S` Health         |
| **Notifications** | Notification history and Do Not Disturb                          | Controls shown in the panel                  |
| **Agents**        | Provider usage and reported local tasks                          | Usage and Tasks views                        |

A microphone badge appears during capture. Health adds a shortcut when an issue
needs attention; the app tray opens through its disclosure. Inside the command
center and panels, use the displayed keyboard hints to navigate and activate
controls.

For a tour of every surface, see [Features](docs/features.md). For step-by-step
use, start with [Workflows](docs/workflows.md).

### Make it yours

Open **Command center → Settings → Aranea**:

| Page              | Change                                               |
| ----------------- | ---------------------------------------------------- |
| **Appearance**    | Wallpaper, interface and technical fonts, and motion |
| **Display**       | The focused monitor's scale, including custom values |
| **Schedule**      | A daily list of wallpaper images and times           |
| **Integrations**  | Optional application styling                         |
| **Notifications** | Do Not Disturb and current notification preferences  |

Choose a wallpaper or font, then **Apply**. For a wallpaper schedule, **Add
entry**, choose its image and a unique 24-hour time, then **Save schedule**. Add or remove
entries as needed; the most recent entry stays active across midnight. Existing
schedules retain their choices.

The default fonts are **Inter** for the interface and **JetBrains Mono** for
technical text. Motion can be turned off. The wallpaper collection contains
twenty distinct scenes in obsidian, mint, and violet, with **Signal Shrine** as
the default. Signal Shrine and Aranea Core feature the spider, joined by Lunar
Weaver, Abyssal Sanctum, Ghost Weaver, Skyline Sentinel, and Frostbound Nexus.
Ghost in the Wire is the cybernetic portrait, and Neural Deck is the command room.

See [Configuration](docs/configuration.md) for saved preferences, display
behavior, and the wallpaper title/ID map.

### Health and updates

System's Health page opens with CPU, memory, and disk details expanded. Select an
issue to open its diagnostics and recovery options. A stopped container can be
acknowledged for that particular stop; later failures still appear.

The update center checks repository and AUR packages, including the installed Omarchy package, and hands installation to the native update tools. See
[Troubleshooting](docs/troubleshooting.md) when a check or recovery action needs
attention.

## Projects and agents

Open **Command center → Projects → Add project** to register a development
folder. Review discovered repositories and worktrees, choose your tools and
workspace preference, then use **Open** or **Resume** to return to a checkout.
Search with `project:` from the command center. The Projects help pages explain
the workflow offline.

Project **Actions** are saved commands or services that you start explicitly.
Their runs retain status and bounded local-journal output, with Stop/Restart and
an optional local preview. Registering or opening a project does not run its
repository scripts. Follow the [project workflow guide](docs/workflows.md) to
set up a project, tools, and actions. Task checkouts give each task its own
working copy, and Projects explains any problem in plain words with **Details**
and **Copy**.

**Agents → Usage** shows provider usage. **Tasks** shows opt-in local Claude Code
and Codex activity. Install an adapter only when you want local task reporting;
the [agent activity workflow](docs/workflows.md#connect-claude-code-or-codex) explains the
commands and controls. Live work and unanswered input remain distinct from
completed history that can be cleared.

## Gallery

The hero is a tour of the current desktop. Expand a collection below to inspect
individual surfaces or choose a wallpaper. Agent usage captures show Codex with
demonstration data; the desktop background is Signal Shrine.

<details>
<summary><strong>Desktop panels, settings, pickers, and applications</strong></summary>

### Desktop and settings

| Desktop                             | Appearance                                                                | Display scaling                                               |
| ----------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------- |
| ![Desktop](screenshots/desktop.png) | ![Appearance settings on the desktop wallpaper](screenshots/settings.png) | ![Display scaling settings](screenshots/settings-scaling.png) |

![Daily wallpaper schedule](screenshots/settings-schedule.png)

### Command center

| Menu                                  | System submenu                                  | Search                                      |
| ------------------------------------- | ----------------------------------------------- | ------------------------------------------- |
| ![Command menu](screenshots/menu.png) | ![System submenu](screenshots/menu-submenu.png) | ![Menu search](screenshots/menu-search.png) |

| Input                                     | Apps                          | Favorites and Recent                                                         |
| ----------------------------------------- | ----------------------------- | ---------------------------------------------------------------------------- |
| ![Menu input](screenshots/menu-input.png) | ![Apps](screenshots/apps.png) | ![Favorites](screenshots/favorites.png)<br>![Recent](screenshots/recent.png) |

### Health, notifications, and session

| Health                                   | Notifications                                   | Empty center                                                      |
| ---------------------------------------- | ----------------------------------------------- | ----------------------------------------------------------------- |
| ![System health](screenshots/health.png) | ![Notifications](screenshots/notifications.png) | ![Empty notification center](screenshots/notifications-empty.png) |

| Updates                                   | Workspaces                                        | System: Power                            |
| ----------------------------------------- | ------------------------------------------------- | ---------------------------------------- |
| ![Update center](screenshots/updates.png) | ![Workspace overview](screenshots/workspaces.png) | ![Power controls](screenshots/power.png) |

| Authentication                                   | Lock screen                          | Boot splash                                       |
| ------------------------------------------------ | ------------------------------------ | ------------------------------------------------- |
| ![Authentication prompt](screenshots/polkit.png) | ![Lock screen](screenshots/lock.png) | ![Plymouth boot splash](screenshots/plymouth.png) |

### Bar controls

| Network: Network                             | Network: VPN                         | Network: Bluetooth                               |
| -------------------------------------------- | ------------------------------------ | ------------------------------------------------ |
| ![Network controls](screenshots/network.png) | ![VPN controls](screenshots/vpn.png) | ![Bluetooth controls](screenshots/bluetooth.png) |

| Audio                                    | Agents: Codex                           | System: Display                              |
| ---------------------------------------- | --------------------------------------- | -------------------------------------------- |
| ![Audio controls](screenshots/audio.png) | ![Agent status](screenshots/agents.png) | ![Display controls](screenshots/monitor.png) |

| Tray menu                          | Tray management                                 | Filament OSD                         |
| ---------------------------------- | ----------------------------------------------- | ------------------------------------ |
| ![Tray menu](screenshots/tray.png) | ![Tray management](screenshots/tray-manage.png) | ![Filament OSD](screenshots/osd.png) |

| Calendar                           | Weather                             |
| ---------------------------------- | ----------------------------------- |
| ![Calendar](screenshots/clock.png) | ![Weather](screenshots/weather.png) |

### Projects

| Projects                              | Overview and Git                                                                  | Actions                                             |
| ------------------------------------- | --------------------------------------------------------------------------------- | --------------------------------------------------- |
| ![Projects](screenshots/projects.png) | ![Project overview with task checkouts and Git](screenshots/project-overview.png) | ![Project actions](screenshots/project-actions.png) |

| Plain problem with Details                                     | Quick switcher                                      |
| -------------------------------------------------------------- | --------------------------------------------------- |
| ![Plain problem with Details](screenshots/project-problem.png) | ![Quick switcher](screenshots/project-switcher.png) |

| Ready for review                                    | Preferences: a terminal and an agent, no editor             |
| --------------------------------------------------- | ----------------------------------------------------------- |
| ![Ready for review](screenshots/project-review.png) | ![Project preferences](screenshots/project-preferences.png) |

### Pickers and applications

| Clipboard                                      | Emoji                                   | Wallpaper picker                                  |
| ---------------------------------------------- | --------------------------------------- | ------------------------------------------------- |
| ![Clipboard picker](screenshots/clipboard.png) | ![Emoji picker](screenshots/emojis.png) | ![Wallpaper picker](screenshots/image-picker.png) |

| File manager                                  | Neovim                            | Btop                          |
| --------------------------------------------- | --------------------------------- | ----------------------------- |
| ![File manager](screenshots/file-manager.png) | ![Neovim](screenshots/neovim.png) | ![Btop](screenshots/btop.png) |

</details>

<details>
<summary><strong>All twenty cyberpunk wallpapers</strong></summary>

Twenty different scenes share obsidian, mint, and violet: alleys, command rooms,
rail, rooftops, desert, markets, a cybernetic portrait, open road, ocean, orbit, suspended gardens, and polar ice.
Human titles appear in the picker; stable IDs preserve selections and schedules.
See the [title/ID map](docs/configuration.md#wallpapers) and
[artwork sources and prompts](backgrounds/ARTWORK.md).

| Signal Shrine (default)                                  | Aranea Core                                          | Neural Deck                                      |
| -------------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------ |
| ![Signal Shrine](backgrounds/variants/signal-shrine.png) | ![Aranea Core](backgrounds/variants/aranea-core.png) | ![Neural Deck](backgrounds/variants/cockpit.png) |

| Rain City                                    | Silent Vault                                      | First Departure                                   |
| -------------------------------------------- | ------------------------------------------------- | ------------------------------------------------- |
| ![Rain City](backgrounds/background-day.png) | ![Silent Vault](backgrounds/background-night.png) | ![First Departure](backgrounds/variants/dawn.png) |

| Dead Frequency                                   | Black Signal                                     | Undercity                                    |
| ------------------------------------------------ | ------------------------------------------------ | -------------------------------------------- |
| ![Dead Frequency](backgrounds/variants/dusk.png) | ![Black Signal](backgrounds/variants/sparse.png) | ![Undercity](backgrounds/variants/dense.png) |

| Ghost in the Wire                                         | Violet Pursuit                                             | Deep Current                                           |
| --------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------ |
| ![Ghost in the Wire](backgrounds/variants/monochrome.png) | ![Violet Pursuit](backgrounds/variants/violet-pursuit.png) | ![Deep Current](backgrounds/variants/deep-current.png) |

| Orbital Relay                                        | Canopy Circuit                                             | Polar Freight                                            |
| ---------------------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------------- |
| ![Orbital Relay](backgrounds/variants/ultrawide.png) | ![Canopy Circuit](backgrounds/variants/canopy-circuit.png) | ![Polar Freight](backgrounds/variants/polar-freight.png) |

| Lunar Weaver                                           | Abyssal Sanctum                                              | Ghost Weaver                                           |
| ------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------ |
| ![Lunar Weaver](backgrounds/variants/lunar-weaver.png) | ![Abyssal Sanctum](backgrounds/variants/abyssal-sanctum.png) | ![Ghost Weaver](backgrounds/variants/ghost-weaver.png) |

| Skyline Sentinel                                               | Frostbound Nexus                                               |
| -------------------------------------------------------------- | -------------------------------------------------------------- |
| ![Skyline Sentinel](backgrounds/variants/skyline-sentinel.png) | ![Frostbound Nexus](backgrounds/variants/frostbound-nexus.png) |

See [Visual language](docs/visual-language.md) for the design system behind
these surfaces.

</details>

## Documentation

Start with the [documentation hub](docs/README.md), or go directly to your task:

| Task                                       | Guide                                                                     |
| ------------------------------------------ | ------------------------------------------------------------------------- |
| Install, update, activate, or remove       | [Getting started](docs/getting-started.md)                                |
| Use the desktop and project workflows      | [Features](docs/features.md) · [Workflows](docs/workflows.md)             |
| Set preferences and integrations           | [Configuration](docs/configuration.md)                                    |
| Diagnose or recover                        | [Troubleshooting](docs/troubleshooting.md)                                |
| Automate projects, agents, or installation | [Agent interface](docs/agent-interface.md)                                |
| Browse fonts and icons                     | [Bundled fonts](fonts/README.md) · [Icon gallery](docs/icons.md)          |
| Work on the code                           | [Development](docs/development.md) · [Architecture](docs/architecture.md) |

Helpers can be run from this checkout's `scripts/` directory or from the installed
`~/.config/omarchy/themes/aranea/scripts/` directory. The public `aranea` command
manages projects, actions, and local agent activity. See the automation guide for
JSON schemas and command examples.

### Get help

Run `scripts/aranea-doctor` for installation diagnostics. Its `--fix` option
repairs stale hooks and plugin deployment. For a
[bug report](https://github.com/AraneaDev/aranea-desktop/issues), include your
install profile, the affected surface, and the output of
`scripts/aranea-about` and `scripts/aranea-doctor --json`.

### Contribute

Read [Contributing](CONTRIBUTING.md) for checks, conventional commits, and
releases. The [development guide](docs/development.md) covers token generation,
focused tests, and screenshot capture. Aranea's identity and canonical spider
mark are fixed; user preferences live in Settings.

### License

Code is released under the [MIT License](LICENSE). Bundled fonts use the
[SIL Open Font License 1.1](fonts/README.md), with license texts in each family
directory. Check upstream project and asset licenses before redistributing
artwork.
