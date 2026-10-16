const { test } = require("node:test")
const assert = require("node:assert/strict")
const { loadPragma } = require("./lib/load-pragma.js")
const p = loadPragma("plugins/araneadev.projects/ProjectProblems.js")
const plain = (v) => JSON.parse(JSON.stringify(v))
const ALL = [
  "retry",
  "checkAgain",
  "startAnother",
  "openAnother",
  "locate",
  "refresh",
  "settings",
  "install"
]

const table = {
  unconfirmed: [
    "ACCEPTANCE_UNKNOWN",
    "SUBMISSION_UNCONFIRMED",
    "FOCUS_UNCONFIRMED",
    "WINDOW_TARGET_UNCONFIRMED",
    "OWNERSHIP_UNCONFIRMED",
    "OBSERVATION_TIMEOUT",
    "ACTIVATION_UNCONFIRMED",
    "OPERATION_LOST",
    "PREPARATION_TIMEOUT"
  ],
  failed: [
    "LAUNCH_FAILED",
    "FOCUS_FAILED",
    "INVALID_LAUNCH",
    "RETRY_NOT_FAILED",
    "SAVE_NOT_STARTED",
    "READ_FAILED",
    "RUN_IDENTITY_LOST",
    "RUN_NOT_FOUND",
    "RUN_TERMINAL",
    "ACTION_NOT_FOUND",
    "OPERATION_NOT_FOUND"
  ],
  moved: [
    "CHECKOUT_INVALID",
    "CHECKOUT_MISSING",
    "CHECKOUT_NOT_FOUND",
    "CHECKOUT_CHANGED",
    "INVALID_PATH",
    "PROJECT_NOT_FOUND",
    "ENVIRONMENT_NOT_FOUND"
  ],
  notRunning: [
    "OWNER_UNAVAILABLE",
    "OWNER_NOT_READY",
    "COMPOSITOR_UNAVAILABLE",
    "REGISTRY_UNAVAILABLE",
    "ACTIONS_UNAVAILABLE",
    "SESSION_CHANGED",
    "SESSION_NOT_FOUND"
  ],
  missingTool: [
    "TOOL_MISSING",
    "AGENT_MISSING",
    "DEPENDENCY_MISSING",
    "UNSUPPORTED_TOOL",
    "ADAPTER_UNSUPPORTED"
  ],
  git: [
    "NO_REMOTE",
    "NO_UPSTREAM",
    "NOT_FAST_FORWARD",
    "LOCAL_CHANGES",
    "AUTH_REQUIRED",
    "GIT_TIMEOUT",
    "GIT_ERROR",
    "INVALID_BRANCH",
    "BRANCH_EXISTS",
    "NO_DEFAULT_BRANCH",
    "PATH_EXISTS",
    "REGISTER_FAILED",
    "UNREGISTER_FAILED"
  ],
  changed: [
    "REGISTRY_CONFLICT",
    "PROFILE_CHANGED",
    "TARGET_CHANGED",
    "ENVIRONMENT_CHANGED",
    "ACTION_CONFLICT",
    "ACTIVATION_CONFLICT",
    "PROFILE_CONFLICT",
    "PROFILE_NOT_FOUND",
    "CHECKOUT_CONFLICT",
    "REQUEST_CONFLICT",
    "ENVIRONMENT_CONFLICT",
    "STALE_SEQUENCE"
  ],
  busy: [
    "GIT_BUSY",
    "CHECKOUT_BUSY",
    "WORKSPACE_BUSY",
    "RUN_PROTECTED",
    "REGISTRY_LOCK_FAILED",
    "CAPACITY_EXCEEDED"
  ],
  notAllowed: [
    "PRIMARY_CHECKOUT",
    "CHECKOUT_DIRTY",
    "UNPUSHED_COMMITS",
    "CHECKOUT_REQUIRED",
    "INERT_MODE",
    "INVALID_WORKSPACE",
    "WORKSPACE_UNAVAILABLE",
    "ROOT_CHOICE_REQUIRED",
    "INPUT_TOO_LARGE",
    "INVALID_REQUEST",
    "REGISTRY_INVALID",
    "REGISTRY_WRITE_FAILED",
    "ACTION_WRITE_FAILED",
    "ACTION_STATE_INVALID",
    "UNSAFE_STATE_PATH",
    "ROOT_NOT_FOUND"
  ]
}

test("every known code maps to its kind and title", () => {
  for (const [kind, codes] of Object.entries(table))
    for (const code of codes) {
      const r = p.problem({ code, message: "m", recovery: "r" }, { actions: ALL })
      assert.equal(r.kind, kind, code)
      assert.equal(r.title, p.KINDS[kind], code)
      assert.ok(r.actions.length <= 2, code)
    }
})

