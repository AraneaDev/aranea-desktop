# Configuration

## Aranea settings

Open **Setup → Aranea settings**, or search for “settings” in the menu.
The centered window uses a compact 840×460 logical size capped to the screen,
with scrolling for longer pages. It covers wallpaper selection and explicit Apply, motion,
custom display scaling, wallpaper schedule enablement and validated Save, integration activation, and
Do not disturb. Navigation and thumbnail selection never change preferences.
Appearance includes searchable **Interface font** and **Monospace font**
choices for Aranea panels and controls. Samples preview each draft; **Apply**
saves both choices and updates open surfaces. **Reset to defaults** edits the
draft and also requires Apply. Icon glyphs retain their dedicated font.
Preferences live in `~/.config/aranea/fonts.json`; changing these choices does
not replace the native fonts used by applications or terminal content.

Appearance also shows the current wallpaper preview. **Choose wallpaper**
expands an inline chooser; thumbnail and label are one selection target.
**Apply** changes the desktop, while **Discard** restores the observed wallpaper.
Collapsing the chooser and navigating retain drafts and page scroll positions.

Reopening reads the existing CLI and service owners; closing leaves an active
integration installation running until its result is confirmed.

**Display** accepts decimal values from 1 to 4, including
`2.5` and `2.667`. Editing the field does nothing until **Apply**. Presets for 2x, 2.5x, 2.667x and 3x also edit only
the local draft. **Discard** restores the current observed scale.
The focused display and current effective scale are shown separately from your
entry. Omarchy adjusts fractions to clean logical pixels for the display mode;
for example, `2.667` on a 3840×2160 display can become about `2.666667`.
The typed request stays visible after applying; the
[scaling preview](../screenshots/settings-scaling.png) shows both values. See the
[Hyprland monitor contract](https://wiki.hypr.land/configuring/core/monitors/).

The existing `omarchy hyprland monitor scaling` helper owns display changes.
Standard generic Omarchy monitor configuration supports saving the scale;
custom monitor rules can leave a session-only change. Settings reports whether
saving is supported and whether literal persistence was confirmed, without
interpreting arbitrary Lua or creating a second display preference store.
A changed focused display or unconfirmed effective scale shows an actionable
error; review the current display before applying again. There are no automatic
retries. This control offers scaling only; the installed owner retains its
existing monitor-application behavior.

```bash
scripts/aranea-settings set display-scale 2.667 --json
# Optional stale-focus guard used by the UI:
scripts/aranea-settings set display-scale 2.5 --monitor eDP-1 --json
```

Schema version 1 retains its existing fields and adds optional `state.display`:
`monitor` (focused connector or null), `scale` (observed number or null), `width`
and `height` (observed mode or null), `availability` (`available` or
`unavailable`), `persistenceSupport` (`supported`, `unsupported`, or `unknown`),
and `configuredScale` (recognized literal number or null). An unavailable
scaling owner does not make other sections unavailable.

A dispatched scale mutation adds `result.displayScale`: `requested` (exact
string), `monitor` (original target), `width` and `height` (original mode),
`expectedScale` (owner's clean fraction), `effectiveScale` (observed target
scale or null), `confirmed` (boolean), and `persistence` (`persisted`,
`session-only`, or `unconfirmed`). `state.display` always describes the current
focused display, which can differ from that target on failure. Confirmation
checks exit status, identity, mode and effective scale; changed monitor config
is reloaded and checked with `hyprctl configerrors`. A successful-looking helper
message alone never confirms application. A later independent controller read
must still match the target before the UI reports Applied.

Quiet hours shows the effective state and configured window read-only. Set
`ARANEA_QUIET_HOURS` through your notification service configuration to change it;
settings does not write `notifications.json`. Bar layout and editable quiet hours are outside this release.

Direct destinations use the existing summon contract:

```bash
omarchy-shell shell summon araneadev.settings '{"section":"appearance"}'
omarchy-shell shell summon araneadev.settings '{"section":"display"}'
omarchy-shell shell summon araneadev.settings '{"section":"schedule"}'
omarchy-shell shell summon araneadev.settings '{"section":"integrations"}'
omarchy-shell shell summon araneadev.settings '{"section":"notifications"}'
scripts/aranea-settings status --json
```

Unknown sections open Appearance. Unavailable reads show Retry and disable
only the affected changes. Saved, deferred, failed, and confirmed Applied
outcomes remain distinct. Changes reuse the existing helper ownership and
backup behavior.

Installation and theme activation deploy and register `araneadev.settings`
when its manifest is present; repair adds it once and preserves other plugin
settings. Leaving Aranea releases the registration, and uninstall removes its
owned folder. It has no stock plugin replacement or bar icon. User-defined
`aranea.settings` menu entries take precedence over the generated route.

For display-only full-desktop captures, run `scripts/capture-screenshots --surface
settings --output screenshots` on one line. Use `settings-scaling` for Display.
These show the normal centered compact window with the bar and wallpaper. Capture
refuses an in-flight mutation, waits for an acknowledged inert fixture and ready
artwork, and restores prior visibility, section, drafts, scroll positions, showcase
state, workspace and focus. Preference mutations and owner refreshes are disabled.
The `--all` batch and hero include both frames after menu navigation.

Diagnostic variants `settings-narrow`, `settings-dirty`, `settings-unavailable`,
`settings-integration-failed` and `settings-notifications` render production content
offscreen with fixed fixtures and refuse reads and changes. The standalone
`tools/render-settings-preview --fixture scaling --output FILE` retains the cropped
Display diagnostic. Offscreen diagnostics do not summon the live desktop or change
notifications.

## Profiles

Profiles control application integrations during installation:

| Profile   | Includes                                         |
| --------- | ------------------------------------------------ |
| `minimal` | Core theme and GTK experience                    |
| `full`    | All supported application integrations           |
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

- `~/.local/state/aranea/`: profile, ownership ledger, backups, and saved settings;
- `~/.config/aranea/`: user-facing Aranea settings such as wallpaper schedule;
- `~/.config/omarchy/`: hooks, shell configuration, and deployed plugins.

Do not delete the ownership ledger while Aranea integrations are installed.
Use the uninstall command so restoration decisions remain safe.

## Environment variables

Useful overrides include:

| Variable                         | Purpose                                    |
| -------------------------------- | ------------------------------------------ |
| `ARANEA_THEME_SOURCE`            | Default source passed to the installer     |
| `ARANEA_THEME_REPO_URL`          | Default remote theme source                |
| `ARANEA_INSTALL_PROFILE`         | Profile read by activation hooks           |
| `ARANEA_CLIPBOARD_SECRET_TTL_MS` | Clipboard secret retention time            |
| `ARANEA_OSD_CAPTURE_COMMAND`     | Live OSD capture command for showcase work |

Most scripts also expose `--dry-run`, `--json`, or `--help`. Prefer those
interfaces over relying on internal paths.
