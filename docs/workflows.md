# Projects, workflow actions, and agents

Open **Command center → Projects** to keep a Git checkout, its tools, saved
commands, and local agent activity together. Projects opens its own window.
You can use it without enabling agent reporting.

Search the sidebar by project name, checkout path or branch; Ctrl+K focuses
search, arrows move through results and Enter selects. Pins appear first, followed
by recent projects. Narrow windows open a full searchable picker.
**Overview** leads with read-only Git state and brings services/checks, agents and
workspaces together. **Actions** contains saved commands and runs, **Agents** shows
reported tasks, **Preferences** controls tools and checkouts, **Profiles** holds reusable tool choices, and **Help** explains
setup. Leaving an editor offers **Save**, **Discard**, or **Keep editing**. Save
continues only after successful acknowledgement; a failed save retains the draft.
Closing the window retains drafts and does not cancel accepted operations.

## What belongs where?

| Item            | Meaning                                                                       |
| --------------- | ----------------------------------------------------------------------------- |
| Project         | A registered Git repository with saved tools and workspace preferences.       |
| Profile         | A named combination of supported tools, applied to your selected checkout.    |
| Environment     | One accepted profile start, its saved launch context and workspace.           |
| Checkout        | One working copy: a main repository checkout or a related Git worktree.       |
| Workflow action | A command you save and explicitly run, such as tests or a development server. |
| Agent task      | Activity reported by a local Claude Code or Codex session.                    |
| Usage           | Provider usage and limits, independent of task reporting.                     |

## Set up your first project

1. Open Projects and choose **Add project**.
2. Choose the exact Git repository, or enter its absolute path and choose
   **Add repository**.
3. Registration opens **Overview** immediately. Inspect Git state and choose
   **Start working** to use the remembered profile on the selected checkout.

Agent reporting and saved actions are optional. First-use profiles offer installed
tools without requiring agent setup.

Every registration (Projects, the CLI or a folder scan) saves default profiles
from the editors, terminals and agents installed on this computer, so **Start
working** is ready at once. Projects registered earlier without profiles get
them the first time you open them. If no supported editor or terminal is
installed, Projects says so; install one and choose **Refresh**.

For bulk discovery, choose **Scan development folder** from Add project. Approve
a parent folder, review discovered repositories and select **Add selected**.
Scanning alone registers nothing. This optional guide can walk through each
registered project's preferences and agent help; **Exit setup** keeps saved
registrations. Related worktrees remain grouped under one project.

To add repositories later, choose **Add project** again. **Preferences → Manage
development folders** opens discovery directly. **Scan again** refreshes a saved
folder. Review ignored repositories to restore them to discovery. Partial scans
can still offer usable results; narrow the folder if the scan reaches a limit.

## Start working and Return

Select a project and checkout to inspect them. **Start working** shows the remembered
profile name and tools. It starts that combination in an empty, unreserved workspace,
switches there, and dismisses Projects once this request is confirmed accepted.
Existing windows and environments stay open. Starting a profile never runs saved actions.

If the remembered profile can no longer start (for example its editor was
uninstalled), **Start working** uses the first saved profile that can and says
which one. Starting it makes it the remembered profile.

**Choose another profile** opens a searchable list. Selecting a profile starts it
immediately on the currently selected checkout; there is no extra confirmation.
The same checkout can have multiple independent environments. Each environment keeps
its launch-time profile name, tools, path and branch even if you later edit a profile.

Use **Return** on an environment in Overview or its desktop-search result to focus
that exact existing workspace. Projects closes only after focus is observed. Return
does not start missing tools or switch profiles. Saved metadata is unconfirmed after
a shell restart until fresh current-session ownership evidence is available.

If only some tools open, use the individual result's **Retry**, **Check … again**, or
explicit **New window** action. Those actions use the original environment and tools.
They do not restore terminal commands, editor buffers, or session contents.

**Launch status unknown** means an acknowledgement was lost; it is not proof of failure.
Use **Check launch status** first. **Start another environment** deliberately starts
new work with a new identity; the earlier request may still finish. A missing lookup
never automatically replays a start. **Cancel preparation** is available only while
the owner has explicitly refused acceptance; accepted or uncertain native work continues.

## Task checkouts

Give each piece of work its own checkout. Choose **New task checkout** in the
project header, type a branch name and choose **Create**. Aranea fetches, starts
the branch from the remote's default branch (or local `main`/`master` without a
remote) and creates the folder next to your repository as
`<repo>-worktrees/<branch>`. The new checkout is selected; press **Start working**
to open your tools there. A new task always starts from the main checkout, even
when a task checkout is selected.

