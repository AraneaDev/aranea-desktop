/**
 * Supplies fixed display data without a user directory or owner read.
 * @param {string} id - approved project fixture identifier
 * @param {string} [mode] - pending launch or installed agent display variant
 * @param {string} [count] - optional project count, including an empty registry
 * @returns {Object<string, *>} inert settings and owner observations
 */
function sample(id, mode, count) {
  var path =
    "/fixture/development/very-long-organization-name/customer-dashboard/worktrees/accessibility-improvements"
  var project = {
    id: "p-preview",
    name: "Customer dashboard and developer accessibility improvements",
    commonDir: "/fixture/development/customer-dashboard/.git",
    lastCheckoutId: "c-preview",
    workspaceMode: "dedicated",
    tools: { editorId: "code", terminalId: "kitty" },
    checkouts: [
      { id: "c-preview", path: path, branch: "accessibility-improvements", primary: true },
      {
        id: "c-review",
        path: "/fixture/development/customer-dashboard-review",
        branch: "review",
        primary: false
      }
    ],
    associations: [{ checkoutId: "c-preview", mode: "dedicated", workspaceId: 3, separate: false }]
  }
  // The problem capture shows the plain start problem of a daily profile start.
  if (mode === "problem") mode = "daily-unknown"
  var daily = mode && mode.indexOf("daily") === 0
  // A linked task checkout is selected so Remove task checkout shows too.
  if (mode === "daily-task" || mode === "review") project.lastCheckoutId = "c-review"
  // The review capture shows an agent task checkout that is ready for review.
  if (mode === "review") project.checkouts[1].branch = "agent/navigation-polish"
  var agentPreview = mode && mode.indexOf("agents") === 0
  if (daily || agentPreview || mode === "profiles" || mode === "profile-editor") {
    project.profiles = [
      {
        id: "f-code",
        revision: 1,
        name: "VS Code",
        roles: ["editor"],
        tools: { editorId: "code", terminalId: null, agentId: null }
      },
      {
        id: "f-review",
        revision: 1,
        name: "Review with terminal",
        roles: ["editor", "terminal"],
        tools: { editorId: "code", terminalId: "kitty", agentId: null }
      },
      {
        id: "f-agent",
        revision: 2,
        name: "Terminal + Agent",
        roles: ["terminal", "agent"],
        tools: { editorId: null, terminalId: "kitty", agentId: "codex" }
      }
    ]
    project.lastProfileId = "f-code"
  }
  var operation = {
    id: "op-preview",
    projectId: project.id,
    checkoutId: "c-preview",
    sessionId: "preview-session",
    generation: 1,
    state: "completed",
    outcome: "partial",
    steps: [
      { id: "editor", role: "editor", status: "observed" },
      { id: "terminal", role: "terminal", status: "failed", code: "TOOL_MISSING" }
    ],
    error: null
  }
  if (mode === "pending") {
    operation.state = "observing"
    operation.outcome = null
    operation.steps[1].status = "pending"
  }
  var empty = id === "projects-empty" || id === "project-setup-folder"
  var discovery =
    id === "projects-discovery" || id === "projects-partial" || id === "project-setup-review"
  var bulk = id === "project-setup-bulk"
  var secondProject = Object.assign({}, project, {
    id: "p-second",
    name: "Backend API",
    checkouts: [
      { id: "c-second", path: "/fixture/development/backend-api", branch: "main", primary: true }
    ],
    lastCheckoutId: "c-second"
  })
  var state = {
    schemaVersion: 1,
    revision: 1,
    roots: empty ? [] : [{ id: "r-preview", path: "/fixture/development" }],
    ignored: [],
    projects: empty || discovery ? [] : bulk ? [project, secondProject] : [project]
  }
  if (count !== undefined && count !== "") {
    state.projects = []
    for (var i = 0; i < Number(count); i++) {
      state.projects.push(
        i === 0
          ? project
          : {
              id: "p-many-" + i,
              name: i % 10 === 0 ? "Customer dashboard" : "Project " + String(i).padStart(3, "0"),
              commonDir: "/fixture/development/team-" + i + "/repository/.git",
              lastCheckoutId: "c-many-" + i,
              tools: { editorId: "code", terminalId: "kitty" },
              checkouts: [
                {
                  id: "c-many-" + i,
                  path: "/fixture/development/team-" + i + "/repository",
                  branch: i % 3 === 0 ? "feature/search" : "main",
                  primary: true
                }
              ],
              associations: []
            }
      )
    }
  }
  // The quick switcher shows six projects: pinned first, then most recent visit.
  var switcherEnvironments = []
  if (mode === "switcher") {
    var names = [
      ["p-aranea", "Aranea shell", "main", "VS Code"],
      ["p-dashboard", "Customer dashboard", "feature/search", "Review with terminal"],
      ["p-backend", "Backend API", "main", "VS Code"],
      ["p-docs", "Docs site", "docs/rewrite", "VS Code"],
      ["p-mobile", "Mobile app", "main", "Terminal"],
      ["p-scratch", "Scratch notes", "main", ""]
    ]
    var visited = {}
    state.projects = names.map(function (entry, index) {
      var profiles = entry[3]
        ? [
            {
              id: "f-" + entry[0],
              revision: 1,
              name: entry[3],
              roles:
                entry[3] === "VS Code"
                  ? ["editor"]
                  : entry[3] === "Terminal"
                    ? ["terminal"]
                    : ["editor", "terminal"],
              tools: {
                editorId: entry[3] === "Terminal" ? null : "code",
                terminalId: entry[3] === "VS Code" ? null : "kitty",
                agentId: null
              }
            }
          ]
        : []
      visited[entry[0]] = 1000 - index * 10
      return {
        id: entry[0],
        name: entry[1],
        commonDir: "/fixture/development/" + entry[0] + "/.git",
        lastCheckoutId: "c-" + entry[0],
        lastProfileId: profiles.length ? profiles[0].id : null,
        profiles: profiles,
        workspaceMode: "dedicated",
        tools: { editorId: "code", terminalId: "kitty" },
        checkouts: [
          {
            id: "c-" + entry[0],
            path: "/fixture/development/" + entry[0].slice(2),
            branch: entry[2],
            primary: true
          }
        ],
        associations: []
      }
    })
    state.navigation = {
      lastProjectId: "p-aranea",
      pinnedProjectIds: ["p-aranea"],
      visitedAt: visited
    }
    switcherEnvironments = [
      {
        id: "e-aranea",
        projectId: "p-aranea",
        checkoutId: "c-p-aranea",
        workspaceId: 3,
        generation: 1,
        sessionId: "preview-session",
        observedRoles: ["editor"],
        status: "observed"
      },
      {
        id: "e-docs",
        projectId: "p-docs",
        checkoutId: "c-p-docs",
        workspaceId: 5,
        generation: 1,
        sessionId: "preview-session",
        observedRoles: ["editor", "terminal"],
        status: "observed"
      }
    ]
  }
  var gitCache = {}
  if (state.projects.length) {
    gitCache[JSON.stringify([project.id, "c-preview"])] = {
      data:
        mode === "unreadable"
          ? null
          : {
              projectId: project.id,
              checkoutId: "c-preview",
              path: path,
              observedAt: Date.now() - (mode === "stale" ? 180000 : 2000),
              branch: "feature/current-overview",
              detached: false,
              upstream: "origin/feature/current-overview",
              ahead: mode === "changes" ? null : 2,
              behind: mode === "changes" ? null : 1,
              counts: {
                staged: mode === "changes" ? 2 : 1,
                unstaged: mode === "changes" ? 2 : 1,
                untracked: 1,
                conflicts: mode === "conflicts" || mode === "changes" ? 1 : 0
              },
              files: [
                {
                  path: "src/project.qml",
                  originalPath: null,
                  indexStatus: mode === "conflicts" ? "U" : "M",
                  worktreeStatus: mode === "conflicts" ? "U" : "M",
                  conflict: mode === "conflicts"
                },
                {
                  path:
                    mode === "changes"
                      ? 'notes/new \t\n <>&" $(touch NEVER) ideas.md'
                      : "notes/new ideas.md",
                  originalPath: null,
                  indexStatus: "?",
                  worktreeStatus: "?",
                  conflict: false
                }
              ].concat(
                mode === "changes"
                  ? [
                      {
                        path: "src/merge-conflict.qml",
                        originalPath: null,
                        indexStatus: "U",
                        worktreeStatus: "U",
                        conflict: true
                      }
                    ]
                  : []
              ),
              truncated: false
            },
      error:
        mode === "unreadable" || mode === "stale"
          ? {
              code: "UNREADABLE",
              message: "Checkout could not be read. Check the folder and refresh."
            }
          : null
    }
  }
  if ((mode === "daily-task" || mode === "review") && state.projects.length) {
    var taskGit = JSON.parse(JSON.stringify(gitCache[JSON.stringify([project.id, "c-preview"])]))
    taskGit.data.checkoutId = "c-review"
    taskGit.data.path = project.checkouts[1].path
    taskGit.data.branch = project.checkouts[1].branch
    taskGit.data.upstream = "origin/" + project.checkouts[1].branch
    if (mode === "review") {
      // A clean, committed task checkout, matching the review card.
      taskGit.data.ahead = 3
      taskGit.data.behind = 0
      taskGit.data.counts = { staged: 0, unstaged: 0, untracked: 0, conflicts: 0 }
      taskGit.data.files = []
    }
    gitCache[JSON.stringify([project.id, "c-review"])] = taskGit
  }
  var snapshot = {
    sessionId: "preview-session",
    observedAt: 123,
    availability: { ready: true, registry: true, compositor: true },
    projects: state.projects,
    bindings: [],
    operations: id === "project-launch-partial" ? [operation] : []
  }
  if (mode === "switcher") snapshot.environments = switcherEnvironments
  if (daily) {
    snapshot.environments = [
      {
        id: "e-code",
        projectId: project.id,
        checkoutId: "c-preview",
        workspaceId: 4,
        sessionId: "preview-session",
        createdAt: 2,
        profileSnapshot: project.profiles[0],
        checkoutSnapshot: project.checkouts[0],
        resolvedTools: project.profiles[0].tools,
        observedRoles: ["editor"],
        status: "observed"
      },
      {
        id: "e-agent",
        projectId: project.id,
        checkoutId: "c-preview",
        workspaceId: 5,
        sessionId: "preview-session",
        createdAt: 3,
        profileSnapshot: project.profiles[2],
        checkoutSnapshot: Object.assign({}, project.checkouts[0], { branch: "earlier-topic" }),
        resolvedTools: project.profiles[2].tools,
        observedRoles: ["terminal"],
        status: "observed"
      }
    ]
    snapshot.operations = [
      {
        id: "op-agent",
        environmentId: "e-agent",
        projectId: project.id,
        checkoutId: "c-preview",
        sessionId: "preview-session",
        generation: 3,
        state: "completed",
        outcome: "partial",
        steps: [
          { role: "terminal", status: "observed" },
          { role: "agent", status: "failed", error: { message: "Provider unavailable" } }
        ]
      }
    ]
    if (mode === "daily-missing") project.lastProfileId = "f-agent"
  }
  if (mode && mode.indexOf("agents") === 0) {
    var history = mode === "agents-history-menu"
    project.openRoles = ["editor", "terminal", "agent"]
    project.tools.agentId = history ? "claude" : "codex"
    project.profiles[2].tools.agentId = project.tools.agentId
    project.lastProfileId = "f-agent"
    snapshot.agents = {
      tools: [
        { id: "claude", label: "Claude Code", available: true, supported: true },
        { id: "codex", label: "Codex", available: true, supported: true }
      ],
      usage: {
        claude: {
          limits: [
            {
              label: "weekly limit",
              percent: history ? 0.55 : 0.94,
              resetsAt: "2099-01-01T12:00:00Z"
            }
          ]
        },
        codex: {
          limits: [{ label: "weekly limit", percent: 0.5, resetsAt: "2099-01-01T12:00:00Z" }]
        }
      }
    }
  }
  if (id === "project-search") {
    snapshot.bindings = [
      {
        projectId: project.id,
        checkoutId: "c-preview",
        role: "editor",
        workspaceId: 3,
        address: "0x123",
        pid: 123,
        appId: "preview-token",
        sessionId: snapshot.sessionId,
        evidence: { mode: "process-app-id", processVerified: true }
      }
    ]
  }
  var reviewTime = Math.floor(Date.now() / 1000)
  var reviewFixture = mode === "review"
  return {
    projectReviews: reviewFixture
      ? {
          "c-review": {
            projectId: project.id,
            error: null,
            data: {
              projectId: project.id,
              checkoutId: "c-review",
              branch: "agent/navigation-polish",
              base: "origin/main",
              mergeBase: "0123456789abcdef0123456789abcdef01234567",
              head: "89abcdef0123456789abcdef0123456789abcdef",
              ahead: 3,
              behind: 0,
              commits: [
                { sha: "89abcdef0123456789abcdef0123456789abcdef", subject: "Keep focus in the sidebar after a refresh" },
                { sha: "4567890123abcdef4567890123abcdef45678901", subject: "Add keyboard shortcuts to the project list" },
                { sha: "bcdef0123456789abcdef0123456789abcdef012", subject: "Group navigation links by section" }
              ],
              files: [
                { path: "src/navigation/Sidebar.js", added: 64, removed: 12 },
                { path: "src/navigation/shortcuts.js", added: 38, removed: 0 },
                { path: "src/navigation/Sidebar.test.js", added: 52, removed: 3 },
                { path: "src/styles/navigation.css", added: 9, removed: 4 },
                { path: "README.md", added: 6, removed: 1 }
              ],
              uncommitted: { dirty: false, untracked: false },
              truncated: false
            }
          }
        }
      : {},
    projectActions:
      reviewFixture
        ? {
            snapshot: {
              revision: 1,
              definitions: [
                {
                  id: "a-tests",
                  projectId: project.id,
                  revision: 1,
                  name: "Run tests",
                  kind: "command",
                  argv: ["npm", "test"],
                  cwdRelative: "."
                }
              ],
              runs: [],
              requests: []
            }
          }
        : mode === "activity"
        ? {
            snapshot: {
              revision: 1,
              definitions: [
                {
                  id: "a-server",
                  projectId: project.id,
                  revision: 1,
                  name: "Dev server",
                  kind: "service",
                  argv: ["npm", "run", "dev"],
                  cwdRelative: "."
                }
              ],
              runs: [
                {
                  id: "r-server",
                  projectId: project.id,
                  checkoutId: "c-preview",
                  actionId: "a-server",
                  createdAt: Math.floor(Date.now() / 1000) - 90,
                  updatedAt: Math.floor(Date.now() / 1000),
                  processState: "running",
                  invocationId: "fixture-invocation",
                  definitionSnapshot: { id: "a-server", name: "Dev server", kind: "service" }
                }
              ],
              requests: []
            }
          }
        : {},
    activitySnapshot:
      reviewFixture
        ? {
            tasks: [
              {
                taskId: "t-navigation",
                provider: "codex",
                description: "Polish project navigation",
                reportedState: "ready-for-review",
                freshness: "connected",
                nativeSessionEligible: true,
                lastReceivedAt: reviewTime,
                verification: { status: "reported-pass" },
                association: {
                  status: "registered",
                  projectId: project.id,
                  checkoutId: "c-review",
                  cwd: project.checkouts[1].path
                }
              }
            ],
            operations: []
          }
        : mode === "activity"
        ? {
            tasks: [
              {
                taskId: "t-layout",
                provider: "codex",
                description: "Refine project navigation",
                reportedState: "needs-input",
                freshness: "connected",
                nativeSessionEligible: true,
                lastReceivedAt: Math.floor(Date.now() / 1000),
                verification: { status: "not-reported" },
                association: {
                  status: "registered",
                  projectId: project.id,
                  checkoutId: "c-preview",
                  cwd: path
                }
              }
            ],
            operations: []
          }
        : { tasks: [], operations: [] },
    projectSection: mode === "profiles" || mode === "profile-editor" ? "profiles" : "overview",
    projectsState: state,
    projectGitCache: gitCache,
    projectAcceptanceUnknown: mode === "daily-unknown",
    projectTools: {
      defaults: { editorId: "code", terminalId: "kitty" },
      editors: [
        { id: "code", label: "VS Code", available: true, supported: true },
        { id: "nvim", label: "Neovim", available: true, supported: true }
      ],
      agents:
        (daily && mode !== "daily-missing") ||
        agentPreview ||
        mode === "profiles" ||
        mode === "profile-editor"
          ? [
              { id: "claude", label: "Claude Code", available: true, supported: true },
              { id: "codex", label: "Codex", available: true, supported: true }
            ]
          : [],
      terminals:
        id === "project-launch-partial"
          ? []
          : [{ id: "kitty", label: "Kitty", available: true, supported: true }]
    },
    projectsDraft: {
      profileEditing: mode === "profile-editor",
      profileDraft: mode === "profile-editor" ? project.profiles[2] : null,
      profileRevision: mode === "profile-editor" ? 2 : 0,
      exactSetup: id === "project-setup-folder",
      setupActive: id.indexOf("project-setup-") === 0,
      setupStep:
        id === "project-setup-folder"
          ? 0
          : id === "project-setup-review"
            ? 1
            : id === "project-setup-configure" || bulk
              ? 2
              : 3,
      setupProjectId:
        id === "project-setup-configure" || id === "project-setup-agents" || bulk ? project.id : "",
      setupProjectIds: bulk
        ? [project.id, secondProject.id]
        : id === "project-setup-configure" || id === "project-setup-agents"
          ? [project.id]
          : [],
      selectedPaths: [],
      ignoredExpanded: false,
      detailsDraft: {
        name: project.name,
        editorId: "code",
        terminalId: "kitty",
        workspaceMode: "dedicated"
      },
      detailsOperation: id === "project-launch-partial" ? operation : null,
      recoveryCheckoutId: "c-preview",
      recoveryProjectId: project.id,
      recoverySelectedCheckoutId: "c-preview",
      detailsDirty: false,
      customized: id === "project-details",
      folderPath: ""
    },
    projectCandidates: discovery
      ? [
          {
            path: path,
            name: project.name,
            commonDir: project.commonDir,
            checkouts: project.checkouts.map(function (c) {
              return { path: c.path, branch: c.branch, primary: c.primary }
            })
          }
        ]
      : [],
    projectPartial: id === "projects-partial",
    projectErrors:
      id === "projects-partial"
        ? [
            {
              code: "SCAN_LIMIT",
              message: "Directory limit reached. Choose a narrower folder.",
              path: "/fixture/development"
            }
          ]
        : [],
    projectSnapshot: snapshot,
    projectAvailable: true,
    projectId: state.projects.length ? project.id : ""
  }
}
