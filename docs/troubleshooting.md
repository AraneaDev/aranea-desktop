# Troubleshooting

Start with the doctor, then follow the section matching what you see. The
`scripts/…` commands below run from your Aranea checkout; `aranea` is the
installed command for projects and agents.

## Start with the doctor

```bash
scripts/aranea-doctor
```

The doctor checks the active theme, hooks, assets, fonts, shell plugins, logs,
integrations, and optional tooling. **repair** identifies something needing
attention; **skipped** usually means an optional dependency is absent.

For machine-readable output or repair:

```bash
scripts/aranea-doctor --json
scripts/aranea-doctor --fix
```

`--fix` repairs hooks and reconciles plugin deployment. It does not replace a
missing theme update or install every optional application.

## Aranea is not active

Check the current theme and switch back:

```bash
omarchy theme current
omarchy theme set aranea
```

Switching away from Aranea releases its theme-owned shell surfaces. If returning
does not restore them, run `scripts/aranea-doctor --fix`.

## Hooks or plugins are stale

Repair deployment and restart the shell:

```bash
scripts/aranea-doctor --fix
omarchy restart shell
```

If the doctor reports missing theme assets, update the theme before retrying.
A shell restart also loses live project-window bindings; use the project's
explicit recovery controls if an existing window cannot be verified afterward.

## The spider mark is missing

A blank menu, bar, or lock mark can mean the deployed plugins expect artwork
missing from the installed theme. The doctor's `branding` check identifies
missing files. Update through `./installer` → **Install/update**, using your
preferred profile, then run the doctor again. Repairing hooks alone cannot add
artwork absent from an older installed theme.

## Installation failed

Read the failed step and any command offered to restore your previously active
theme. Inspect the plan before retrying:

```bash
scripts/install.sh --dry-run --yes
scripts/aranea-doctor --json
```

The guided installer needs both `gum` and `jq`. The direct CLI avoids the TUI,
but JSON mode and several supporting operations still need `jq`; a working
Omarchy installation must satisfy its own installer dependencies.