When the work is merged, select the task checkout and choose **Remove task
checkout**. Aranea removes the folder only when it has no uncommitted or
untracked changes and no running action, and warns when commits are not on any
remote. It also warns when ignored files, such as `.env` or build output, will
be deleted with the folder. The branch is always kept. A commit on a detached
HEAD that is on no branch always blocks removal, and the removal card says so
before you confirm; create a branch for it first.
If you deleted a task checkout's folder by hand, **Remove task checkout** just
forgets it.

The **Git** section has **Fetch** and **Pull**. Pull only fast-forwards: when
branches have diverged or local changes would be overwritten, it changes
nothing and tells you to merge, rebase or commit in a terminal. Git never asks
for passwords here; if a remote needs credentials, run `git fetch` once in a
terminal. Your own `core.sshCommand` is honoured.

## Quick switcher

Press your quick switcher key, type part of a project name and press **Enter**.
If the project has open windows, Aranea takes you back to its workspace; if not,
it starts your remembered profile there, with the same checks as **Start working**.
**Alt+Enter** opens the full Projects window on that project without starting
anything. Each row shows what Enter will do before you press it.

Set the key in **Settings → Integrations → Quick switcher**: type the key you
want, then press **Add to bindings**. Aranea adds one marked line to your
`~/.config/hypr/bindings.lua`, checks that the key is free, keeps a backup
beside it as `bindings.lua.aranea.bak` and reloads Hyprland. If Hyprland reports
a new configuration error, Aranea puts your file back exactly as it was and
reloads again; errors that were already there do not stop the change. If another
change is still running, Aranea asks you to wait a moment and try again.
**Remove** takes the line out again. Aranea never changes your other bindings.
From a terminal, `aranea projects switch` opens the switcher.

## Review agent work

When an agent you connected finishes in a task checkout, the project shows
**Ready for review** at the top of that checkout's Overview, and the project
gets a **Review** marker in the sidebar and the quick switcher. The card lists
the commits and changed files since the branch started, any uncommitted
changes, what the agent reported about its checks, and the result of your own
check action (a saved command named like "test" or "check"; it reads "not run"
until you run it, and also when a run was stopped or could not be confirmed).
**Run checks** runs that action. **Open diff** opens your terminal with `git
diff` against where the branch started; it turns off external diff tools,
text conversion, the repository's pager and on-demand fetches, so settings in
the repository can't make it run other programs. **Push branch** pushes the
branch and sets its upstream (never forced). While the agent is still working
the checkout shows **Agent working**, or **Agent needs input** when it is
waiting for you.

Choose **Mark reviewed** when you are done; the card comes back when the agent
finishes another task, or when you open that checkout and it has new commits. Removing the task checkout ends the
review too. Reviews only appear for task checkouts, not your main checkout.
In the quick switcher, a project with work to review shows `Review · <branch>`,
and **Enter** opens that checkout's Overview without launching anything.

## When something goes wrong

Projects explains problems in plain words with at most two actions. **Starting…**
means Projects is still checking whether your tools opened; it checks a few
times by itself. If it still can't tell, choose **Check again**, or **Start
another** to deliberately open a second set. Projects never starts a second set
by itself.

Common problems: **Folder moved or missing** (choose **Locate folder**),
**Projects isn't running** (make sure Aranea is running, then **Retry**), **A tool
is missing**, **Changed elsewhere** (choose **Refresh**), **Busy right now**, and
**Git couldn't do that**, which keeps Git's own explanation.

Every problem has **Details** with the exact error code and message, and **Copy**
for bug reports or for pasting to an agent. The command line and
`aranea … --json` keep the original codes and messages.

## Advanced profile configuration

Use **Manage profiles** to name a profile and select its editor, terminal and optional
agent. Profiles contain tool choices, not checkout paths or arbitrary launch commands.
Choose your checkout in the project header. Missing providers are shown with a direct
setup/edit option, and saving a profile itself launches nothing.

Preferences still manages checkout locations and legacy ordinary Open defaults.
**Locate folder** repairs a moved checkout. Removing a profile or forgetting saved
environment metadata leaves existing windows in place. The public `projects open`
command retains its existing focus/reuse behavior for automation.

## Start an agent in a project

Choose a profile with an agent to use that profile’s saved or resolved terminal.
For a standalone agent, choose **Start … here** on an empty Agents page;
standalone agent starts use the terminal saved in Preferences.
In command-center search, try `claude <project>`,
`codex <project>`, or `agent <project>`.

Only installed providers are offered. The generic suggestion uses local usage
headroom and previous launch history; its reason appears beside the choice.
Choose the other provider explicitly whenever you prefer it. Starting an agent
does not refresh usage.

**Start** opens a new session. Legacy `projects open` with Agent enabled can
focus an existing verified agent window. If the result is unconfirmed, use the
recovery controls before starting another session.

The provider selected in the bar's **Agents → Usage** is a separate preference.
Changing it does not change project launch defaults or enable reporting.

## Example: run tests

