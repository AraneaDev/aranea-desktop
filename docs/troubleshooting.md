# Troubleshooting

## Start with the doctor

```bash
scripts/aranea-doctor
scripts/aranea-doctor --json
scripts/aranea-doctor --fix
```

The doctor checks the active theme, hooks, manifest, icons, ownership, shell
plugins, runtime logs, integrations, notifications, and optional tooling.
`repair` means a check needs attention; `skipped` usually means an optional
dependency is not installed.

## Aranea is not active

```bash
omarchy theme current
omarchy theme set aranea
scripts/aranea-doctor --fix
```

Switching themes intentionally hands host-owned surfaces back to Omarchy. Set
Aranea active again if you want its shell plugins and integrations restored.

## Hooks or plugins are stale

Run:

```bash
scripts/aranea-doctor --fix
omarchy restart shell
```

The repair path reinstalls the theme-set and post-boot hooks and reconciles
deployed plugins.

## The spider mark is missing

A blank bar icon, menu header or lock mark means the deployed plugins are
newer than the installed theme: they reference a branding file (for example
`branding/brand.svg`) the active theme does not have yet. The doctor's
`branding` check names the missing files, and `deploy-plugins-safely` warns
about them. Update the theme so both match:

```bash
scripts/install.sh --yes --profile "$(cat ~/.local/state/aranea/profile)"
```

## Installation failed

The installer reports the exact command for restoring the previously active
theme when it can detect one. Inspect a plan before retrying:

```bash
scripts/install.sh --dry-run --yes
scripts/aranea-doctor --json
```

If `jq` or `gum` is missing, install the missing Omarchy ecosystem dependency
or use the plain CLI without the TUI. JSON mode requires `jq`; the TUI requires
both `gum` and `jq`.

## Uninstall safely

Use integration scope first:

```bash
scripts/uninstall.sh --dry-run --scope integration --yes
scripts/uninstall.sh --scope integration --yes
```

Complete removal is explicit and also removes the installed theme directory:

```bash
scripts/uninstall.sh --scope complete --replacement-theme Omarchy --yes
```

The uninstall process restores files recorded by the ownership ledger and
preserves files that were customized after installation. Both scopes drain activity
writes and remove task/session state and owned heartbeat helpers. The inert
`agent-activity.json.lock` coordination file and its required parent directories
remain so delayed callbacks cannot recreate removed state. Normal installation
reactivates activity under that same lock; public reports cannot reactivate it.
If activity teardown cannot acquire its lock, uninstall reports failure instead
of claiming state removal succeeded.

## Find a control after bar consolidation

VPN and Bluetooth are inside **Network** (`V` and `B`). Brightness, night light,
keyboard light, and monitor controls are inside **System → Display** (`D`).
Resources and issues are inside **System → Health** (`S`). Audio contains both
output and microphone controls. A separate microphone indicator appears only
while a capture stream is active; a separate Health shortcut appears only for
issues or an open alert popup. Their absence is normal.

The linked-node icon opens Network; the adjustment-sliders icon opens System.
System remains available on machines without a battery. Standalone child widgets
are retained when their host is absent. If a tab is missing after an update,
run `scripts/aranea-doctor --fix` and restart the shell to reconcile the installed
plugins. Desktop preferences moved to **Command center → Settings → Aranea**;
search `aranea-settings` to reach the same window.

## Resolve a Health issue

Click the issue or select it with the keyboard and press Enter. The panel opens
a terminal with diagnostics for the exact service, container, filesystem, or
kernel update. Opening the resolver does not restart anything. Select the offered
recovery action and confirm it; successful actions trigger another Health check.
Disk actions inspect usage and open folders, without deleting files.

An intentionally stopped container may still be reported because it has a
nonzero recorded exit. In its resolver, choose `a` to acknowledge that stop.
Acknowledgment matches both the container ID and its stop timestamp. Restarting
it, replacing it, or stopping it again creates a different occurrence, so a later
failure remains visible. A changed container state refuses an old acknowledgment.
Memory-kill wording requires Docker's OOM evidence; exit code 137 or 143 alone
does not establish that cause.

Inspect or undo acknowledgments with the installed helper:

```bash
scripts/aranea-health-ack status
scripts/aranea-health-ack forget container:NAME
```

Active service, disk, and reboot issues must be resolved at their source. If an
issue remains after recovery, reopen it and inspect the fresh diagnostic output.
See the [Health plugin](../plugins/araneadev.health/README.md) for check details.

