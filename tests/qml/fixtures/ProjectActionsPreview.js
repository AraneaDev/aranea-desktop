/**
 * Supplies full inert action records and drafts for one Actions scene; every
 * rendered control stays production. Shared by the offscreen actions renderer
 * and the live desktop capture (tools/project-capture-fixture.mjs).
 * @param {string} scene - approved action scene identifier
 * @returns {Object<string, *>} inert Projects capture fixture
 */
function sample(scene) {
  var p = "p-00000000-0000-4000-8000-000000000001"
  var c = "c-00000000-0000-4000-8000-000000000001"
  var a = "a-00000000-0000-4000-8000-000000000001"
  var r = "r-00000000-0000-4000-8000-000000000001"
  var request = "req-00000000-0000-4000-8000-000000000001"
  var long = scene === "long-output"
  var path = long
    ? "/fixture/development/very-long-organization/customer-dashboard/worktrees/accessibility-improvements/build-output"
    : "/fixture/customer-dashboard"
  var service =
    [
      "configured-service",
      "editor-service",
      "running",
      "reachable",
      "unreachable",
      "unconfirmed"
    ].indexOf(scene) >= 0
  var d = {
    id: a,
    projectId: p,
    name: long
      ? "Customer dashboard accessibility validation with a long literal command and separate argument fields"
      : service
        ? "Start preview"
        : "Run checks",
    kind: service ? "service" : "command",
    argv: [
      "printf",
      long ? "literal $HOME %i ; <b>plain</b> " + path : "literal $HOME %i ; <b>plain</b>",
      ""
    ],
    cwdRelative: ".",
    timeoutSeconds: service ? null : 300,
    previewUrl: service ? "http://127.0.0.1:8181/" : null,
    revision: 1,
    createdAt: 1700000000,
    updatedAt: 1700000000
  }
  var project = {
    id: p,
    name: "Customer dashboard",
    commonDir: "/fixture/customer-dashboard/.git",
    lastCheckoutId: c,
    workspaceMode: "dedicated",
    tools: {
      editorId: "code",
      terminalId: "kitty"
    },
    checkouts: [
      {
        id: c,
        path: path,
        branch: "main",
        primary: true
      }
    ],
    associations: []
  }
  var hasRun =
    [
      "running",
      "passed",
      "failed",
      "stopped",
      "unconfirmed",
      "reachable",
      "unreachable",
      "long-output"
    ].indexOf(scene) >= 0
  var processState =
    scene === "passed" || long
      ? "succeeded"
      : scene === "failed"
        ? "failed"
        : scene === "stopped"
          ? "stopped"
          : scene === "unconfirmed"
            ? "unconfirmed"
            : "running"
  var run = {
    id: r,
    requestId: request,
    projectId: p,
    checkoutId: c,
    actionId: a,
    definitionRevision: 1,
    definitionHash: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    definitionSnapshot: d,
    cwd: path,
    unitName: "aranea-project-00000000-0000-4000-8000-000000000001.service",
    bootId: "00000000-0000-4000-8000-000000000001",
    invocationId: scene === "unconfirmed" ? null : "11111111111111111111111111111111",
    createdAt: 1700000000,
    updatedAt: 1700000000,
    state: "completed",
    outcome:
      processState === "failed"
        ? "failed"
        : processState === "unconfirmed"
          ? "partial"
          : "observed",
    processState: processState,
    readiness:
      scene === "reachable" ? "reachable" : scene === "unreachable" ? "unreachable" : "unknown",
    exitCode: processState === "succeeded" ? 0 : processState === "failed" ? 7 : null,
    exitSignal: null,
    error:
      scene === "unconfirmed"
        ? {
            code: "SUBMISSION_UNCONFIRMED",
            message: "Manager acceptance is unconfirmed.",
            recovery: "Refresh this exact run; do not resubmit."
          }
        : scene === "failed"
          ? {
              code: "COMMAND_FAILED",
              message: "Command exited with status 7.",
              recovery: "Read the local journal and review the saved command."
            }
          : null,
    stopRequested: scene === "stopped",
    submissionUnconfirmed: scene === "unconfirmed"
  }
  var editing = scene.indexOf("editor") >= 0
  var actions = {
    selectedActionId: scene === "empty" ? "" : a,
    selectedIdentity: [p, c, a, 1].join("|"),
    editing: editing,
    draftProjectId: p,
    snapshot: {
      schemaVersion: 1,
      revision: 1,
      definitions: scene === "empty" ? [] : [d],
      runs: hasRun ? [run] : [],
      requests: hasRun
        ? [
            {
              requestId: request,
              hash: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
              runId: r,
              createdAt: 1700000000
            }
          ]
        : []
    },
    currentRun: hasRun ? run : null,
    runId: hasRun ? r : "",
    requestId: hasRun ? request : "",
    submissionUncertain: false,
    availability: {
      execution: scene !== "unavailable-manager",
      userManager: scene !== "unavailable-manager"
    },
    available: true,
    error: null,
    output: hasRun
      ? long
        ? Array(50).join("<b>literal journal output</b> " + path + "\n")
        : "<b>literal journal output</b>\nArguments remain plaintext.\n"
      : "",
    truncated: long
  }
  if (editing)
    actions.editor = {
      draft: {
        id: a,
        name: d.name,
        executable: scene === "invalid-editor" ? "" : "printf",
        cwdRelative: ".",
        kind: service ? "service" : "command",
        timeoutSeconds: "300",
        previewUrl: service ? d.previewUrl : ""
      },
      argv: d.argv.slice(1),
      expectedRevision: 1,
      fieldError:
        scene === "invalid-editor"
          ? "Enter an executable name, absolute path or explicit ./path."
          : ""
    }
  return {
    state: {},
    projectId: p,
    projectSection: "actions",
    projectsState: {
      schemaVersion: 1,
      revision: 1,
      roots: [],
      ignored: [],
      projects: [project]
    },
    projectTools: {
      defaults: {
        editorId: "code",
        terminalId: "kitty"
      },
      editors: [
        {
          id: "code",
          label: "VS Code",
          available: true,
          supported: true
        }
      ],
      terminals: [
        {
          id: "kitty",
          label: "Kitty",
          available: true,
          supported: true
        }
      ]
    },
    projectAvailable: true,
    projectSnapshot: {
      sessionId: "preview-session",
      availability: {
        ready: true,
        registry: true,
        compositor: true
      }
    },
    projectActions: actions
  }
}