test("unknown and malformed errors still read plainly", () => {
  for (const e of [{}, { code: "X" }, { message: "m" }, null, undefined]) {
    const r = p.problem(e, { actions: ALL })
    assert.equal(r.kind, "unknown")
    assert.equal(r.title, "Something went wrong")
    assert.ok(r.body.length > 0)
  }
  assert.equal(p.problem({ message: "Raw text." }, {}).details.message, "Raw text.")
})

test("actions follow the kind order and the caller's abilities", () => {
  const u = p.problem({ code: "ACCEPTANCE_UNKNOWN" }, { actions: ALL })
  assert.deepEqual(plain(u.actions), [
    { id: "checkAgain", label: "Check again" },
    { id: "startAnother", label: "Start another" }
  ])
  assert.deepEqual(
    plain(p.problem({ code: "ACCEPTANCE_UNKNOWN" }, { actions: ["checkAgain"] }).actions),
    [{ id: "checkAgain", label: "Check again" }]
  )
  assert.deepEqual(plain(p.problem({ code: "CHECKOUT_INVALID" }, { actions: ALL }).actions), [
    { id: "locate", label: "Locate folder" }
  ])
  assert.deepEqual(plain(p.problem({ code: "PRIMARY_CHECKOUT" }, { actions: ALL }).actions), [])
  assert.deepEqual(plain(p.problem({ code: "NOT_FAST_FORWARD" }, { actions: ALL }).actions), [])
  assert.deepEqual(plain(p.problem({ code: "GIT_TIMEOUT" }, { actions: ALL }).actions), [
    { id: "retry", label: "Retry" }
  ])
  assert.deepEqual(
    plain(
      p.problem({ code: "WINDOW_TARGET_UNCONFIRMED" }, { surface: "details", actions: ALL }).actions
    ),
    [
      { id: "checkAgain", label: "Check again" },
      { id: "openAnother", label: "Open another window" }
    ]
  )
})

test("plain backend messages are kept for git and notAllowed", () => {
  const msg = "Branches have diverged; merge or rebase in a terminal."
  assert.equal(p.problem({ code: "NOT_FAST_FORWARD", message: msg }, {}).body, msg)
  assert.notEqual(
    p.problem({ code: "ACCEPTANCE_UNKNOWN", message: "Launch acceptance is unknown." }, {}).body,
    "Launch acceptance is unknown."
  )
})

test("no banned word, em dash or long action list in any produced text", () => {
  const re = new RegExp("\\b(" + p.BANNED.join("|") + ")\\b", "i")
  for (const kind of [...Object.keys(table), "unknown"]) {
    const codes = table[kind] || ["NOPE"]
    for (const code of codes)
      for (const surface of ["start", "run", "git", "registry", "setup", "details", "agents"]) {
        const r = p.problem({ code }, { surface, actions: ALL })
        for (const text of [r.title, r.body, ...r.actions.map((a) => a.label)]) {
          assert.ok(!re.test(text), code + " " + surface + ": " + text)
          assert.ok(text.indexOf(String.fromCharCode(0x2014)) < 0, text)
        }
      }
  }
})

test("details keep the original code, message and recovery", () => {
  const r = p.problem(
    {
      code: "OWNER_UNAVAILABLE",
      message: "Project owner unavailable.",
      recovery: "Activate Aranea and retry."
    },
    {}
  )
  assert.deepEqual(plain(r.details), {
    code: "OWNER_UNAVAILABLE",
    message: "Project owner unavailable.",
    recovery: "Activate Aranea and retry."
  })
})

test("role window problems name the role and run problems talk about the run", () => {
  const body = (role) =>
    p.problem(
      { code: "WINDOW_TARGET_UNCONFIRMED" },
      { surface: "details", subject: role, actions: ALL }
    ).body
  assert.equal(
    body("agent"),
    "Projects couldn't confirm the agent window opened. It may still open."
  )
  assert.equal(
    body("editor"),
    "Projects couldn't confirm the editor window opened. It may still open."
  )
  assert.equal(
    body("terminal"),
    "Projects couldn't confirm the terminal window opened. It may still open."
  )
  assert.equal(
    p.problem({ code: "SUBMISSION_UNCONFIRMED" }, { surface: "run", actions: ALL }).body,
    "Projects couldn't tell whether the run started. It may still be running."
  )
  assert.equal(
    p.problem({ code: "SUBMISSION_UNCONFIRMED" }, { surface: "actions", actions: ALL }).body,
    "Projects couldn't tell whether it started. It may still open."
  )
})

test("a missing agent names the tool through its plain backend message", () => {
  assert.equal(
    p.problem({ code: "AGENT_MISSING", message: "Codex isn't installed." }, {}).body,
    "Codex isn't installed."
  )
  assert.equal(
    p.problem({ code: "AGENT_MISSING", message: "Owner has no binding." }, {}).body,
    "A tool this needs isn't installed."
  )
  assert.equal(
    p.problem({ code: "TOOL_MISSING", message: "kitty is not installed." }, {}).body,
    "A tool this needs isn't installed."
  )
})
