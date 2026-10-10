# Aranea projects

`araneadev.projects` is the persistent owner of project workspace operations.
Its menu entry point, `Projects.qml`, stays loaded while registered in the
Omarchy shell. Settings, desktop search, the workspace overview and the CLI
consume its snapshots and results; they do not launch tools independently.
The plugin adds no bar widget.

## Commands and installation

From a checkout, run `./scripts/aranea`. After `scripts/install.sh`, run
`aranea` from the user executable directory: `${XDG_BIN_HOME:-$HOME/.local/bin}`.
Include that directory in your `PATH`, or invoke the command by its full path.
The owned symlink points to
`~/.config/omarchy/themes/aranea/scripts/aranea`, the stable installed theme.
Changing the active theme does not redirect the command to another theme's
scripts. Omarchy's installed-theme location is fixed; the user-bin location
honors `XDG_BIN_HOME`.

```bash
./scripts/aranea capabilities --json
aranea projects roots add ~/Work --json
aranea projects discover --json
aranea projects register --path ~/Work/my-project --json
aranea projects list --json
aranea projects open PROJECT_ID --json
aranea desktop status --json
```

Discovery scans only explicitly approved roots when requested. Registration
requires explicit repository selection. Ordinary Open never executes repository
scripts. Capabilities describes command arguments, supported installed tools,
required dependencies and live owner availability. Bash, Git, jq and flock
support the registry; live operations also require the owner and a supported
compositor session. Missing dependencies produce actionable errors; Node is
not an installed runtime requirement.

All installation profiles install the command when the theme scripts are
present. Full and no_apps use the existing shell deployment loop, which
deploys and registers the owner. Minimal retains the existing plugin deployment
policy; it does not independently guarantee a running owner. Registry commands
work without the live shell, and capabilities reports an absent owner as null.
Workspace opening and desktop status report the unavailable owner instead of
claiming successful live operations.

The installer follows the shared ownership ledger: an earlier user wrapper is
backed up on first adoption, repeated installs keep that original backup, and
user changes made after installation are preserved. Ownership recognizes only
the exact stable `scripts/aranea` target among script symlinks. Both uninstall
scopes restore an owned command's backup or remove the owned link, preserve
user replacements, and release the project plugin registration. A retained
replacement also retains its original backup under Aranea's ownership state.

## Tools and resume limits

Supported adapters are Visual Studio Code (`code`) and Neovim (`nvim`), with
Alacritty, Kitty, Foot or Ghostty terminals. Neovim opens through a supported
terminal. A missing tool or an unsupported configured default requires an
explicit choice; configuration is read as inert text and is never evaluated
as a shell command.

Dedicated workspaces are the default. Use `--use-current-workspace` explicitly
to choose the current workspace. Related worktrees are grouped; `--separate`
opens a checkout with a separate association. Open focuses bindings supported
by fresh ownership evidence or launches the missing roles. Application class,
window title or workspace membership alone does not establish ownership.

Each launch has a ten-second observation deadline. Acceptance alone is not
proof that a window opened; unconfirmed roles return a partial result and are
never automatically retried. Explicit `--retry-role` and `--new-window` choices
permit a later attempt. Resume restores supported workspace and tool windows;
it cannot reconstruct editor tabs, terminal commands or arbitrary application
session contents.

## Lifecycle and removal

Switching away from Aranea releases the owner registration through
`release-shell-config`. Returning reconciles deployment and restores exactly
one registration. Project records remain in
`${ARANEA_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/aranea}/projects.json`.
Applications are launched in detached sessions and survive shell reload,
theme switching and integration removal.

Runtime bindings and operation history belong to one shell session. A restart
creates a new session and invalidates those bindings. Disconnecting a CLI
observer does not cancel accepted work: `aranea projects operation OPERATION_ID`
can reconnect within the same session while the result is retained. The owner
keeps the latest 100 completed operations and all pending operations. A result
lost across restart cannot be resumed or automatically resubmitted.

`scripts/uninstall.sh --scope integration` and `--scope complete` both remove
Aranea project registrations and state. Integration removal keeps the installed
theme; complete removal also removes that theme through Omarchy. Neither scope
deletes registered repository folders or kills applications opened from them.
`aranea projects remove PROJECT_ID` removes only that registration, leaving its
repository and running applications intact.

## Validation

Run `tests/run install uninstall shell-config shell-deploy application-integrations`.
These tests use sandbox HOME/XDG directories, temporary repositories and fake
applications; they do not install into the active desktop.

## Named actions and tracked runs

Settings project details include Actions for the selected exact checkout. Save a
name, executable, separate argument fields, working folder, Command/Service kind,
command timeout and optional loopback preview URL. Save is inert; Run/Start is
explicit. Configuration lives in local `project-actions.json`, without repository
manifests, shell text splitting or runtime command overrides.

The action backend is headless and independent of this persistent workspace
owner. `ProjectActionsClient.qml` observes it only while the view is visible;
closing the view does not Stop a run. Systemd transient user services own the
process lifetime. They have no automatic restart or login startup; user-manager
shutdown/logout/reboot may end them. No additional persistent plugin is installed.

```text
aranea projects actions list PROJECT_ID --json
aranea projects actions run PROJECT_ID ACTION_ID --checkout CHECKOUT_ID --json
aranea projects runs list --project PROJECT_ID --json
aranea projects runs refresh RUN_ID --json
aranea projects runs stop RUN_ID --json
aranea projects runs logs RUN_ID --json
aranea projects runs open-preview RUN_ID --json
```

See the [full CLI/configuration contract](../../docs/agent-interface.md#configured-project-actions-and-retained-runs)
for configure examples, revision guards, Restart, capabilities and bounds.
UI Start/Restart guards the displayed revision; CLI Restart explicitly uses the
current saved action after confirmed exact Stop. Exit status, cleanup uncertainty
and preview reachability remain independent. Logs are bounded local-journal
plaintext; retention belongs to system policy.

Both uninstall scopes stop only proven owned action units before removing their
payload. A refused drain leaves recovery code and protected metadata intact and
reports failure. Successful removal preserves three stable coordination files
and required ancestor directories; reinstall fences older requests. Repository
folders, providers, editors and unrelated services remain untouched. Sandboxed
backend/CLI/UI tests use fake manager/browser boundaries; they do not validate
live native unit/browser behavior.