Open the project's **Actions**. If the repository declares a test command,
it appears under **Found in this repo**: choose **Add**, then **Run**. To
enter one yourself, choose **Add action**; **Example: npm test** fills an
empty draft. Adapt it to your repository:

| Field          | Value                                        |
| -------------- | -------------------------------------------- |
| Name           | Run tests                                    |
| Executable     | `npm`                                        |
| Argument 1     | `test`                                       |
| Working folder | `.`                                          |
| Kind           | Command (runs to completion)                 |
| Timeout        | `300` seconds, or an appropriate test limit. |

Choose **Save**, then **Run** beside the saved action. Inspect status, exit code,
and **View logs** for output.

Each argument field is literal. For `npm run build`, use Executable `npm` and
separate arguments `run` and `build`. Do not paste the full command into
Executable. `.` means the selected checkout's root; `apps/web` means that
subfolder. Argument fields do not expand environment variables, pipes, or shell
operators. Choosing an example does not save, run, or overwrite an existing draft.

## Example: start a dev server

Detected dev servers appear under **Found in this repo** as services, with a
preview URL when the port is stated in the command or is the framework's
default. Choose **Add**, then **Start**. Otherwise choose **Add action**, then
**Example: npm run dev**, or enter:

| Field          | Value                                                                   |
| -------------- | ----------------------------------------------------------------------- |
| Name           | Dev server                                                              |
| Executable     | `npm`                                                                   |
| Arguments      | `run`, then `dev`, in separate fields.                                  |
| Working folder | `.`                                                                     |
| Kind           | Service (keeps running)                                                 |
| Preview URL    | Optional: `http://127.0.0.1:5173`, if that is the server's actual port. |

Choose **Save**, then **Start**. Read the output, use **Open preview** for the
saved URL, and **Stop** when finished. Preview URLs require a loopback host
(`127.0.0.1` or `[::1]`) and an explicit port. Services have no command timeout.
A reachable preview confirms HTTP reachability, not which process owns the port.

Runs continue after the panel closes or the shell reloads. Services have no
automatic restart or login startup; survival across logout or reboot is not
promised. **Stop** and **Restart** target the selected retained run. If submission
is unconfirmed, **Refresh** that run before starting another: it may already
have been accepted.

When an action changes, review the new definition and use **Run/Start**; the UI
will not restart an older run with a changed command. If a save conflicts with
another edit, refresh and review the latest definition, then explicitly choose
**Save draft over latest**. See [action recovery](troubleshooting.md#project-actions-unavailable-or-unconfirmed)
if execution or cleanup cannot be confirmed.

## Connect Claude Code or Codex

Register the exact checkout first. In a terminal, install reporting for the
provider you use:

```bash
aranea agents adapter install claude
# Or:
aranea agents adapter install codex
```

Review that provider's hook trust settings, then start a **new native CLI
session from the registered checkout** and perform some work. Existing
sessions may not load newly installed hooks. Installing hooks alone does not
confirm that reporting is trusted or working.

Check **Agents → Tasks** in the bar for activity across projects, or the
selected project's Agents page. The bar's **Agents → Help** provides reporting
and session guidance. Usage remains available separately.

| Task status                   | Next step                                                             |
| ----------------------------- | --------------------------------------------------------------------- |
| Working                       | Let it continue, or open the session to inspect its terminal.         |
| Needs input                   | Open the session and answer in the terminal.                          |
| Ready for review              | Open the checkout and inspect the reported changes.                   |
| Failed                        | Read diagnostics before deciding whether to resume.                   |
| Finished                      | Read the result and check reported verification separately.           |
| Connection lost / Unconfirmed | Check the terminal; this does not establish that the session stopped. |

**Details** shows the summary, exact checkout, report age, question or blockers,
result, and any separately reported verification. Finished does not imply tests
passed. Session focus reaches a verified hosting terminal, but cannot select a
particular tmux pane. **Reopen session** explicitly resumes a supported native
session; **Check session again** and **Reconnect** inspect an existing
operation without launching another.

In the bar's Agents panel, Tab switches Tasks, Usage, and Help. In Tasks, ↑↓ or
j/k moves the selection; the first Enter reveals the cursor and the next
confirms. Escape returns from details or closes the panel.

## If no tasks appear

Inspect provider setup:

```bash
aranea agents adapter status claude
aranea agents adapter status codex
```

Check that hooks are installed and trusted, the exact checkout is registered,
and the session was started after installation. Perform work that triggers a
report. Usage records do not produce tasks, and not every provider question
exposes a reporting hook. Unassigned tasks need an exact registered checkout
before project session controls are available.

To disable reporting, remove Aranea's hooks for your provider:

```bash
aranea agents adapter remove claude
aranea agents adapter remove codex
```

Other hooks are preserved. Activity stays local to this machine. See the
[activity interface](../plugins/araneadev.activity/README.md) for manual reports,
and [public project commands](agent-interface.md#public-project-commands) for
automation.
