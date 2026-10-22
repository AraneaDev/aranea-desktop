# Configuration

Most everyday preferences are in **Command center → Settings → Aranea**. Use
this guide to change the desktop, choose integrations, and understand which
settings take effect immediately. Commands below run from a repository checkout;
`aranea` is the installed command used for projects and agents.

## Aranea settings

The settings window has six destinations:

| Destination   | Change                                          | When it takes effect                                                   |
| ------------- | ----------------------------------------------- | ---------------------------------------------------------------------- |
| Appearance    | Wallpaper.                                      | **Apply** commits the draft; **Discard** restores the observed choice. |
| Appearance    | Interface and monospace fonts.                  | **Apply** commits the draft; reset also requires Apply.                |
| Appearance    | Motion.                                         | Immediately.                                                           |
| Display       | Desktop scale.                                  | **Apply** commits the draft.                                           |
| Schedule      | Daily wallpaper entries.                        | **Save schedule** commits the draft.                                   |
| Schedule      | Enable or disable the saved schedule.           | Immediately.                                                           |
| Integrations  | Activate or deactivate a supported integration. | Immediately, after the operation completes.                            |
| Screensavers  | Scene or shuffle; idle and lock deadlines.      | **Apply scene** and **Apply timing** save independently.               |
| Notifications | Manual Do not disturb.                          | Immediately.                                                           |

Navigating between pages keeps your drafts and scroll positions. Unavailable
controls show an error and **Retry** without disabling unrelated preferences.
Closing the window does not cancel an accepted integration installation.

### Choose screensavers and timing

Open **Settings → Screensavers**, or search for **screensaver**, **shuffle** or
**lock** in the command center. Select a card to draft a single scene, or enable
**Shuffle Aranea scenes**; shuffle excludes Omarchy. **Apply scene** saves the
selection, while **Discard** restores the current owner choice. Unavailable scenes
cannot be selected. **Preview** never saves either draft and hides Settings when
the launch is accepted. Move the pointer, click, or press a key to dismiss the
preview. Launch acceptance is not a rendered-frame confirmation; reopen Settings
to read any startup error.

Both timing deadlines count from last activity. Set whole minutes from 1 to 1440
or explicitly choose **Disabled**. When both are enabled, lock must be later than
the screensaver. **Apply timing** saves only timing; **Discard timing draft**
restores the configured values. Existing precise seconds stay unchanged until
that field is edited, including when the other duration is saved. Non-minute
values are shown exactly in **Configured**, with the minutes field left blank
until edited. The initial 15/20-minute user configuration is preserved until save.

**Timing saved** confirms persistence and a successful shell reload request;
**Configured** describes saved values, not independently verified running timers.
If reload or readback fails, the draft and diagnostic stay visible for correction.
Stay awake and screensaver-off indicators explain pauses without toggling them.
Automatic activation requires the installed, reachable Aranea session integration.
A full install manages that launcher; enable the **Session** integration in Settings
if it is inactive. Omarchy's idle service remains responsible for activation and
locking. Stay awake or screensaver-off can pause automatic activation.

The initial catalog contains **Silk Journey** (local Chromium/WebGL), **Silk Chamber**
(local mpv video), and **Omarchy** (the packaged terminal saver). The owner uses
one selected scene across active monitors. Shuffle chooses from available Aranea
scenes once per automatic session, avoids the previous scene when possible, and
excludes Omarchy. Missing renderer dependencies disable only the affected scene.

Read selection, catalog availability, launcher reachability and configured timing
without launching a renderer:

```bash
scripts/aranea-screensaver status --json
scripts/aranea-screensaver list --json
```

Saved selection lives in `~/.config/aranea/screensaver.json`; timing stays in
Omarchy's `shell.json`. See the [session integration guide](../integrations/session/README.md#automatic-screensavers-and-timing)
for launcher ownership, fallback and reload behavior.

### Choose fonts

In Appearance, search **Interface font** and **Monospace font**, inspect the
samples, then choose **Apply**. **Reset to defaults** changes the draft and also
requires Apply. Defaults are **Inter** and **JetBrains Mono**. Icons keep their
dedicated font.

Aranea bundles Inter, Inter Display, Inter Variable, IBM Plex Sans, Source Sans
3, JetBrains Mono, and JetBrains Mono NL. The installer and theme activation
install these locally under `~/.local/share/fonts/aranea/`; saved choices are
preserved. You can also run `scripts/install-fonts` from the checkout. Bundled
fonts remain installed after removal for other documents and applications.

Preferences are stored in `~/.config/aranea/fonts.json`. They update Aranea's
interface and technical text; the interface family also updates GTK and
GTK-backed Qt desktop fonts. Reopen running Qt applications if needed. Terminal
font preferences remain under the terminal's own configuration.

### Change display scale

Open Display, review the focused monitor, enter a decimal scale from `1` to `4`,
and choose **Apply**. Presets such as `2.5` and `2.667` only fill the draft.
**Discard** returns to the currently observed scale.

