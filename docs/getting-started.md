# Getting started

Install Aranea on an existing Omarchy desktop, then choose your wallpaper and
preferences. The installer activates the theme and sets up its shell controls;
you do not need to copy plugin files by hand.

## Requirements

Use an Omarchy installation with `omarchy` available on `PATH`. The guided
installer requires `gum` and `jq`. Git is needed to download the theme; optional
application integrations apply to supported applications already installed.
Aranea does not install your editor, terminal, browser, or agent CLI for you.

## Install from a checkout

Download the repository and open it before running the installer:

```bash
git clone https://github.com/AraneaDev/aranea-desktop.git
cd aranea-desktop
./installer
```

Choose **Install/update**, then select a profile and review the confirmation.

| Profile   | Choose it when…                                                                                     |
| --------- | --------------------------------------------------------------------------------------------------- |
| `full`    | You want all supported integrations, including terminals and developer tools.                       |
| `minimal` | You want the core desktop and GTK styling.                                                          |
| `no_apps` | You want the core desktop, GTK, cursor, icons, and artwork without the additional app integrations. |

For a noninteractive installation, use:

```bash
scripts/install.sh --profile full --yes
```

The direct installer defaults to `full` with `--yes` or without an interactive
terminal. An explicit `--profile` makes your choice reproducible. The selected
profile is saved in `~/.local/state/aranea/profile`.

The installer normally downloads the public repository again. To install the
committed version in your local Git checkout instead, use:

```bash
scripts/install.sh --source "$PWD" --profile minimal --yes
# Or use the guided installer with that source:
ARANEA_THEME_SOURCE="$PWD" ./installer
```

Omarchy clones Git content: uncommitted working files are not included. You can
review the planned steps first with `scripts/install.sh --dry-run --yes`.

## Activate the theme

Installation already activates Aranea. When returning from another theme, run:

```bash
omarchy theme set aranea
```

**Silken Vault** is the default when there is no matching current background.
Choose another scene in **Command center → Settings → Aranea → Appearance**.
An enabled wallpaper schedule continues to choose its scheduled images.

The boot splash is optional and applied separately:

```bash
omarchy plymouth set-by-theme aranea
```

Aranea remembers this choice and restores the splash after an Omarchy update
resets it. Run `scripts/aranea-boot-splash off` to go back to the default splash.

## After installation

Click the spider button to open the command center. Its top tiles open **Files**,
**Terminal**, and **Projects**. Below them, **Apps**, **Actions**, **Software**,
**Settings**, **Help**, and **System** form a single list. Start typing to search,
or open **Settings → Aranea** for desktop preferences.

The right side of the bar brings related controls together:

| Control       | What you will find                                            |
| ------------- | ------------------------------------------------------------- |
| Network       | Network (`N`), VPN (`V`), and Bluetooth (`B`) tabs.           |
| Audio         | Output devices, microphones, per-app audio, volume, and mute. |
| System        | Power (`P`), Display (`D`), and Health (`S`) tabs.            |
| Notifications | Waiting notifications and Do not disturb.                     |
| Agents        | Local task reports and provider usage. Reporting is optional. |

The letter shortcuts work inside their panels. In Bluetooth, `T` toggles power.
A microphone badge appears during active capture; a separate Health shortcut
appears when issues need attention.

For a useful first check, run `scripts/aranea-doctor` from the checkout. Continue
with [Configuration](configuration.md) for wallpapers, fonts, and scaling, or
[Workflows](workflows.md) to register a project and run its tools.

## Update

From your checkout, run `./installer` and choose **Install/update**, or repeat
your direct install command with the profile you want. The default source is
the public repository; a local-source installation uses your local committed
content. Updates reinstall the theme as `aranea` and reconcile its hooks and
selected integrations.

Updating Aranea is separate from updating system packages. Use **Command center
→ Software → Update** for Omarchy's native updater.

## Remove

Run removal from the checkout. Integration removal restores managed settings
while keeping the installed theme directory:

```bash
scripts/uninstall.sh --scope integration --yes
```

For complete removal, select an installed replacement theme:

```bash
scripts/uninstall.sh --scope complete --replacement-theme Omarchy --yes
```

Replace `Omarchy` with your chosen installed theme if necessary. The guided
installer also offers both removal scopes. Aranea preserves managed files that
you changed after installation. See [Uninstall safely](troubleshooting.md#uninstall-safely)
if removal reports a retained run or another error.
