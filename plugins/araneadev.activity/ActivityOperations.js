/** @typedef {{[key:string]:any}} ActivityOperation */

/** Accept a strict action and coalesce pending requests for the same native session.
 * @param {Array<ActivityOperation>} operations - owner records
 * @param {ActivityOperation} payload - action and taskId only, or
 *   dismiss-many with taskIds (1 to 700 unique IDs)
 * @param {string} id - new operation identifier
 * @param {string} ownerId - owner lifetime
 * @param {string} sessionKey - provider plus native session identity (a set
 *   dismissal passes its own operation ID, so sets never merge)
 * @returns {ActivityOperation} acceptance with retained operation
 */
function request(operations, payload, id, ownerId, sessionKey) {
  /** Refuse an empty, oversized, option-shaped or control-character task ID.
   * @param {any} value - candidate task ID
   * @returns {boolean} true when the ID is not acceptable
   */
  var badId = function (value) {
    return (
      typeof value !== "string" ||
      !value ||
      value.length > 256 ||
      /^[\s-]/.test(value) ||
      value.split("").some(function (character) {
        return character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127
      })
    )
  }
  var many = !!payload && payload.action === "dismiss-many"
  if (
    !payload ||
    (many
      ? Object.keys(payload).sort().join(",") !== "action,taskIds" ||
        !Array.isArray(payload.taskIds) ||
        !payload.taskIds.length ||
        payload.taskIds.length > 700 ||
        payload.taskIds.some(function (/** @type {any} */ value, /** @type {number} */ index) {
          return badId(value) || payload.taskIds.indexOf(value) !== index
        })
      : Object.keys(payload).sort().join(",") !== "action,taskId" ||
        ["focus", "reopen", "open-checkout", "dismiss"].indexOf(payload.action) < 0 ||
        badId(payload.taskId))
  )
    return {
      ok: false,
      operationId: null,
      error: {
        code: "INVALID_REQUEST",
        message: "Choose a task and a supported action.",
        recovery: "Refresh activity and select a task."
      }
    }
  var existing = operations.filter(function (op) {
    return (
      op.ownerId === ownerId &&
      op.sessionKey === sessionKey &&
      op.action === payload.action &&
      (op.state !== "completed" ||
        op.submissionPending === true ||
        op.submissionUnconfirmed === true)
    )
  })[0]
  var operation =
    existing ||
    Object.assign({}, payload, {
      id: id,
      ownerId: ownerId,
      sessionKey: sessionKey,
      state: "accepted",
      outcome: null,
      steps: [],
      error: null
    })
  return {
    ok: true,
    operationId: operation.id,
    operation: operation,
    reused: !!existing,
    error: null
  }
}

/** Observation never changes reported task state or turns a terminal into native proof.
 * @param {ActivityOperation} operation - accepted reopen
 * @param {?ActivityOperation} terminal - independent terminal observation
 * @param {?ActivityOperation} native - freshly validated native epoch evidence
 * @param {boolean} expired - bounded observer deadline reached
 * @returns {ActivityOperation} progress or terminal copy
 */
function observe(operation, terminal, native, expired) {
  var resumed =
    native &&
    native.nativeVerified === true &&
    native.provider + ":" + native.providerSessionId === operation.sessionKey &&
    native.producerEpoch !== operation.priorEpoch &&
    native.observedAt >= operation.acceptedAt
  var steps = [
    {
      role: "terminal",
      status: terminal && terminal.status === "observed" ? "observed" : "unconfirmed",
      binding: (terminal && terminal.binding) || null
    },
    {
      role: "session",
      status: resumed ? "observed" : "unconfirmed",
      code: resumed ? null : "SESSION_UNCONFIRMED"
    }
  ]
  var complete = resumed && terminal && terminal.status === "observed"
  return Object.assign({}, operation, {
    state: complete || expired ? "completed" : "observing",
    outcome: complete ? "observed" : expired ? "partial" : null,
    steps: steps,
    terminal: terminal || null,
    native: resumed ? native : null,
    error:
      expired && !complete
        ? {
            code: "SESSION_UNCONFIRMED",
            message: "Launch started; the resumed session is not confirmed.",
            recovery: "Check again, or look at the terminal it runs in."
          }
        : null
  })
}
if (typeof module !== "undefined") module.exports = { request, observe }
