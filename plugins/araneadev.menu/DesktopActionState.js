// Pure per-family request generations and persistent keyed action feedback.

/** @typedef {{key:string,requestId:string,startedAt:number}} PendingAction */
/** @typedef {{status:string,message:string}} ActionFeedback */
/** @typedef {{sequence:number,pending:{[family:string]:PendingAction},feedback:{[key:string]:ActionFeedback}}} ActionState */

/**
 * Creates independent idle request maps.
 * @returns {ActionState} no pending requests or feedback
 */
function idle() {
  return { sequence: 0, pending: {}, feedback: {} }
}

/**
 * Begins one family request without mutating earlier snapshots.
 * @param {ActionState} state - current state
 * @param {string} family - dnd, audio or wallpaper
 * @param {string} key - canonical target key
 * @param {number} now - monotonic observation timestamp
 * @returns {{state:ActionState,requestId:string,accepted:boolean}} request decision
 */
function begin(state, family, key, now) {
  if (state.pending[family]) return { state: state, requestId: "", accepted: false }
  var sequence = state.sequence + 1
  var requestId = family + ":" + sequence
  var pending = Object.assign({}, state.pending)
  var feedback = Object.assign({}, state.feedback)
  pending[family] = { key: key, requestId: requestId, startedAt: now }
  feedback[key] = { status: "pending", message: "" }
  return {
    state: { sequence: sequence, pending: pending, feedback: feedback },
    requestId: requestId,
    accepted: true
  }
}

/**
 * Accepts only the outstanding request's completion, allowing safe retries.
 * @param {ActionState} state - current state
 * @param {string} family - affected action family
 * @param {string} requestId - completion identity
 * @param {boolean} ok - observed successful outcome
 * @param {string} message - retained context or actionable failure
 * @returns {ActionState} settled state, or the same state for obsolete callbacks
 */
function complete(state, family, requestId, ok, message) {
  var current = state.pending[family]
  if (!current || current.requestId !== requestId) return state
  var pending = Object.assign({}, state.pending)
  var feedback = Object.assign({}, state.feedback)
  delete pending[family]
  feedback[current.key] = { status: ok ? "confirmed" : "failed", message: message || "" }
  return { sequence: state.sequence, pending: pending, feedback: feedback }
}

if (typeof module !== "undefined") module.exports = { idle: idle, begin: begin, complete: complete }
