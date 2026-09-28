# Getting started

## Requirements

Aranea is an Omarchy theme and expects an Omarchy installation with `omarchy`
available on `PATH`. The guided installer also uses `gum` and `jq`.

## Install from a checkout

```bash
./installer
```

Choose a profile:

- `minimal` — core theme and GTK experience;
- `full` — every supported application integration;
- `no_apps` — theme, cursor, icons, wallpaper, and branding without app integrations.

The direct CLI is useful for scripts and agents:

```bash
scripts/install.sh --profile full --yes
scripts/install.sh --source "$PWD" --profile minimal --yes
scripts/install.sh --dry-run --yes
```

The selected profile is stored in `~/.local/state/aranea/profile`.

## Activate the theme

```bash
omarchy theme set aranea
scripts/aranea-wallpaper list
scripts/aranea-wallpaper set day
```

Apply the optional boot splash separately:

```bash
omarchy plymouth set-by-theme aranea
```

## Update

Run `./installer` and choose Install/update, or repeat the CLI install command.
The installer adopts the installed theme as `aranea` and re-registers the
hooks and selected integrations.

## Remove

Remove Aranea's integration while leaving the theme directory:

```bash
scripts/uninstall.sh --scope integration --yes
```

Remove the integration and the installed theme directory:

```bash
scripts/uninstall.sh --scope complete --replacement-theme Omarchy --yes
```

The TUI presents these as separate, clearly confirmed actions.

## After installation

Use `scripts/aranea-doctor` to inspect the installation. Use
`scripts/aranea-doctor --fix` to repair stale hooks and plugin deployment.

See [Configuration](configuration.md) for wallpapers, motion, integrations,
and state; see [Troubleshooting](troubleshooting.md) when something is wrong.
