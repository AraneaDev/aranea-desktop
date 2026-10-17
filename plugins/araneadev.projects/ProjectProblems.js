/** Fixed titles for the ten plain problem kinds. */
/** @type {{[key:string]:string}} */
var KINDS = {
  unconfirmed: "Couldn't confirm it started",
  failed: "Couldn't start",
  moved: "Folder moved or missing",
  notRunning: "Projects isn't running",
  missingTool: "A tool is missing",
  git: "Git couldn't do that",
  changed: "Changed elsewhere",
  busy: "Busy right now",
  notAllowed: "Can't do that here",
  unknown: "Something went wrong"
}

/** Fixed labels for every action a problem can offer. */
/** @type {{[key:string]:string}} */
var ACTIONS = {
  retry: "Retry",
  checkAgain: "Check again",
  startAnother: "Start another",
  openAnother: "Open another window",
  locate: "Locate folder",
  refresh: "Refresh",
  settings: "Open settings",
  install: "Show how to install"
}

/** Internal words that never appear in user-visible Projects text. */
var BANNED = [
  "acceptance",
  "receipt",
  "owner",
  "observation",
  "observe",
  "observed",
  "binding",
  "exact",
  "retained",
  "ipc",
  "replay",
  "resubmit",
  "unconfirmed"
]

/** Code groups per kind; anything absent is "unknown". */
/** @type {{[key:string]:string[]}} */
var GROUPS = {
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
    "NO_BRANCH",
    "PUSH_REJECTED",
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

/** One plain sentence per kind, used when the backend message is not kept. */
/** @type {{[key:string]:string}} */
var BODIES = {
  unconfirmed: "Projects couldn't tell whether it started. It may still open.",
  failed: "It didn't start. Nothing else was changed.",
  moved: "The folder for this checkout isn't where Projects expects it.",
  notRunning: "The Projects service isn't answering. Make sure Aranea is running, then try again.",
  missingTool: "A tool this needs isn't installed.",
  git: "Git stopped before finishing.",
  changed: "This changed somewhere else while you were working. Refresh to see the latest.",
  busy: "Something else is still running here. Try again in a moment.",
  notAllowed: "This isn't possible for this item.",
  unknown: "Projects hit an unexpected problem. Details has the information for a bug report."
}

/** Kinds whose backend message is already plain and is kept as the body. */
/** @type {{[key:string]:boolean}} */
var KEEP_MESSAGE = { git: true, notAllowed: true }

/** Codes whose plain backend message names the tool and is kept as the body. */
/** @type {{[key:string]:boolean}} */
var KEEP_CODE_MESSAGE = { AGENT_MISSING: true }

/** Git codes worth retrying as they are. */
/** @type {{[key:string]:boolean}} */
var TRANSIENT_GIT = { GIT_TIMEOUT: true, AUTH_REQUIRED: true }

/**
 * Whether text contains any banned internal word, matched case-insensitively as whole words.
 * @param {string} text - user-visible text to check
 * @returns {boolean} true when a banned word appears
 */
function bannedIn(text) {
  return BANNED.some(function (word) {
    return new RegExp("\\b" + word + "\\b", "i").test(text)
  })
}

/**
 * Plain kind for an error code.
 * @param {string} [code] - backend or client error code
 * @returns {string} one of the ten kinds
 */
function kindOf(code) {
  for (var kind in GROUPS) if (GROUPS[kind].indexOf(code) >= 0) return kind
  return "unknown"
}

/**
 * Preferred action ids for a kind, before filtering by caller abilities.
 * @param {string} kind - plain kind
 * @param {string} code - original code
 * @param {string} surface - calling surface
 * @returns {string[]} ordered action ids
 */
function preferred(kind, code, surface) {
  if (kind === "unconfirmed")
    return surface === "details" ? ["checkAgain", "openAnother"] : ["checkAgain", "startAnother"]
  if (kind === "failed" || kind === "notRunning" || kind === "busy") return ["retry"]
  if (kind === "moved") return ["locate"]
  if (kind === "missingTool") return ["install", "settings"]
  if (kind === "git") return TRANSIENT_GIT[code] ? ["retry"] : []
  if (kind === "changed" || kind === "unknown") return ["refresh"]
  return []
}

/**
 * Turn any error into a plain problem with at most two actions.
 * @param {*} error - {code, message, recovery}; may be missing or partial
 * @param {*} context - {surface, operation, subject (role shown in a window problem), actions:[ids the caller can do]}
 * @returns {{kind:string,title:string,body:string,actions:{id:string,label:string}[],details:{code:string,message:string,recovery:string}}} plain problem
 */
function problem(error, context) {
  var e = error && typeof error === "object" ? error : {}
  var c = context && typeof context === "object" ? context : {}
  var code = typeof e.code === "string" ? e.code : ""
  var message = typeof e.message === "string" ? e.message : ""
  var recovery = typeof e.recovery === "string" ? e.recovery : ""
  var kind = kindOf(code)
  var keep = (KEEP_MESSAGE[kind] || KEEP_CODE_MESSAGE[code]) && message && !bannedIn(message)
  var body = keep ? message : BODIES[kind]
  if (!keep && kind === "unconfirmed") {
    if (c.surface === "details" && typeof c.subject === "string" && c.subject)
      body = "Projects couldn't confirm the " + c.subject + " window opened. It may still open."
    else if (c.surface === "run")
      body = "Projects couldn't tell whether the run started. It may still be running."
  }
  var allowed = Array.isArray(c.actions) ? c.actions : []
  var actions = preferred(kind, code, c.surface || "")
    .filter(function (id) {
      return allowed.indexOf(id) >= 0
    })
    .slice(0, 2)
    .map(function (id) {
      return { id: id, label: ACTIONS[id] }
    })
  return {
    kind: kind,
    title: KINDS[kind],
    body: body,
    actions: actions,
    details: { code: code, message: message, recovery: recovery }
  }
}

if (typeof module !== "undefined")
  module.exports = {
    KINDS: KINDS,
    ACTIONS: ACTIONS,
    BANNED: BANNED,
    kindOf: kindOf,
    problem: problem
  }
