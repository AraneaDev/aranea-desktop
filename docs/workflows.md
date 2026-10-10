# Projects, workflow actions, and agents

Start in **Setup → Projects → Set up a project**. The wizard guides you through
adding a Git checkout, choosing your tools, defining optional workflow actions,
and connecting agent reporting. **Projects help**, **How to use actions**, and
**Agents → Help** provide offline help inside the desktop.

## What belongs where?

| Feature         | Use it for                                                                             |
| --------------- | -------------------------------------------------------------------------------------- |
| Project         | A registered Git repository and its saved editor, terminal, and workspace preferences. |
| Checkout        | One working copy of a repository: the main checkout or a related Git worktree.         |
| Workflow action | A command you configure and explicitly run, such as tests, a build, or a dev server.   |
| Agent task      | Activity reported by a local Claude Code or Codex session.                             |
| Usage           | Provider usage and limits; available independently of task reporting.                  |

You can use projects and actions without enabling agent reporting.

## Set up your first project

1. Open **Setup → Projects** and choose **Set up a project**.
2. **Choose folder:** pick the exact Git repository folder or a development folder
   containing repositories. You can also enter an absolute path and choose
   **Use folder**. The saved folder is scanned for Git checkouts.
3. **Add repositories:** review the scan results. Select the checkouts you want,
   including any related worktrees, then choose **Add selected**. Selection and
   scanning alone do not register anything. Setup advances after registration
   succeeds. You can select several repositories in one batch; related worktrees
   are grouped into their project.
4. **Configure workflow:** review the project name, editor, terminal, and workspace
   preference. Choose **Use checkout** beside the working copy you want as the
   default. Choose **Save preferences** after editing. A dedicated workspace
   keeps the project's windows together; **Use current workspace** opens them
   on the workspace you are using. For a batch, **Project 1 of N** shows your
   position. **Next project** moves to the next repository; **Previous project**
   revisits one. Each project keeps its own preferences and workflow actions.
   Keep the current preferences and continue if you do not need customization;
   continuing does not save or run anything.
5. Optionally add test, build, or dev-server actions. Save or cancel any action
   draft before continuing. You can add actions later in **Preferences & actions**.
6. **Connect agents:** follow the reporting instructions for the provider you use,
   or skip this optional setup by choosing **Finish setup**. This stage appears
   after the last project. Install reporting once per provider, then start agent
   sessions from whichever registered checkout you want to work in.

**Exit setup** returns to project management. Changes already saved remain
registered. An existing unsaved project or action draft must be saved or discarded
before starting another setup.

To add more repositories later, use the wizard again. **Manage development folders**
opens the folder and discovery controls directly. **Scan again** refreshes the
results for a saved folder. A partial scan can still contain usable candidates;
choose a narrower folder if it reaches a limit.

## Open and resume a project

Choose **Open project** in Projects, or search for `project:` in the launcher.
Aranea uses the saved preferences and selected checkout, opening or focusing its
editor and terminal. Opening a project does not run workflow actions.

Use **Preferences & actions** to change the default checkout, tools, or workspace.
**Open separately** opens another registered checkout separately. **Locate folder**
updates a checkout's saved location after it has moved. Removing a development
folder does not remove its project registrations. **Remove registration** removes
only the saved project record; repository files and existing windows remain.

If only one tool opens, inspect the individual editor and terminal outcomes.
Use the offered **Retry**, **Check … again**, or **Open new … window** control for
that role. An unconfirmed result means observation is incomplete; it does not
prove that a tool failed to launch.

## Example: run tests

Open the project's **Preferences & actions**, then **Add action**. On an empty
new draft, **Example: npm test** fills the fields for you. Adapt it to the command
your repository actually uses:

| Field          | Value                                                |
| -------------- | ---------------------------------------------------- |
| Name           | Run tests                                            |
| Executable     | `npm`                                                |
| Argument 1     | `test`                                               |
| Working folder | `.`                                                  |
| Kind           | Command (runs to completion)                         |
| Timeout        | `300` seconds, or a limit appropriate for your tests |

