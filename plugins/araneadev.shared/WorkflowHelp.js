/** Human-facing help for existing desktop workflows. */
/** @typedef {{title:string,body:string,command?:string}} HelpSection */

/** Return local, read-only help sections for one workflow.
 * @param {string} topic - projects, actions or agents
 * @returns {Array<HelpSection>} ordered steps and recovery advice
 */
function sections(topic) {
  if (topic === "projects")
    return [
      {
        title: "1. Add a project",
        body: "Choose Set up a project. Pick a repository folder or the development folder containing your repositories. Aranea scans for Git checkouts; review the results, select the checkouts you want, and choose Add selected. Select several repositories to configure them together in the wizard. Related worktrees share one project. Scanning alone adds nothing."
      },
      {
        title: "2. Choose how it opens",
        body: "A checkout is a folder containing one working copy of your repository. Related Git worktrees can belong to the same project. Choose the checkout, editor, terminal, and workspace you want to use. In bulk setup, Project 1 of N shows your progress; Next project and Previous project move between repositories. Keep the current preferences and continue, or save any edits first. Workflow actions can be added later."
      },
      {
        title: "3. Open or resume your work",
        body: "Open project brings up the saved editor and terminal in the selected checkout. Use project: in the launcher to find registered projects. A dedicated workspace keeps project windows together; Current workspace uses the workspace you are on. Opening a project does not run tests or start a dev server."
      },
      {
        title: "4. Add optional workflow actions",
        body: "In project details, add a named action for a test, build, or dev server. Run is for commands that finish; Start is for services that keep running. Saving an action does not execute it. Use Run or Start when you are ready."
      },
      {
        title: "5. Connect an agent",
        body: "Agents → Help explains opt-in reporting for Claude Code and Codex. Start the agent from an exact registered checkout so its task can be associated with the project. Usage is separate from task activity."
      },
      {
        title: "If something is missing",
        body: "No scan results? Pick the exact Git repository folder or a narrower parent folder, then Scan again. A partial scan may still have usable results. Missing checkout? Use Locate folder to point to its new location. Removing a project registration leaves its files and windows in place."
      }
    ]
  if (topic === "actions")
    return [
      {
        title: "Commands and services",
        body: "Choose Command for tests, builds, or other work that exits. Choose Service for a dev server that stays running until you stop it. Name the action so you can recognize it later. Actions use the selected project checkout."
      },
      {
        title: "Example: run tests",
        body: "For npm test, enter npm in Executable and test in the first argument field. Keep Working folder as . for the checkout root. Choose Command, save, then Run. Each argument field is passed literally; do not paste a full command line into Executable."
      },
      {
        title: "Example: start a dev server",
        body: "For npm run dev, enter npm in Executable, then add arguments run and dev. Choose Service. If your server listens on port 5173, enter http://127.0.0.1:5173 as the optional Preview URL. Save, then Start. Choose Stop when you are done."
      },
      {
        title: "Folders, timeouts, and previews",
        body: "Working folder is relative to the selected checkout: . means the root, apps/web means that subfolder. Command timeout limits how long a command may run. Preview opens the URL you supplied; it does not prove that the server is ready. Use its actual port and a loopback address (127.0.0.1 or [::1])."
      },
      {
        title: "Inspect a run",
        body: "Select a run to view its status and output. Command exit status and service readiness are separate. Closing the panel does not stop a run. If acceptance is unconfirmed, refresh and inspect the retained run before starting another. Stop and Restart act on the exact selected run."
      }
    ]
  return [
    {
      title: "Tasks and Usage",
      body: "Tasks shows local agent activity: what needs your input, what is ready to review, and what is still working. Usage shows provider usage and limits. A configured hook or a usage record alone does not create a task."
    },
    {
      title: "1. Register the project",
      body: "Open Setup → Projects → Set up a project. Add the exact Git checkout you will use. Start your agent in that folder so session actions can resolve the correct project and checkout."
    },
    {
      title: "2. Enable your provider",
      body: "Run the install command for the provider you use in a terminal. This installs Aranea reporting hooks. Review the provider's hook trust settings, then start a new native CLI session; existing sessions may not load new hooks.",
      command: "aranea agents adapter install claude\naranea agents adapter install codex"
    },
    {
      title: "3. Use the Tasks panel",
      body: "Open a task's Details to read its report and choose an action. Needs input means answer in the agent terminal. Ready for review means inspect the checkout and the reported result. Failed means inspect its failure report. Finished does not imply that tests passed; verification is reported separately."
    },
    {
      title: "What session buttons do",
      body: "Open session / Go to session focuses the proven hosting terminal, not a particular tmux pane. Reopen session explicitly resumes a supported native session. Open checkout brings up the project's saved tools. Check session again and Reconnect observation read an existing operation; they do not launch another session."
    },
    {
      title: "No tasks appearing?",
      body: "Check provider availability with the commands below. Confirm hooks are trusted, start a new CLI session, and perform an action that triggers a report. Some question hooks are unavailable, so not every prompt can be detected. Connection lost and Unconfirmed describe observation, not proof that the agent stopped.",
      command: "aranea agents adapter status claude\naranea agents adapter status codex"
    },
    {
      title: "Turn reporting off",
      body: "Remove Aranea's owned hooks for the provider. Other provider hooks are preserved. Activity is local to this machine.",
      command: "aranea agents adapter remove claude\naranea agents adapter remove codex"
    },
    {
      title: "Keyboard",
      body: "Tab switches Tasks, Usage, and Help. In Tasks, ↑↓ or j/k moves the cursor; the first Enter reveals it and the next confirms. Escape returns from details or closes the panel. In Help, ↑↓ or j/k scrolls."
    }
  ]
}

if (typeof module !== "undefined") module.exports = { sections }
