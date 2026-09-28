# Configuration

## Profiles

Profiles control application integrations during installation:

| Profile | Includes |
| --- | --- |
| `minimal` | Core theme and GTK experience |
| `full` | All supported application integrations |
| `no_apps` | Theme assets, cursor, icons, wallpaper, branding |

The profile is persisted in `~/.local/state/aranea/profile` and read by the
theme hooks after activation.

## Wallpapers

List and select stable wallpaper IDs:

```bash
scripts/aranea-wallpaper list
scripts/aranea-wallpaper set day
scripts/aranea-wallpaper set ultrawide
```

The schedule uses four phase boundaries and can be inspected without changing
it:

```bash
scripts/aranea-wallpaper schedule status
scripts/aranea-wallpaper schedule configure 06:00 08:00 18:00 20:00
scripts/aranea-wallpaper schedule on
scripts/aranea-wallpaper schedule off
```

## Motion

```bash
scripts/aranea-motion status
scripts/aranea-motion set on
scripts/aranea-motion set off
scripts/aranea-motion toggle
```

Reduced-motion preferences should be respected by the host shell and compositor
configuration. The installer does not require motion to be enabled.

## Integrations

List integration IDs and states before changing one:

```bash
scripts/aranea-integrations status
scripts/aranea-integrations status --json
```

Activation backs up managed files before linking theme-owned content. On
uninstall, Aranea restores the saved originals unless the user changed the
managed file after installation; customized files are preserved and recorded
in the ownership ledger.

## State and backups

Aranea state normally lives under:

- `~/.local/state/aranea/` — profile, ownership ledger, backups, and saved settings;
- `~/.config/aranea/` — user-facing Aranea settings such as wallpaper schedule;
- `~/.config/omarchy/` — hooks, shell configuration, and deployed plugins.

Do not delete the ownership ledger while Aranea integrations are installed.
Use the uninstall command so restoration decisions remain safe.

## Environment variables

Useful overrides include:

| Variable | Purpose |
| --- | --- |
| `ARANEA_THEME_SOURCE` | Default source passed to the installer |
| `ARANEA_THEME_REPO_URL` | Default remote theme source |
| `ARANEA_INSTALL_PROFILE` | Profile read by activation hooks |
| `ARANEA_CLIPBOARD_SECRET_TTL_MS` | Clipboard secret retention time |
| `ARANEA_OSD_CAPTURE_COMMAND` | Live OSD capture command for showcase work |

Most scripts also expose `--dry-run`, `--json`, or `--help`. Prefer those
interfaces over relying on internal paths.
