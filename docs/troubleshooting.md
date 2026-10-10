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
