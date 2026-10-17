/** @typedef {{[key:string]:any}} ActivityData */

/** Validate public IDs without allowing option-shaped executable arguments.
 * @param {any} value - candidate ID
 * @returns {boolean} bounded printable non-option identifier
 */
function validId(value) {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 256 &&
    !/^[\s-]/.test(value) &&
    !value.split("").some(function (character) {
      return character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127
    })
  )
}

/** Fixed provider CLI resume identity; named sessions are deliberately unsupported.
 * @param {ActivityData} task - retained task
 * @returns {?string} display-only shell-quoted command
 */
function resumeCommand(task) {
  if (!task || !/^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/.test(task.providerSessionId))
    return null
  if (task.provider === "claude") return "claude --resume '" + task.providerSessionId + "'"
  var cwd = task.association && task.association.cwd
  if (
    task.provider !== "codex" ||
    typeof cwd !== "string" ||
    cwd[0] !== "/" ||
    cwd.split("").some(function (character) {
      return character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127
    })
  )
    return null
  return "codex resume '" + task.providerSessionId + "' --cd '" + cwd.replace(/'/g, "'\\''") + "'"
}

/** Locate the exact native epoch, never another session sharing a checkout.
 * @param {ActivityData} state - durable snapshot
 * @param {ActivityData} task - task identity
 * @returns {?ActivityData} retained epoch
 */
function sessionFor(state, task) {
  /** @type {Array<ActivityData>} */
  var sessions = state.sessions || []
  return (
    sessions.filter(function (s) {
      return (
        s.provider === task.provider &&
        s.providerSessionId === task.providerSessionId &&
        s.producerEpoch === task.producerEpoch
      )
    })[0] || null
  )
}

/** Seconds without any report after which working is treated as ended (6 hours).
 * The store's dismiss rule uses the same age (agent-activity.jq stale_work). */
var silentWorkSeconds = 21600

/** A working task with no report for silentWorkSeconds, while its session may
 * still send heartbeats. A question (needs-input) can wait for the user.
 * @param {ActivityData} task - retained task
 * @param {number} wall - current wall clock in milliseconds
 * @returns {boolean} the work ended without a report
 */
function silentWork(task, wall) {
  return (
    task.reportedState === "working" &&
    typeof task.lastReceivedAt === "number" &&
    wall - task.lastReceivedAt * 1000 >= silentWorkSeconds * 1000
  )
}

/** Project reported lifecycle independently from connection and verification.
 * displayState is "ended" for working or needs-input work a later prompt in its
 * session superseded, and for working with no report for 6 hours.
 * Numeric now is wall milliseconds; clock objects additionally provide monotonic
 * milliseconds and bootId. Store projections remain authoritative for boot loss.
 * @param {ActivityData} state - last validated store snapshot
 * @param {number|ActivityData} now - injected current clock
 * @param {?ActivityData} registry - current registered checkouts, or null
 * @returns {ActivityData} immutable public view
 */
function project(state, now, registry) {
  var clock = typeof now === "number" ? { wall: now } : now
  /** @type {Array<ActivityData>} */
  var tasks = state.tasks || []
  /** @type {Array<ActivityData>} */
  var projects = (registry && registry.projects) || []
  return Object.assign({}, state, {
    tasks: tasks.map(function (task) {
      var s = sessionFor(state, task),
        c = s && s.connection
      var age = c ? clock.wall - c.receivedAt * 1000 : Infinity
      var lost =
        !c || !c.connected || age < 0 || age >= 60000 || task.freshness === "connection-lost"
      if (c && clock.bootId !== undefined) lost = lost || clock.bootId !== c.bootId
      if (c && clock.monotonic !== undefined)
        lost =
          lost ||
          clock.monotonic < c.monotonic * 1000 ||
          clock.monotonic - c.monotonic * 1000 >= 60000
      var superseded =
        !!s && ((s.nativeMetadata || {}).inactiveTaskIds || []).indexOf(task.taskId) >= 0
      if (superseded) lost = true
      var freshness = lost
        ? "connection-lost"
        : s.provenance && s.provenance.commandHash
          ? "connected"
          : "unconfirmed"
      var association = Object.assign({}, task.association)
      if (
        registry &&
        association.status === "registered" &&
        !projects.some(function (p) {
          return (
            p.id === association.projectId &&
            p.checkouts.some(function (/** @type {ActivityData} */ co) {
              return co.id === association.checkoutId && co.path === association.cwd
            })
          )
        })
      )
        association.status = "unavailable"
      var historical = ["finished", "failed", "ready-for-review"].indexOf(task.reportedState) >= 0
      var displayState = !historical && lost ? "connection-lost" : task.reportedState
      if (!historical && (superseded || silentWork(task, clock.wall))) displayState = "ended"
      return Object.assign({}, task, {
        // Presentation eligibility follows private exact-epoch evidence, not the
        // latest producer label. Runtime still independently proves every action.
        nativeSessionEligible: !!(
          s &&
          s.provenance &&
          s.provenance.commandHash &&
          s.nativeMetadata &&
          (s.nativeMetadata.observedHooks || []).indexOf("SessionStart") >= 0
        ),
        association: association,
        freshness: freshness,
        displayState: displayState,
        verification: task.verification || { status: "unknown", summary: "", commands: [] },
        resumeCommand: resumeCommand(task),
        focusScope: "hosting-terminal",
        ownership: "unconfirmed"
      })
    })
  })
}
/** Stable attention identity excludes diagnostic/heartbeat/text updates.
 * @param {ActivityData} task - current task
 * @returns {string} identity
 */
function notificationKey(task) {
  return JSON.stringify([
    task.taskId,
    task.producerEpoch,
    task.reportedState,
    (task.blockers || [])
      .map(function (/** @type {ActivityData} */ b) {
        return b.id || b.blockerId || ""
      })
      .sort()
  ])
}

/** Bounded native notification text, without markup or control characters.
 * @param {any} value - display data
 * @param {number} limit - maximum length
 * @returns {string} plain text
 */
function notificationText(value, limit) {
  return String(value || "")
    .replace(/[<>]/g, "")
    .split("")
    .filter(function (c) {
      return c.charCodeAt(0) >= 32 && c.charCodeAt(0) !== 127
    })
    .join("")
    .slice(0, limit)
}

/** Initial snapshots are historical; suppressed transitions are consumed by the owner.
 * @param {?ActivityData} previous - last successfully read snapshot
 * @param {ActivityData} current - new successfully read snapshot
 * @param {boolean} suppressed - policy blocks emission
 * @returns {Array<ActivityData>} attention transitions only
 */
function notificationTransitions(previous, current, suppressed) {
  if (!previous || suppressed) return []
  return (current.tasks || [])
    .filter(function (/** @type {ActivityData} */ task) {
      if (["needs-input", "ready-for-review", "failed"].indexOf(task.reportedState) < 0)
        return false
      var before = (previous.tasks || []).filter(function (/** @type {ActivityData} */ old) {
        return old.taskId === task.taskId
      })[0]
      return !before || notificationKey(before) !== notificationKey(task)
    })
    .map(function (/** @type {ActivityData} */ task) {
      /** @type {{[key:string]:string}} */
      var labels = {
        "needs-input": "Needs input",
        "ready-for-review": "Ready for review",
        failed: "Failed"
      }
      return {
        taskId: task.taskId,
        key: notificationKey(task),
        title: "Aranea · " + labels[task.reportedState],
        body: notificationText(
          task.description || task.summary || "Agent task needs attention",
          512
        )
      }
    })
}
/** Characters a panel shows of one text or one joined list (AgentTasksLogic.text). */
var shownChars = 4096

/** Largest single task row sent in an IPC snapshot page. */
var maxTaskBytes = 32000

/** UTF-8 size of a string, the unit the Quickshell IPC reply limit counts.
 * @param {string} value - text
 * @returns {number} bytes
 */
function utf8Length(value) {
  var s = String(value),
    n = 0
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (c >= 0xd800 && c < 0xdc00 && i + 1 < s.length) {
      n += 4
      i++
    } else n += 3
  }
  return n
}