## Updates appear empty or stale

The update center now checks repository packages with `checkupdates --nocolor`
and AUR packages with `yay -Qua --color never` when yay is installed. Repository
results include Omarchy itself; a development checkout adds its native check.
It refreshes at shell startup, hourly, and when its panel opens. Update actions
still use Omarchy's native updater.

Read the same source results without installing packages:

```bash
scripts/aranea-update-status
```

A no-update exit is an empty successful result. Missing tools, network failures,
or malformed output are errors: the panel shows **Check failed** and keeps its
last valid status rather than replacing it with a false zero. Check the returned
`error` field and the named package tool. The native updater's gcc14/gcc14-libs AUR
exclusions are also applied here. See [Updates](../plugins/araneadev.updates/README.md).

## Agents returns to the wrong provider

Selecting a Usage provider saves its stable ID in the Agents inline bar entry.
Codex stays selected across shell restarts; screenshot stand-ins never overwrite
the real choice. Read or change that selection with:

```bash
omarchy-shell omarchy.agents selection
omarchy-shell omarchy.agents select codex
```

`select` returns `unavailable` when the provider has not been discovered and
`refused` during an inert capture or active showcase. A preferred provider that
is currently unavailable falls back to a discovered provider for display while
retaining the preference. This choice controls Usage and its bar ring; it does
not enable task-reporting hooks. If selection still resets, update the deployed
Agents plugin and run the doctor before restarting.

## Collect useful information

For a bug report, include:

```bash
scripts/aranea-about
scripts/aranea-doctor --json
omarchy theme current
```

Also state the selected install profile, whether the problem survives a shell
restart, and whether it affects the live session or only an integration.

## Project actions unavailable or unconfirmed

Use `aranea capabilities --json` to inspect action execution, user-manager,
journal, preview-probe and opener availability. Execution needs a responsive
systemd user manager and systemd-run 254+. Definitions can be configured without
them. An absent executable or invalid checkout is a Start error; saving does not
install dependencies. Select the exact registered checkout and review the working
folder, which must resolve inside it.

Keep the reported run ID, then use:

```text
aranea projects runs inspect RUN_ID --json
aranea projects runs refresh RUN_ID --json
aranea projects runs logs RUN_ID --json
aranea projects runs stop RUN_ID --json
```

An observer timeout or closed panel does not cancel the command. Refresh the same
run instead of inventing a new request to work around uncertainty. Main-process
success with cleanup unconfirmed still protects the run: child processes may
remain. Identity mismatch refuses control of a replacement unit; do not infer
ownership from its name, PID or port. Restore manager access and retry exact-run
Refresh/Stop. An unresolved submission whose unit is absent can remain protected;
absence alone cannot prove it never launched.

Preview reachable is only HTTP reachability. Missing curl means unchecked;
missing xdg-open prevents opening. Logs are explicit local journal reads, capped
at 200 entries / 256 KiB, and may be truncated or unavailable under system journal
retention. Removing run metadata does not delete that journal.

`ACTION_CONFLICT` preserves an unsaved UI draft. Refresh and review the current
saved definition, then explicitly choose Save draft over latest. A run whose
accepted definition changed cannot use UI Restart; review the new action and
Run/Start it. CLI `projects runs restart` explicitly uses the current saved
command after confirmed Stop. Neither interface overrides argv at runtime.

If uninstall reports `action_teardown_failed`, it retains the installed command,
script code, registry and protected action payload before removing integrations.
Use the retained run ID with the commands above, then retry the same uninstall.
A draining state blocks new starts/configuration; reinstall activation also
refuses protected runs. Keep `project-actions.json` and both action lock files
intact during recovery. Corrupt state is preserved for repair, never silently
reset. Successful removal leaves `project-actions.json.lock`,
`project-actions.json.dispatch.lock`, and `agent-activity.json.lock` with their
necessary directories; these inert files fence delayed requests and are reused
by reinstall. Existing customized-file backups retain their normal protection.

Install and uninstall share the action dispatch mutex through deployment/removal.
`action_lifecycle_busy` means that lock is busy or its path is unsafe; the message
names the underlying code. A concurrent operation refuses before destructive
work. Wait for it to finish and retry, or repair the reported unsafe path without
deleting retained coordination files. Native desktop commands do not inherit the
mutex.