For a local-source installation, check that the source is a Git checkout with
the intended committed content. Uncommitted files are not included in the clone.
See [Getting started](getting-started.md#install-from-a-checkout) for the full
clone, directory, and install sequence.

## Uninstall safely

Preview integration removal, then run it:

```bash
scripts/uninstall.sh --dry-run --scope integration --yes
scripts/uninstall.sh --scope integration --yes
```

This keeps the installed theme directory. Complete removal also removes that
directory and selects an installed replacement theme:

```bash
scripts/uninstall.sh --scope complete --replacement-theme Omarchy --yes
```

Replace `Omarchy` with the theme you want to use. Restoration preserves managed
files you changed after installation. Use the uninstall command rather than
deleting its ownership records or theme directory manually.

Uninstall also stops owned project-action runs and removes task/session state.
If it reports `action_teardown_failed`, follow [project-action recovery](#project-actions-unavailable-or-unconfirmed)
with the retained command before retrying removal. Small inert lock files can
remain after successful removal; these prevent delayed requests from recreating
state and are reused on reinstall.

## Find a control after bar consolidation

| Looking for…                                      | Open                                   |
| ------------------------------------------------- | -------------------------------------- |
| VPN / Bluetooth                                   | Network → VPN (`V`) / Bluetooth (`B`). |
| Brightness, night light, keyboard light, monitors | System → Display (`D`).                |
| Resources or issues                               | System → Health (`S`).                 |
| Output or microphone controls                     | Audio.                                 |
| Wallpaper, fonts, scaling preferences             | Command center → Settings → Aranea.    |

Network has the linked-node icon; System has the adjustment-sliders icon.
System is available without a battery. The microphone badge only appears during
active capture; the separate Health shortcut only appears for issues or an open
alert popup. Their absence is normal. If a tab is missing after an update,
repair plugins and restart the shell as described above.

## Resolve a Health issue

1. Open **System → Health** and select the issue.
2. Read the diagnostics in the terminal that opens. Opening it alone performs
   no restart.
3. Choose an offered recovery action and confirm it. Successful recovery starts
   another Health check.
4. If the issue remains, reopen it and inspect the fresh output.

Disk actions inspect usage and open folders without deleting files. Active
service, disk, and reboot issues need resolution at their source.

An intentionally stopped container may still have a recorded nonzero exit. In
its resolver, `a` acknowledges that exact stop. A later stop or replacement
container is a new occurrence and can still appear. Exit code 137 or 143 alone
does not prove an out-of-memory kill.

Inspect or undo container acknowledgments:

```bash
scripts/aranea-health-ack status
scripts/aranea-health-ack forget container:NAME
```

See the [Health plugin](../plugins/araneadev.health/README.md) for check details.

## Updates appear empty or stale

Open the update center to trigger a fresh check. It also checks at startup and
hourly. Repository checks use `checkupdates`; AUR checks use `yay` when present.
A successful check with no updates is empty. Missing tools, network failures,
or invalid output show **Check failed** and retain the last valid result.

Read source results without installing packages:

```bash
scripts/aranea-update-status
```

Inspect the `error` field and named package tool. Installation still uses
**Command center → Software → Update**, Omarchy's native updater. For source
handling and exclusions, see [Updates](../plugins/araneadev.updates/README.md).

## Agents returns to the wrong provider

The Usage provider is saved independently of project launches and task hooks.
Inspect it or select an available provider:

```bash
omarchy-shell omarchy.agents selection
omarchy-shell omarchy.agents select codex
```

An unavailable preferred provider can temporarily fall back to one that is
available while keeping the saved preference. `select` reports `unavailable`
if the provider has not been discovered, or `refused` during an inert capture or
showcase. If the preference keeps resetting, update Aranea, run the doctor, and
restart the shell.

For missing tasks rather than Usage, follow
[If no tasks appear](workflows.md#if-no-tasks-appear).

## Project actions unavailable or unconfirmed

Use `aranea capabilities --json` to check execution, journal, preview, and opener
availability. Running actions requires a responsive systemd user manager and
`systemd-run` 254 or newer. Definitions remain editable when execution is
unavailable. Saving an action does not install its executable or dependencies;
select the exact checkout and review its working folder before starting it.

Keep the reported run ID and inspect that same run:

```bash
aranea projects runs inspect RUN_ID --json
aranea projects runs refresh RUN_ID --json
aranea projects runs logs RUN_ID --json
```

Replace `RUN_ID` with the retained identifier. A timeout or closed panel does
not cancel a command. Refresh before requesting another run: an unconfirmed
submission may already have started. If you need to stop it:

```bash
aranea projects runs stop RUN_ID --json
```

If cleanup remains unconfirmed, restore user-manager access and retry
**Refresh/Stop** for that exact run. Aranea refuses control when it cannot prove
ownership; a unit name, PID, or reachable port is not enough. Keep retained
`project-actions.json` state and its lock files intact during recovery.

| Message or symptom                      | Next step                                                                                            |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `ACTION_CONFLICT` while saving          | Refresh, review the saved definition, then explicitly choose **Save draft over latest**.             |
| Restart unavailable after an edit       | Review the current action and use **Run/Start**. The UI does not restart an older definition.        |
| Preview unchecked or cannot open        | Check `curl` and `xdg-open` availability, plus the saved loopback URL and port.                      |
| Logs truncated or unavailable           | Check local journal retention; the panel reads at most 200 entries / 256 KiB.                        |
| `action_teardown_failed` during removal | Use the retained command to refresh/stop its run, then retry the same uninstall.                     |
| `action_lifecycle_busy`                 | Wait for the concurrent install/removal to finish and retry; inspect any reported unsafe-path error. |

CLI restart explicitly uses the current saved definition after confirmed Stop.
A service's process state and its preview reachability are separate results.
See the [action CLI reference](agent-interface.md#configured-project-actions-and-retained-runs)
for detailed run states and recovery contracts.

## Collect useful information

Include these outputs in a bug report:

```bash
scripts/aranea-about
scripts/aranea-doctor --json
omarchy theme current
```

Describe the visible symptom, selected install profile, and steps to reproduce.
State whether a shell restart changes the result. For project issues, include
the exact checkout and retained run or request ID; review logs before sharing
any private paths or command output.
