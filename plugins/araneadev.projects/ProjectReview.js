/** @typedef {{[key:string]:any}} ReviewData */

/** Reported states that mean the agent has stopped and handed work back. */
var FINISHED = ["finished", "ready-for-review", "failed"]

/**
 * Tasks associated with one checkout, oldest report first.
 * @param {Array<ReviewData>} tasks - agent tasks
 * @param {string} projectId - project id
 * @param {string} checkoutId - checkout id
 * @returns {Array<ReviewData>} matching tasks sorted by lastReceivedAt ascending
 */
function tasksFor(tasks, projectId, checkoutId) {
  return (tasks || [])
    .filter(function (t) {
      var a = t && t.association
      return (
        !!a && a.status === "registered" && a.projectId === projectId && a.checkoutId === checkoutId
      )
    })
    .sort(function (a, b) {
      return (a.lastReceivedAt || 0) - (b.lastReceivedAt || 0)
    })
}

/**
 * The most recent task that has finished.
 * @param {Array<ReviewData>} tasks - tasks sorted or not
 * @returns {?ReviewData} latest finished task or null
 */
function latestFinished(tasks) {
  /** @type {?ReviewData} */
  var best = null
  ;(tasks || []).forEach(function (t) {
    if (FINISHED.indexOf(t.reportedState) < 0) return
    if (!best || (t.lastReceivedAt || 0) >= (best.lastReceivedAt || 0)) best = t
  })
  return best
}

/**
 * Where a task checkout stands for review.
 * @param {ReviewData} checkout - {id, primary, review?}
 * @param {Array<ReviewData>} tasks - tasks already associated with this checkout
 * @param {?ReviewData} review - helper data, or null when not read yet
 * @returns {string} ready, working, needsInput, reviewed or none
 */
function reviewState(checkout, tasks, review) {
  if (!checkout || checkout.primary || !tasks || !tasks.length) return "none"
  var assoc = tasks.filter(function (t) {
    return t.association && t.association.status === "registered"
  })
  if (!assoc.length) return "none"
  if (
    assoc.some(function (t) {
      return t.reportedState === "needs-input"
    })
  )
    return "needsInput"
  if (
    assoc.some(function (t) {
      return t.reportedState === "working"
    })
  )
    return "working"
  var done = latestFinished(assoc)
  if (!done) return "none"
  var mark = checkout.review
  if (!mark) return "ready"
  if (review && review.head !== mark.reviewedHead) return "ready"
  if ((done.lastReceivedAt || 0) > (mark.reviewedTaskAt || 0)) return "ready"
  return "reviewed"
}

/**
 * Whether any task checkout of the project is ready for review.
 * @param {ReviewData} project - {id, checkouts}
 * @param {Array<ReviewData>} tasks - all agent tasks
 * @param {ReviewData} reviews - checkoutId to helper data
 * @returns {boolean} true when some non-primary checkout is ready
 */
function projectHasReview(project, tasks, reviews) {
  return ((project && project.checkouts) || []).some(function (/** @type {ReviewData} */ c) {
    return (
      !c.primary &&
      reviewState(c, tasksFor(tasks, project.id, c.id), (reviews && reviews[c.id]) || null) ===
        "ready"
    )
  })
}

/**
 * The project's first saved command that looks like a check.
 * @param {Array<ReviewData>} definitions - action definitions
 * @param {string} projectId - project id
 * @returns {?ReviewData} definition or null
 */
function checksAction(definitions, projectId) {
  return (
    (definitions || []).filter(function (d) {
      return (
        d.projectId === projectId &&
        d.kind === "command" &&
        /\b(test|tests|check|checks)\b/i.test(d.name || "")
      )
    })[0] || null
  )
}

/**
 * Plain label for the latest run of the checks action.
 * @param {?ReviewData} run - run record or null
 * @returns {string} passed, failed, running or not run
 */
function checksLabel(run) {
  var s = run && run.processState
  if (s === "succeeded") return "passed"
  if (s === "failed") return "failed"
  if (s === "pending" || s === "running") return "running"
  return "not run"
}

/**
 * Plain label for what the agent said about its own checks.
 * @param {?ReviewData} task - agent task
 * @returns {string} passed, failed or not reported
 */
function agentReportLabel(task) {
  var s = task && task.verification && task.verification.status
  if (s === "reported-pass") return "passed"
  if (s === "reported-fail") return "failed"
  return "not reported"
}

/**
 * Summary of how much changed.
 * @param {?ReviewData} review - helper data or null
 * @returns {string} for example "2 commits · 3 files", or empty
 */
function changesLine(review) {
  if (!review) return ""
  var c = (review.commits || []).length
  var f = (review.files || []).length
  return c + (c === 1 ? " commit" : " commits") + " · " + f + (f === 1 ? " file" : " files")
}

if (typeof module !== "undefined")
  module.exports = {
    tasksFor,
    latestFinished,
    reviewState,
    projectHasReview,
    checksAction,
    checksLabel,
    agentReportLabel,
    changesLine
  }
