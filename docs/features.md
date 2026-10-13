# Features

Aranea is designed as a system-wide visual language rather than a single bar
theme. The same identity appears in the shell, notifications, secure prompts,
wallpapers, cursors, icons, and application integrations.

## Command center

The bar opens an Omarchy command menu with Aranea identity, Files, Terminal,
and Projects tiles above a compact single-column list: Apps, Actions, Software,
Settings, Help, and System. Software groups Install, Remove, and Update; Settings
groups Aranea, Appearance, and Devices. The stock About slot is replaced by
Aranea, while the other menu IDs and searchable commands remain available. Apps keeps Favorites and Recent state in
`~/.local/state/aranea/menu.json`. The menu uses a compact network-and-node
motif and supports keyboard navigation and pinned applications. Typing at the
root searches apps, menu commands, windows, workspaces, projects, settings and quick actions.
Use `app:`, `command:`, `window:`, `workspace:`, `setting:`, `project:` or `action:` to restrict results.
Submenu searches stay scoped; Search everywhere or Ctrl+F keeps the query while
returning to root. Enter uses the selected current target, and a disappearing
window clears that selection. The list caps at 50 matches with a refinement hint.
Dmenu choices and input answers keep their existing behavior.

Quick actions toggle manual Do not disturb, select an available audio output, or
apply an installed wallpaper while keeping the menu open. Current choices, quiet
hours and active schedules are labelled; those schedules remain in place. Pending
changes wait for confirmation. Failed actions can be retried with Enter; Tab
reaches the offered audio controls or Appearance recovery destination. Missing
capabilities are omitted.

![Aranea command menu](../screenshots/menu.png)

![Unified desktop search with type labels](../screenshots/menu-search-mixed.png)

![Desktop quick actions](../screenshots/menu-search-actions.png)

## Network, Audio, and System

Network uses a linked-node bar icon and contains **Network**, **VPN**, and
**Bluetooth** tabs. `N`, `V`, and `B` switch pages; Bluetooth uses `T` for its
power toggle while hosted, so switching to the tab never changes hardware state.
VPN retains NetworkManager profiles, own-app profiles, connection controls,
session details, and traffic graphs.

Audio keeps output/input devices, per-app streams, volume, and mute controls in
one panel. Microphone mute is explicit in the input heading. A small microphone
badge appears only during an active capture stream; its muted/live appearance
reflects the source state. The hardware microphone mute key retains its normal
behavior.

System uses an adjustments icon with a small battery cue and optional percentage.
Its **Power**, **Display**, and **Health** tabs use `P`, `D`, and `S`. Power opens
by default, Display retains brightness, night light, keyboard light, scaling, and
monitor controls, and Health shows resources and actionable issues. System stays
reachable on machines without a battery. Child plugins retain their standalone
controls when the corresponding host is absent.

Notifications and Agents remain separate everyday bar controls. The tray stays
behind its disclosure. Usage provider selection is saved across shell restarts;
showcase choices do not overwrite it. Agents also offers local Tasks; reporting
is opt-in as described in the [workflow guide](workflows.md).

## Update center