The requested scale and effective scale can differ slightly: Omarchy adjusts
fractions to fit clean logical pixels. Settings reports whether the result was
saved or applies only to this session. Standard generic Omarchy monitor
configuration supports saving; custom monitor rules may allow only a session
change. If focus changes or the result cannot be confirmed, review the current
monitor and error before applying again.

For a direct request:

```bash
scripts/aranea-settings set display-scale 2.667 --json
```

This uses Omarchy's existing scaling helper. Other monitor controls remain in
**System → Display**. See the [settings CLI](agent-interface.md) for machine
readback and automation details.

### Notifications and quiet hours

Notifications offers manual Do not disturb and shows the configured quiet-hours
window. Quiet hours is read-only here; `ARANEA_QUIET_HOURS` is supplied through
the notification service's environment, using a window such as `22:00-07:00`.

For a combined settings readback, use:

```bash
scripts/aranea-settings status --json
```

## Bar and panel groups

The right bar groups controls into Notifications, Agents, Network, Audio, and
System, with a tray disclosure and a conditional Health shortcut.

| Panel   | Keyboard tabs                        | Other controls                                 |
| ------- | ------------------------------------ | ---------------------------------------------- |
| Network | `N` Network, `V` VPN, `B` Bluetooth. | `T` toggles Bluetooth power while hosted here. |
| System  | `P` Power, `D` Display, `S` Health.  | Available even without a battery.              |
| Audio   | Panel hints                          | Outputs, microphones, and per-app streams.     |