/** Keep the first LIMIT characters of a list's joined text, one entry per line.
 * @param {any} list - entries
 * @param {string} field - text field of each entry
 * @param {number} limit - joined characters kept
 * @param {boolean} keepAll - keep every entry (with empty text past the limit)
 * @returns {any} bounded copy, or the input when it is not a list
 */
function boundList(list, field, limit, keepAll) {
  if (!Array.isArray(list)) return list
  var room = limit
  /** @type {Array<ActivityData>} */
  var kept = []
  list.forEach(function (/** @type {ActivityData} */ entry) {
    if (room <= 0 && !keepAll) return
    var copy = Object.assign({}, entry)
    if (typeof entry[field] === "string") {
      copy[field] = room > 0 ? entry[field].slice(0, room) : ""
      room -= copy[field].length + 1
    }
    kept.push(copy)
  })
  return kept
}

/** Bound one task row to what the Tasks views display, then to a byte size.
 * Lists keep the first shown characters; a row that is still too large (long
 * multibyte text everywhere) keeps shorter text. Identity fields never change.
 * @param {ActivityData} task - projected task
 * @returns {ActivityData} bounded copy
 */
function boundTask(task) {
  var limits = [shownChars, 1024, 256]
  /** @type {ActivityData} */
  var copy = task
  for (var i = 0; i < limits.length; i++) {
    var limit = limits[i]
    copy = Object.assign({}, task)
    ;["description", "result", "question"].forEach(function (key) {
      if (typeof task[key] === "string") copy[key] = task[key].slice(0, limit)
    })
    copy.diagnostics = boundList(task.diagnostics, "summary", limit, false)
    copy.blockers = boundList(task.blockers, "question", limit, true)
    if (task.verification && typeof task.verification === "object") {
      copy.verification = Object.assign({}, task.verification)
      if (typeof task.verification.summary === "string")
        copy.verification.summary = task.verification.summary.slice(0, limit)
      if (limit < shownChars && Array.isArray(task.verification.commands))
        copy.verification.commands = boundList(
          task.verification.commands.map(function (/** @type {any} */ c) {
            return { c: String(c) }
          }),
          "c",
          limit,
          false
        ).map(function (/** @type {ActivityData} */ c) {
          return c.c
        })
    }
    if (task.diagnostics === undefined) delete copy.diagnostics
    if (task.blockers === undefined) delete copy.blockers
    if (utf8Length(JSON.stringify(copy)) <= maxTaskBytes) return copy
  }
  return copy
}

/** Rows from OFFSET that fit in BUDGET bytes; at least one row while any remain.
 * @param {Array<ActivityData>} rows - bounded task rows
 * @param {number} offset - first row
 * @param {number} budget - bytes for the serialized rows
 * @returns {Array<ActivityData>} page
 */
function taskPage(rows, offset, budget) {
  /** @type {Array<ActivityData>} */
  var page = []
  var used = 2
  for (var i = offset; i < rows.length; i++) {
    var size = utf8Length(JSON.stringify(rows[i])) + 1
    if (page.length && used + size > budget) break
    page.push(rows[i])
    used += size
  }
  return page
}

if (typeof module !== "undefined")
  module.exports = {
    utf8Length,
    boundTask,
    taskPage,
    maxTaskBytes,
    validId,
    resumeCommand,
    sessionFor,
    project,
    notificationKey,
    notificationTransitions,
    notificationText
  }
