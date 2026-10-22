<div align="center">

# Aranea Desktop

**A cyberpunk command center for Omarchy.**

A coordinated desktop with a command center, grouped controls, project tools,
thirty wallpapers, and six live screensavers. Obsidian, mint, violet, and the
Aranea spider carry through the desktop, lock screen, and boot splash.

[![Release](https://img.shields.io/github/v/release/AraneaDev/aranea-desktop?label=release)](https://github.com/AraneaDev/aranea-desktop/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/AraneaDev/aranea-desktop/ci.yml?label=CI)](https://github.com/AraneaDev/aranea-desktop/actions/workflows/ci.yml)
[![Language](https://img.shields.io/github/languages/top/AraneaDev/aranea-desktop)](https://github.com/AraneaDev/aranea-desktop)
[![Last commit](https://img.shields.io/github/last-commit/AraneaDev/aranea-desktop?label=last%20commit)](https://github.com/AraneaDev/aranea-desktop/commits/master)
[![Conventional Commits](https://img.shields.io/badge/commits-conventional-fe5196?logo=conventionalcommits&logoColor=white)](https://www.conventionalcommits.org/)

[Omarchy](https://omarchy.org) · [AraneaDev](https://aranea-development.nl)

</div>

![Aranea desktop showcase](screenshots/hero-showcase.gif)

[Install](#install) · [Explore](#explore-the-desktop) · [Screensavers](#screensavers) · [Gallery](docs/gallery.md) · [Documentation](#documentation)

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

## Explore the desktop

Click the **spider on the bar** to open the command center. Launch an app, open a
terminal or folder, or search with prefixes such as `app:`, `window:`, and
`project:`. Keyboard hints appear inside the menu and panels.

| Surface               | What you can do                                                                                                                    |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Clock**             | Open Calendar, World Clock, and Weather in one dropdown. Search for cities, view daylight on the globe, and choose your home city. |
| **Network**           | Manage Wi-Fi, wired connections, VPN profiles, and Bluetooth devices.                                                              |
| **Audio**             | Adjust outputs, microphones, and individual application streams.                                                                   |
| **System**            | Control power and displays, inspect resource usage, and open health diagnostics.                                                   |
| **Notifications**     | Read notification history and toggle Do Not Disturb.                                                                               |
| **Updates**           | Check repository and AUR packages, then install through Omarchy's native tools.                                                    |
| **Passwordless sudo** | Choose a duration and authenticate to enable it; click again to disable. White means enabled.                                      |

See [Features](docs/features.md) for the full control map and keyboard shortcuts.

### Personalize it

Open **Command center → Settings → Aranea** to choose a wallpaper, fonts, motion,
display scale, application integrations, notification preferences, or a daily
wallpaper schedule. **Silken Vault** is the default wallpaper; **Inter** and
**JetBrains Mono** are the default interface and technical fonts.

The collection includes thirty cyberpunk wallpapers, from city streets and
command rooms to ocean, orbit, and spider artwork. Browse them in the
[wallpaper gallery](docs/gallery.md#wallpapers) and use the
[configuration guide](docs/configuration.md) for preferences and schedules.

### Projects and agents

Open **Command center → Projects → Add project** to register a folder, discover
repositories and worktrees, and choose your tools. Return with **Open** or
**Resume**, or search with `project:`. Task checkouts provide separate working
copies. Project actions are commands and services you explicitly start, with
status, local logs, and Stop/Restart controls.

**Agents → Usage** shows provider usage; **Tasks** shows opt-in local Claude Code
and Codex activity. The [workflow guide](docs/workflows.md) covers projects,
actions, and agent adapters. The [agent interface](docs/agent-interface.md)
documents the public `aranea` CLI and structured output.

## Screensavers

Six live scenes share Aranea's dark, mint, violet, and restrained gold palette.
Three feature the rigged spider; three explore the same visual world without it.

| Scene            | Visuals                                                    | Spider |
| ---------------- | ---------------------------------------------------------- | ------ |
| **Silk Journey** | An articulated spider explores a moving, silk-lit chamber. | Yes    |
| **Neon Weaver**  | Luminous threads across dark cyberpunk architecture.       | Yes    |
| **Spiderfall**   | Silk descents through a shifting neon-lit vertical shaft.  | Yes    |
| **Kanji Drift**  | Layered kanji dissolve into drifting particles and reform. | No     |
| **Silken Flow**  | Luminous ribbons flow through mint and violet auroras.     | No     |
| **Neon Depths**  | A continuous journey through an evolving geometric city.   | No     |

Open **Settings → Aranea → Screensavers** to apply one scene or shuffle the
collection. **Preview** leaves your saved selection unchanged. Set the idle time
before the screensaver and before locking separately; scene selection and timing
have separate Apply controls. Move the pointer, click, or press a key to return.

The live scenes use local assets and a Chromium/WebGL renderer. Automatic
activation uses the managed session integration and Omarchy's idle service.
Stock Omarchy remains an automatic fallback; **Silk Chamber** is a standalone
experiment outside the picker.

See [screensaver setup and timing](docs/configuration.md#choose-screensavers-and-timing)
for requirements and behavior, or the [model and scene guide](branding/3d/README.md)
for standalone previews and asset development.

## Gallery

The hero above tours the desktop. Browse the [complete gallery](docs/gallery.md)
for panels, settings, projects, applications, the lock screen, boot splash,
[all six screensavers](docs/gallery.md#screensavers), and all thirty wallpapers. Desktop captures use **Silken Vault**; agent usage
captures use demonstration data.

[![Desktop with Silken Vault](screenshots/desktop.png)](docs/gallery.md)

## Documentation

Start at the [documentation hub](docs/README.md), or go directly to your task:

| Task                                            | Guide                                                                                                       |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Install, update, activate, or remove            | [Getting started](docs/getting-started.md)                                                                  |
| Learn controls and everyday workflows           | [Features](docs/features.md) · [Workflows](docs/workflows.md)                                               |
| Change settings, screensavers, and integrations | [Configuration](docs/configuration.md)                                                                      |
| Diagnose or repair an installation              | [Troubleshooting](docs/troubleshooting.md)                                                                  |
| Automate projects and local agent activity      | [Agent interface](docs/agent-interface.md)                                                                  |
| Browse the visual system and assets             | [Visual language](docs/visual-language.md) · [Fonts](fonts/README.md) · [Icons](docs/icons.md)              |
| Develop, test, capture, or release              | [Development](docs/development.md) · [Architecture](docs/architecture.md) · [Contributing](CONTRIBUTING.md) |

Helpers run from the checkout's `scripts/` directory or from the installed
`~/.config/omarchy/themes/aranea/scripts/` directory. The installed `aranea`
command manages projects, actions, and opt-in local agent reporting.

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
