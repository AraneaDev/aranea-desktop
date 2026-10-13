<div align="center">

# Aranea Desktop

**A cyberpunk command center for Omarchy.**

Obsidian instruments, mint light, violet depth, animated controls, and
thirteen distinct cyberpunk wallpapers. Signal Shrine brings the Aranea spider
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

## Quick start

Aranea Desktop expects an [Omarchy](https://omarchy.org) installation with
`omarchy` on `PATH`. From this checkout, open the guided installer:

```bash
./installer
```

Choose **Install/update** and a profile. The same operation is available directly:

```bash
scripts/install.sh --profile full --yes
```

| Profile   | Includes                                                               |
| --------- | ---------------------------------------------------------------------- |
| `minimal` | Core theme and GTK experience                                          |
| `full`    | Every supported application integration                                |
| `no_apps` | Theme, cursor, icons, wallpaper, and branding without app integrations |

The TUI also offers diagnosis/repair and removal. It requires
[`gum`](https://github.com/charmbracelet/gum) and `jq`; JSON CLI output requires
`jq`. Preview installation with `scripts/install.sh --dry-run --yes`.
To update, rerun the installer or the CLI command with your selected profile.
The saved profile lives in `~/.local/state/aranea/profile`.

Select a wallpaper and optionally apply the boot splash:

```bash
scripts/aranea-wallpaper list
scripts/aranea-wallpaper set signal-shrine
omarchy plymouth set-by-theme aranea
```

See [Getting started](docs/getting-started.md) for the full installation,
activation, and update workflow.

## Desktop experience

Aranea installs as the `aranea` theme and brings a consistent visual system to
the shell, applications, lock screen, and boot: obsidian surfaces, mint activity,
violet depth, and an interactive bar. The default Signal Shrine and Aranea Core
wallpapers incorporate the spider into the scene; menus, lock, boot, idle, and
fastfetch use the canonical mark.

- **Command center:** Files, Terminal, Projects, Favorites, Recent, and searchable apps.
- **Settings:** wallpaper, fonts, motion, display scale, schedule, integrations, and DND.
- **Project workspaces:** confirmed Git discovery, grouped worktrees, project search, and Open/Resume with saved tools.
- **Network:** Network, VPN, and Bluetooth tabs behind one linked-node control.
- **Audio:** output, microphone, devices, and app streams; a microphone badge appears during capture.
- **System:** Power, Display, and Health tabs behind one adjustments control.
- **Health and notifications:** expanded resource graphs, compact issue rows with guided recovery, processes, and a quiet notification center.
- **Pickers and prompts:** clipboard with secret masking, emoji, wallpapers, and consistent polkit authentication.
- **Application integrations:** cursor, icons, terminals, editors, browser, media, Qt, and session styling.

### Project workspaces

New to projects and agent tasks? Start with **Command center → Projects → Add project**.
The wizard guides you through registration, tools, workflow actions, and optional
agent reporting. The Projects **Help** destination and **How to use actions**
are available offline. See the [step-by-step user guide](docs/workflows.md).

Open **Command center → Projects**, confirm a development folder, review repositories and
worktrees, then **Add selected**. Search with `project:` to Open or Resume saved
tools. Dedicated workspace is the default; Project preferences makes current workspace an
explicit preference. Partial launches report each role and offer targeted recovery.
Repository scripts are never run by discovery or ordinary Open. Removing a
registration preserves folders and applications.

Project details also offer named **Actions**: configure an executable and individual
arguments, then explicitly Run a command or Start a service for the selected
checkout. Track exit status, Stop/Restart, view bounded local-journal output and
open an optional loopback preview. Saving, opening a project and reloading the
shell never run actions. Runs belong to the systemd user manager independently
of the panel; uncertainty remains visible and protected. See the
[action guide](docs/features.md#project-commands-and-previews) and
[CLI examples](docs/agent-interface.md#configured-project-actions-and-retained-runs).

See [Project configuration](docs/configuration.md) for supported tools,
folder relocation and workspace choices, and [the JSON interface](docs/agent-interface.md)
for automation. Inert showcase IDs are `projects-empty`, `projects-discovery`,
`projects-grouped`, `projects-partial`, `project-details`, `project-search` and
`project-launch-partial`; [development instructions](docs/development.md)
render them without user repositories or desktop operations.

### Local agent activity

Open **Agents → Tasks** for Claude Code and Codex task activity alongside Usage.
Reporting is opt-in: run `aranea agents adapter status claude` or
`aranea agents adapter status codex`, then copy the matching install command from
Tasks setup. Review provider hook trust and start a new native CLI session;
configured hooks alone do not prove observed activity. Register projects explicitly.

Needs input, Ready for review and Failed transitions receive quiet, coalesced
notifications respecting DND and quiet hours. Open task inspects current details;
resume remains an explicit action. Verification is independently reported, and
session focus reaches only a proven hosting terminal. Activity is local to this
machine. See [setup, CLI examples and limitations](plugins/araneadev.activity/README.md).

### Typography and settings

Open **Command center → Settings → Aranea**, or search for “settings”. Aranea uses
**Inter** for the interface and **JetBrains Mono** for technical text.
Appearance offers searchable font choices and preview samples, including
**IBM Plex Sans**, **Source Sans 3**, **Inter Display**, **Inter Variable**, and
**JetBrains Mono NL**. Apply saves a draft; resetting defaults also requires
Apply. Saved font choices are preserved, and icons keep their dedicated font.
The interface choice also follows through to GTK applications and Qt applications
using the GTK platform theme, including Files and the project folder chooser.
`omarchy display text size SIZE` controls the shared logical text size. Aranea
projects that size into desktop fonts without applying GTK's text multiplier
again; monitor scaling remains handled by the toolkits. Terminal font families
keep their own settings. Running Qt applications may need reopening to refresh
their cached desktop font; Aranea’s chooser follows changes live.
See [Bundled fonts](fonts/README.md).

Wallpaper selection requires Apply, and schedule drafts require Save. Custom
display scales from 1 to 4 apply to the focused display and show the observed
effective fraction. Quiet hours are read-only. See
[Configuration](docs/configuration.md) for settings, state, and integrations.

### Everyday controls

The command center has six sections: Apps, Actions, Software, Settings, Help,
and System. Software groups Install, Remove, and Update. Settings contains the
Aranea, Appearance, and Devices. Existing app, software, and device commands remain searchable.

The right side of the bar keeps five everyday controls: Notifications, Agents,
Network, Audio, and System. The app tray uses a disclosure, and a Health shortcut
appears when an issue needs attention. Network groups Wi-Fi, VPN, and Bluetooth;
System groups Power, Display, and Health. Standalone child controls remain
available when their parent control is absent.

| Control | Pages and shortcuts                                                           |
| ------- | ----------------------------------------------------------------------------- |
| Network | `N` Network, `V` VPN, `B` Bluetooth; `T` toggles Bluetooth on its hosted page |
| System  | `P` Power, `D` Display, `S` Health                                            |
| Audio   | Output and microphone volume, mute, devices, and app streams                  |

Health opens with its CPU trace and memory/disk details expanded. Click an issue
or press Enter to open its diagnostics and recovery options. An intentionally
stopped container can be acknowledged for that specific stop; new failures still
appear. See [Health recovery](docs/troubleshooting.md#resolve-a-health-issue).

The wallpaper picker offers thirteen cyberpunk scenes. New additions are
Aranea Core and Signal Shrine with the spider, Violet Pursuit, and Deep Current.
[Preview the additions](screenshots/cyberpunk-additions.jpg). Existing wallpaper
IDs and day/night schedules remain stable. Signal Shrine is the theme default.
In **Settings → Aranea → Schedule**, add as many daily entries as you need,
choose an image and local time for each, then Save. Existing schedules are
preserved. The filament OSD follows the same palette:

```bash
scripts/aranea-wallpaper schedule configure --entries '[{"time":"07:00","wallpaper":"day"},{"time":"21:00","wallpaper":"signal-shrine"}]'
scripts/aranea-wallpaper schedule on
scripts/aranea-integrations status --json
```

Activate or roll back integrations individually with
`scripts/aranea-integrations activate <id> --yes` and
`scripts/aranea-integrations deactivate <id>`. Managed files are backed up in
the Aranea state directory before changes. For NetworkManager and app-based
VPN support, see the [VPN guide](plugins/araneadev.vpn/README.md).

`Ctrl+P` pins the app under the cursor in the command menu. Favorites and Recent
live in `~/.local/state/aranea/menu.json`. Notifications collect in the center
(up to 100 items for 7 days); critical notifications stay until dismissed. Clipboard
secrets are masked and expire according to `ARANEA_CLIPBOARD_SECRET_TTL_MS`.
Health treats container exit codes 137 or 143 as a memory-kill signal only when
the container was stopped for that reason.

If you manually disable the polkit prompt with
`omarchy plugin disable araneadev.polkit`, run `omarchy restart shell` so
Omarchy's fallback prompt can take over.

## Gallery

The hero shows a tour of the desktop. The captures below cover each showcase
surface once, including the current Network and System tabs and compact
Settings windows. The agent preview selects Codex. Captures use Signal Shrine
except for the separate wallpaper examples.

### Desktop and settings

| Desktop                             | Appearance                                       | Display scaling                                               |
| ----------------------------------- | ------------------------------------------------ | ------------------------------------------------------------- |
| ![Desktop](screenshots/desktop.png) | ![Appearance settings](screenshots/settings.png) | ![Display scaling settings](screenshots/settings-scaling.png) |

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

### Pickers and applications

| Clipboard                                      | Emoji                                   | Wallpaper picker                                  |
| ---------------------------------------------- | --------------------------------------- | ------------------------------------------------- |
| ![Clipboard picker](screenshots/clipboard.png) | ![Emoji picker](screenshots/emojis.png) | ![Wallpaper picker](screenshots/image-picker.png) |

| File manager                                  | Neovim                            | Btop                          |
| --------------------------------------------- | --------------------------------- | ----------------------------- |
| ![File manager](screenshots/file-manager.png) | ![Neovim](screenshots/neovim.png) | ![Btop](screenshots/btop.png) |

### Wallpapers

Thirteen different scenes share obsidian, mint, and violet: alleys, command rooms,
rail, rooftops, desert, markets, a cybernetic portrait, open road, ocean, and orbit.
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

| Orbital Relay                                        |     |     |
| ---------------------------------------------------- | --- | --- |
| ![Orbital Relay](backgrounds/variants/ultrawide.png) |     |     |

See [Visual language](docs/visual-language.md) for the design system behind
these surfaces.

## Documentation and support

Start at the [documentation hub](docs/README.md), or choose a guide:

| Task                                 | Guide                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------- |
| Install, update, activate, or remove | [Getting started](docs/getting-started.md)                                |
| Explore capabilities                 | [Features](docs/features.md)                                              |
| Configure settings and integrations  | [Configuration](docs/configuration.md)                                    |
| Diagnose and recover                 | [Troubleshooting](docs/troubleshooting.md)                                |
| Automate installation                | [Agent interface](docs/agent-interface.md)                                |
| Customize identity and artwork       | [Rebranding](docs/rebranding.md)                                          |
| Browse icons and typography          | [Icon gallery](docs/icons.md) · [Bundled fonts](fonts/README.md)          |
| Understand or contribute to the code | [Architecture](docs/architecture.md) · [Development](docs/development.md) |

For a problem, run `scripts/aranea-doctor`; `scripts/aranea-doctor --fix`
repairs stale hooks and plugin deployment. Include `scripts/aranea-about`,
`scripts/aranea-doctor --json`, your install profile, and whether a shell
restart changes the behavior in a [bug report](https://github.com/AraneaDev/aranea-desktop/issues).

## Helpers and automation

Run helpers from `scripts/` in a checkout, or from
`~/.config/omarchy/themes/aranea/scripts/<name>` after installation.

| Helper                                                        | Purpose                                                       |
| ------------------------------------------------------------- | ------------------------------------------------------------- |
| `scripts/install.sh` / `scripts/uninstall.sh`                 | Install, update, or remove Aranea                             |
| `scripts/aranea-doctor` / `scripts/aranea-about`              | Diagnose, repair, and summarize the installation              |
| `scripts/aranea-integrations`                                 | Inspect and toggle integrations                               |
| `scripts/aranea-wallpaper` / `scripts/aranea-motion`          | Select and schedule wallpapers; control animations            |
| `scripts/aranea-settings`                                     | Read versioned settings JSON or invoke existing helpers       |
| `scripts/install-fonts`                                       | Install bundled fonts and refresh the font cache              |
| `scripts/aranea-update-status`                                | Read repository/AUR update availability                       |
| `scripts/aranea-health-resolve` / `scripts/aranea-health-ack` | Diagnose an issue or manage stopped-container acknowledgments |
| `scripts/aranea-showcase`                                     | List documented surfaces                                      |

The installer, uninstaller, and doctor are human-readable by default. Their
explicit `--json` mode emits versioned JSONL events with stable step IDs; the
process exit code remains authoritative. Other status helpers and the public
project CLI return their documented JSON objects or arrays:

```bash
scripts/install.sh --json --yes --profile minimal
scripts/uninstall.sh --json --yes --scope integration
scripts/aranea-doctor --json
```

See [Agent interface](docs/agent-interface.md) for the complete contract.

## Removal

Keep the theme directory while removing Aranea's integration:

```bash
scripts/uninstall.sh --scope integration --yes
```

Remove the integration and installed theme directory:

```bash
scripts/uninstall.sh --scope complete --replacement-theme Omarchy --yes
```

Use `--dry-run` to preview either operation. Bundled fonts remain installed
for documents and applications that selected them.

## Development

Run the repository quality gates and refresh the complete showcase with:

```bash
tools/check
scripts/capture-screenshots --all --output screenshots
```

See [Development](docs/development.md) for the repository map, focused tests,
design token generation, capture fixtures, and upstream tracking, and
[Contributing](CONTRIBUTING.md) for contribution and release conventions.

## License

Code is released under the [MIT License](LICENSE). Bundled fonts use the
[SIL Open Font License 1.1](fonts/README.md), with license texts in each family
directory. Check upstream project and asset licenses before redistributing
modified branding or artwork.
