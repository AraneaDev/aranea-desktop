# Aranea documentation

Start with your task. The user guides explain the desktop; the technical
references cover development and automation.

## Install and use

| I want to...                                          | Read                                  |
| ----------------------------------------------------- | ------------------------------------- |
| Install Aranea or change an existing installation     | [Getting started](getting-started.md) |
| Find a control or understand a panel                  | [Features](features.md)               |
| Set up a project, actions, or agent activity          | [Workflows](workflows.md)             |
| Change wallpapers, schedules, fonts, or integrations  | [Configuration](configuration.md)     |
| Browse desktop captures, screensavers, and wallpapers | [Gallery](gallery.md)                 |
| Resolve an issue or repair an installation            | [Troubleshooting](troubleshooting.md) |

For your first visit, install Aranea, open the command center from the spider,
and use **Settings → Aranea** for desktop preferences. **Network** holds Network,
VPN, and Bluetooth; **System** holds Power, Display, and Health. The full control
map is in Features.

## Develop and automate

| I want to...                                     | Read                                                           |
| ------------------------------------------------ | -------------------------------------------------------------- |
| Call the public CLI or consume structured output | [Agent interface](agent-interface.md)                          |
| Develop safely with a coding agent               | [Agent development](agent-development.md)                      |
| Edit, test, capture, or release the project      | [Development](development.md)                                  |
| Understand module ownership and dependencies     | [Architecture](architecture.md)                                |
| Follow the visual system                         | [Visual language](visual-language.md)                          |
| Browse available icons and fonts                 | [Icon gallery](icons.md) · [Bundled fonts](../fonts/README.md) |

## Where to run commands

Install the project from a Git checkout with `./installer`. The `scripts/`
helpers can be run from that checkout or from
`~/.config/omarchy/themes/aranea/scripts/` after installation. The installed
`aranea` command manages projects, actions, and opt-in local agent reporting.

Use [Agent interface](agent-interface.md) for exact command syntax, JSON
contracts, and exit codes. The process exit code determines whether an operation
succeeded; a visible result or event alone is not confirmation.

## Report a problem

Start with [Troubleshooting](troubleshooting.md) and `scripts/aranea-doctor`.
Include the installation profile, affected panel, and diagnostic output when
opening a [GitHub issue](https://github.com/AraneaDev/aranea-desktop/issues).
