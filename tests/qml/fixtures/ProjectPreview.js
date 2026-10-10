/**
 * Supplies fixed display data without a user directory or owner read.
 * @param {string} id - approved project fixture identifier
 * @param {string} [mode] - optional pending launch display
 * @returns {Object<string, *>} inert settings and owner observations
 */
function sample(id, mode) {
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
  var empty = id === "projects-empty"
  var discovery = id === "projects-discovery" || id === "projects-partial"
  var state = {
    schemaVersion: 1,
    revision: 1,
    roots: empty ? [] : [{ id: "r-preview", path: "/fixture/development" }],
    ignored: [],
    projects: empty || discovery ? [] : [project]
  }
  var snapshot = {
    sessionId: "preview-session",
    observedAt: 123,
    availability: { ready: true, registry: true, compositor: true },
    projects: state.projects,
    bindings: [],
    operations: id === "project-launch-partial" ? [operation] : []
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
  return {
    projectsState: state,
    projectTools: {
      defaults: { editorId: "code", terminalId: "kitty" },
      editors: [{ id: "code", label: "VS Code", available: true, supported: true }],
      terminals:
        id === "project-launch-partial"
          ? []
          : [{ id: "kitty", label: "Kitty", available: true, supported: true }]
    },
    projectsDraft: {
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
    projectId: project.id
  }
}