Standalone child controls remain available when their host panel is absent.
Use the [doctor](troubleshooting.md#hooks-or-plugins-are-stale) to repair stale
plugin deployment after an update.

Selecting a provider in **Agents → Usage** saves the selection across shell
restarts. This preference is separate from the agent you launch for a project
and from optional task reporting. The installed shell also exposes:

```bash
omarchy-shell omarchy.agents selection
omarchy-shell omarchy.agents select codex
```

### Command menu customization

Add or override menu entries in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`. Aranea merges this JSONC file
over Omarchy’s default menu, with later fields taking precedence for matching
item IDs. Changes are watched and apply without a shell restart.

Pinned and recently launched application IDs are stored in
`$XDG_STATE_HOME/aranea/menu.json` (normally
`~/.local/state/aranea/menu.json`). Use **Ctrl+P** on a selected application to
change its pinned state.

## Profiles

The installation profile selects integrations, rather than a different edition
of the desktop:

| Profile   | Included integration scope                                                                                          |
| --------- | ------------------------------------------------------------------------------------------------------------------- |
| `minimal` | Core desktop and GTK styling.                                                                                       |
| `full`    | Core and every supported integration, including terminals, developer tools, Qt, browser, session, and media assets. |
| `no_apps` | Core and GTK, plus cursor, icons, wallpapers, and Aranea artwork; excludes the additional app integrations.         |

Optional tools that are absent are skipped or retain their native fallback.
Profiles do not install those tools. All profiles install the public `aranea`
command and bundled fonts. The saved profile is in
`~/.local/state/aranea/profile`; change it through the installer when updating.

## Wallpapers

In Appearance, choose **Choose wallpaper**, select a thumbnail, then **Apply**.
Selection alone does not change the desktop. **Discard** restores the observed
wallpaper. Silken Vault is the default on a fresh application; an enabled
schedule continues to choose its images.

Displayed titles and stable CLI IDs are different:

| Title                  | Stable ID             |
| ---------------------- | --------------------- |
| Signal Shrine          | `signal-shrine`       |
| Aranea Core            | `aranea-core`         |
| Neural Deck            | `cockpit`             |
| Rain City              | `day`                 |
| Silent Vault           | `night`               |
| First Departure        | `dawn`                |
| Dead Frequency         | `dusk`                |
| Black Signal           | `sparse`              |
| Undercity              | `dense`               |
| Ghost in the Wire      | `monochrome`          |
| Violet Pursuit         | `violet-pursuit`      |
| Deep Current           | `deep-current`        |
| Orbital Relay          | `ultrawide`           |
| Canopy Circuit         | `canopy-circuit`      |
| Polar Freight          | `polar-freight`       |
| Lunar Weaver           | `lunar-weaver`        |
| Abyssal Sanctum        | `abyssal-sanctum`     |
| Ghost Weaver           | `ghost-weaver`        |
| Skyline Sentinel       | `skyline-sentinel`    |
| Frostbound Nexus       | `frostbound-nexus`    |
| Prism Weaver           | `prism-weaver`        |
| Forge of Silk          | `forge-of-silk`       |
| Basalt Covenant        | `basalt-covenant`     |
| Silken Vault (default) | `silken-vault`        |
| Orbital Sigil          | `orbital-sigil`       |
| Echo Basin             | `echo-basin`          |
| Glass Tide             | `glass-tide`          |
| Vector Garden          | `vector-garden`       |
| Midnight Switchyard    | `midnight-switchyard` |
| Quiet Singularity      | `quiet-singularity`   |

To list or select them directly:

```bash
scripts/aranea-wallpaper list
scripts/aranea-wallpaper set silken-vault
```

### Set a daily schedule

1. Open **Settings → Aranea → Schedule**.
2. Edit each row's local 24-hour time (`HH:MM`) and wallpaper.
3. Use **Add entry** or remove rows as needed. Keep at least one row and use
   unique times. An image can appear more than once.
4. Choose **Save schedule**, then enable the schedule if it is off.

Saving sorts entries by time and preserves the enable setting. Draft edits
leave the running schedule unchanged. **Discard** reloads saved entries.
The most recent transition determines the image: before today's first time,
the last entry from the previous day applies.

For example, Rain City at 07:00 and Signal Shrine at 21:00 keeps Signal Shrine
through the night until 07:00:

```bash
scripts/aranea-wallpaper schedule configure --entries '[{"time":"07:00","wallpaper":"day"},{"time":"21:00","wallpaper":"signal-shrine"}]'
scripts/aranea-wallpaper schedule on
scripts/aranea-wallpaper schedule status
scripts/aranea-wallpaper schedule off
```

Existing four-phase schedules load automatically. The legacy command remains
supported: `scripts/aranea-wallpaper schedule configure 06:00 08:00 18:00 20:00`
sets dawn/day/dusk/night transitions. New saves use version 2 JSON in
`~/.config/aranea/wallpaper-schedule.conf`.

## Motion

Use the Motion toggle in Appearance, or:

```bash
scripts/aranea-motion status
scripts/aranea-motion set on
scripts/aranea-motion set off
```

Motion is independent of wallpaper selection and scheduling.

## Integrations

Open **Settings → Aranea → Integrations** to inspect and toggle supported
integrations. For the same control from a checkout:

```bash
scripts/aranea-integrations status
scripts/aranea-integrations activate terminal --yes
scripts/aranea-integrations deactivate terminal --yes
```

Inspect the available IDs before changing one. Managed files are backed up
before theme content is linked. Restoration preserves files you customized
after installation. Some integrations supply assets or instructions for manual
use; browser profiles, for example, are not edited automatically.

## Projects

**Command center → Projects** manages registered Git checkouts, saved editor and
terminal choices, and workspace behavior. **Preferences** changes the selected
project; **Save preferences** commits changes. **Use checkout** selects its
preferred working copy. Dedicated workspaces are the default; using the current
workspace is an explicit preference.

Supported editors are VS Code (`code`) and Neovim (`nvim`); terminals are
Alacritty, Kitty, Foot, and Ghostty. Neovim opens in the selected terminal.
Choose installed supported tools; profile installation does not install them.

**Manage profiles** opens saved tool combinations. **Add profile** reveals usable
presets and custom tool selection; agents are optional. New UI registrations save
available presets after registration. Projects added through the CLI can use
**Set up a profile** whenever convenient. Editor-only and terminal-only profiles
work without an agent; Neovim and agent providers require a supported terminal.
**Refresh tools** rereads installed tools while retaining the current draft.

Profile edits and removals use saved revisions and leave running environments
unchanged. Leaving a profile editor offers **Save**, **Discard**, or **Keep
editing**; closing Projects retains the draft. Saving a profile configures tools
without launching them.

**Manage development folders** controls discovery. Removing a development
folder keeps existing registrations. **Locate folder** updates a moved checkout
while checking its Git identity. **Remove registration** removes saved metadata
and leaves repository files and running applications in place.

Follow [Workflows](workflows.md) for setup, actions, and agent reporting; use the
[project CLI reference](agent-interface.md#public-project-commands) for automation.

## State and backups

Default locations are:

| Location                 | Contents                                                                       |
| ------------------------ | ------------------------------------------------------------------------------ |
| `~/.config/aranea/`      | User preferences, including fonts and wallpaper schedule.                      |
| `~/.local/state/aranea/` | Profile, project registrations, retained runs, ownership records, and backups. |
| `~/.config/omarchy/`     | Installed theme, hooks, shell configuration, and plugins.                      |

XDG overrides can change these locations. Keep ownership records while
integrations are installed, and use the uninstall command for restoration.
Keep retained run state and lock files intact when troubleshooting interrupted
project actions; see [action recovery](troubleshooting.md#project-actions-unavailable-or-unconfirmed).

## Environment variables

Most users can keep the defaults. These overrides are useful for specific tasks:

| Variable                         | Purpose                                               |
| -------------------------------- | ----------------------------------------------------- |
| `ARANEA_THEME_SOURCE`            | Choose the installer's source checkout or URL.        |
| `ARANEA_THEME_REPO_URL`          | Override its default repository URL.                  |
| `ARANEA_INSTALL_PROFILE`         | Override the profile read by activation hooks.        |
| `ARANEA_QUIET_HOURS`             | Supply the notification service's quiet-hours window. |
| `ARANEA_CLIPBOARD_SECRET_TTL_MS` | Set clipboard secret retention time.                  |