Choose **Save**, then **Run** beside the saved action. Inspect the run for its
status, exit code, and output.

Each argument field is literal. For `npm run build`, use Executable `npm` and two
argument fields: `run` and `build`. Do not paste the full command line into the
Executable field. `.` means the selected checkout's root; `apps/web` runs from that
subfolder. Environment-variable expansion, pipes, and shell operators are not
interpreted in argument fields.

Choosing an example only fills an empty draft. It does not save or run anything,
and examples do not overwrite an existing draft.

## Example: start a dev server

Choose **Add action**, then **Example: npm run dev**, or fill in:

| Field          | Value                                                                 |
| -------------- | --------------------------------------------------------------------- |
| Name           | Dev server                                                            |
| Executable     | `npm`                                                                 |
| Argument 1     | `run`                                                                 |
| Argument 2     | `dev`                                                                 |
| Working folder | `.`                                                                   |
| Kind           | Service (keeps running)                                               |
| Preview URL    | Optional: `http://127.0.0.1:5173` if that is the server's actual port |

Choose **Save**, then **Start**. Inspect its output, use **Open preview** to open the
URL you supplied, and **Stop** when finished. Preview does not prove server
readiness. Preview URLs use a loopback host (`127.0.0.1` or `[::1]`) and an explicit
port. Services have no command timeout.

Runs continue when the panel closes. Saving an action, opening a project, and
reloading the shell do not start it. Stop and Restart target the selected run.
If submission is unconfirmed, refresh and inspect the retained run before
starting another; the first request may already have been accepted.

## Connect Claude Code or Codex

Register the exact checkout first. In a terminal, install reporting for the
provider you use:

```bash
aranea agents adapter install claude
```

For Codex:

```bash
aranea agents adapter install codex
```

Review your provider's hook trust settings, then start a **new native CLI session
from that registered checkout** and perform some work. Installing hooks alone
does not prove that they are trusted or that activity has been reported. Existing
sessions may not load newly installed hooks. Aranea does not start an agent when
you finish project setup.

Check **Agents → Tasks** for activity. **Agents → Help** explains setup, status,
session controls, and troubleshooting. **Usage** remains separate from reporting.

| Task status                   | Your next step                                                                     |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| Working                       | Let it continue, or Go to session to inspect the terminal.                         |
| Needs input                   | Open session and answer the agent in its terminal.                                 |
| Ready for review              | Open checkout and inspect the reported changes and result.                         |
| Failed                        | Inspect failure and its diagnostics before deciding to resume.                     |
| Finished                      | Read the reported result; check verification separately.                           |
| Connection lost / Unconfirmed | Check the terminal and observation state; this does not prove the session stopped. |

Open a task's **Details** for its full summary, exact checkout path, report age,
question or blockers, result, and independently reported verification. A finished
task does not imply tests passed. Session focus reaches a proven hosting terminal;
it cannot select a specific tmux pane. **Reopen session** explicitly resumes a
supported native session. **Check session again** and **Reconnect observation**
read the existing operation without launching another session.

**Keyboard:** Tab switches Tasks, Usage, and Help. In Tasks, ↑↓ or j/k moves;
the first Enter reveals the cursor, and the next confirms. Escape returns from
details or closes the panel. In Help, ↑↓ or j/k scrolls.

## If no tasks appear

Check provider availability:

```bash
aranea agents adapter status claude
aranea agents adapter status codex
```

Confirm that reporting hooks are installed and trusted, start a new native session,
and perform an action that triggers reporting. Usage history alone does not
produce task reports. Some providers do not expose every question hook; not every
prompt can be detected automatically. Unassigned tasks need an explicitly
registered project and exact checkout for session actions.

To turn reporting off, remove Aranea's owned hooks for the provider:

```bash
aranea agents adapter remove claude
aranea agents adapter remove codex
```

Other provider hooks are preserved. Activity is local to this machine. For manual
reports and automation, see the [activity interface](../plugins/araneadev.activity/README.md)
and [project CLI reference](agent-interface.md#public-project-commands).