The update center reports repository packages and AUR updates separately, plus
reboot-required state. Repository checks include Omarchy itself; the AUR check
runs when yay is present. Checks run at startup, hourly, and when the panel opens.
A source failure shows **Check failed** and retains the previous valid result.
Installation stays with Omarchy's native updater; **Software → Update** remains
available from the command center. See [update troubleshooting](troubleshooting.md#updates-appear-empty-or-stale).

## Notifications and health

Notifications go to the center instead of interrupting the desktop. Critical
items remain visible through a red indicator, while ordinary waiting items use
the mint badge. The health surface reports failed services, disk pressure,
reboot state, containers, CPU, memory, network, and process activity. Health lives
in **System → Health** (`S`), with an extra bar shortcut only while issues are
open or its alert popup is still visible. CPU, memory, and disk details start
expanded; Processes is optional. The issue list stays compact. Selecting an
issue opens diagnostics and deliberate recovery choices; intentionally stopped
containers can acknowledge that exact stop. See [Health recovery](troubleshooting.md#resolve-a-health-issue).

![Aranea notification center](../screenshots/notifications.png)

## Clipboard and emoji

The clipboard picker labels links, paths, colors, code, images, and text. It
keeps pinned entries above recent history and masks likely secrets. The emoji
picker keeps recent emoji close and supports insert versus copy actions.

![Aranea clipboard picker](../screenshots/clipboard.png)

## Secure prompts

The Aranea polkit surface gives privileged actions a consistent card with the
request, account, action details, and authentication state.

![Aranea authentication prompt](../screenshots/polkit.png)

## Wallpapers and motion

The collection contains thirteen distinct scenes, with **Signal Shrine** as the
default. **Aranea Core** also incorporates the spider; **Ghost in the Wire** is
the cybernetic portrait, and **Neural Deck** is the new command room. Other scenes
cover rain city, rail, rooftop, desert, market, motorcycle, ocean, and orbit.
The [catalog](configuration.md#wallpapers) maps human titles to stable IDs.
Twelve scenes have 3840×2160 exports; Orbital Relay has a 3840×1280 export. These
are resampled delivery sizes; original sources and prompts are in
[Artwork](../backgrounds/ARTWORK.md). The optional daily schedule lets you add, remove, and edit time/image entries
in **Settings → Aranea → Schedule**.
Motion can be enabled or disabled independently.

```bash
scripts/aranea-wallpaper list
scripts/aranea-wallpaper set signal-shrine
scripts/aranea-wallpaper schedule configure --entries '[{"time":"07:00","wallpaper":"day"},{"time":"21:00","wallpaper":"signal-shrine"}]'
scripts/aranea-wallpaper schedule on
scripts/aranea-motion status
```

## Integrations

The theme includes cursor, icon, terminal, browser, media, Qt, session,
developer, and application integrations. They are managed with backups and can
be inspected or toggled individually:

```bash
scripts/aranea-integrations status --json
scripts/aranea-integrations activate <id> --yes
scripts/aranea-integrations deactivate <id> --yes
```

## More surfaces

The repository also contains lock, Plymouth, Cava, cursor, icon, GTK, browser,
terminal, and media styling. The README contains the visual showcase; this
page explains what each surface is for.

## Desktop settings

**Command center → Settings → Aranea** opens a compact, centered Settings
window with Appearance, Display, Schedule, Integrations, and Notifications
destinations. Projects has its own top tile and independent manager. Appearance offers
searchable interface/monospace font choices with samples and explicit Apply;
icons keep their dedicated family. Appearance keeps its
wallpaper chooser collapsed until requested. Wallpaper selection and Display
presets edit local drafts, with explicit Apply and Discard. Display accepts
exact decimal scales and reports effective scale and persistence separately.
Drafts and scroll positions survive page navigation; long content scrolls
inside the window. Motion, integration and Do not disturb toggles keep their
immediate behavior.

## Project workspaces

**Command center → Projects** starts with **Choose folder**, or an absolute folder path.
Confirm the folder, review the discovered Git repositories and worktrees, select
checkouts, then **Add selected**. Discovery alone registers nothing. Related
worktrees share a project; each checkout retains its exact path and branch.
**Review ignored repositories** lets you restore a group for the next refresh.
Scanning runs only after a confirmed folder or explicit Refresh. A partial scan
keeps its results and explains how to choose a narrower folder.

Search project names, paths and branches with `project:`. **Open** uses saved
preferences and a dedicated workspace by default. **Resume** focuses freshly
verified project windows and opens missing tools when safe. **Customize** offers
an editor, terminal and an explicit current-workspace preference. Opening a
worktree separately preserves its separate workspace association. Occupied
workspaces and other checkouts' observed windows are preserved.

Project details show launch outcomes and role recovery. Retry targets a reported failed
role; an unconfirmed launch offers an explicit new window instead of an automatic
retry. A ten-second deadline can leave a partial result even when the application
started. Workspace titles, application classes and workspace membership alone
never establish ownership. The workspace overview shows project context only
when the current owner can justify it. A shell restart loses live bindings;
applications and repository files remain intact.

## Project commands and previews

Select a registered project and exact checkout in **Command center → Projects**, then use
**Actions** to add a named command or service. The form has a name, executable,
individual argument rows with Add/Remove controls, working folder (default `.`),
a command timeout and an optional service preview URL. Save and Cancel never run
the command. Definitions stay in local Aranea state; repository files are not
imported as executable configuration. Review the displayed command and folder,
then explicitly Run or Start. Opening/discovering a project, theme reload and
shell startup never execute saved actions.

Runs retain their accepted command and exact checkout. Refresh reads current
status; View logs loads selectable plaintext from the local journal. Stop cancels
only the proven owned run and its process group. Restart waits for confirmed
cleanup. If the command changed since that run, review the current action and use
Run/Start; the UI refuses an outdated restart. Conflicting edits keep the draft:
Refresh, review the latest saved definition, then explicitly Save draft over latest.

A command's exit status, service process state and preview reachability are shown
separately. Command success does not verify an agent task or the whole project.
A reachable URL does not prove which service owns its port. Open preview is an
explicit browser request for a currently owned running service. Focus project
reuses the existing workspace controls without launching an action.

The systemd user manager owns runs independently of the panel. Closing Projects,
reloading the shell, changing themes or closing the CLI observer does not cancel
them; reopen and Refresh the retained run. Services have no automatic restart or
login startup and do not promise to survive logout or reboot. A missing manager
makes execution unavailable while definitions remain editable. Uncertain starts
or cleanup stay protected until exact evidence is recovered. Logs follow system
journal retention, with at most 200 entries / 256 KiB displayed per read.

The same actions are available through the [public CLI](agent-interface.md#configured-project-actions-and-retained-runs).
Native manager/browser execution is separate from the sandboxed automated tests;
those tests do not run configured repository commands on the live desktop.
