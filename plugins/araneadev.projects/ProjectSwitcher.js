.import "ProjectsNavigation.js" as Navigation
.import "ProjectProfiles.js" as Profiles
.import "ProjectReview.js" as Review

/** @typedef {{kind:string,label:string,target:{[key:string]:*}}} SwitcherAction */
/** @typedef {{id:string,name:string,branch:string,path:string,action:SwitcherAction,startTarget:?{[key:string]:*}}} SwitcherRow */

/**
 * Newest environment of a project that still has open windows.
 * Highest generation wins; ties and missing generations fall to the last one.
 * @param {{[key:string]:*}|null} runtime Projects runtime snapshot.
 * @param {string} projectId Project identity.
 * @returns {?{[key:string]:*}} Returnable environment or null.
 */
function returnable(runtime, projectId) {
  /** @type {?{[key:string]:*}} */
  var best = null
  ;((runtime || {}).environments || []).forEach(function (/** @type {{[key:string]:*}} */ e) {
    if (e.projectId !== projectId || !(e.observedRoles || []).length) return
    if (!best || (e.generation || 0) >= (best.generation || 0)) best = e
  })
  return best
}

/**
 * The ready task checkout whose latest finished task is newest.
 * @param {{[key:string]:*}} project Registered project.
 * @param {Array<{[key:string]:*}>} tasks Agent tasks.
 * @param {{[key:string]:*}} reviews Review helper data by checkout id.
 * @returns {?{[key:string]:*}} Checkout to review or null.
 */
function reviewCheckout(project, tasks, reviews) {
  /** @type {?{[key:string]:*}} */
  var best = null
  var bestAt = -1
  ;((project && project.checkouts) || []).forEach(function (/** @type {{[key:string]:*}} */ c) {
    if (c.primary) return
    var mine = Review.tasksFor(tasks, project.id, c.id)
    if (Review.reviewState(c, mine, (reviews && reviews[c.id]) || null) !== "ready") return
    var at = (Review.latestFinished(mine) || {}).lastReceivedAt || 0
    if (!best || at > bestAt) {
      best = c
      bestAt = at
    }
  })
  return best
}

/**
 * Quick switcher rows in navigation order, each with its Enter action.
 * @param {Array<{[key:string]:*}>|null} projects Registered projects.
 * @param {{[key:string]:*}|null} navigation Saved navigation metadata.
 * @param {string} query Search text.
 * @param {{[key:string]:*}|null} runtime Projects runtime snapshot.
 * @param {{[key:string]:*}} tools Installed tool probe.
 * @param {{[key:string]:*}} [gitCache] Cached branch observations.
 * @param {Array<{[key:string]:*}>} [tasks] Agent tasks.
 * @param {{[key:string]:*}} [reviews] Review helper data by checkout id.
 * @returns {SwitcherRow[]} Rows with Review, Return, Start or Set up actions.
 */
function switcherRows(projects, navigation, query, runtime, tools, gitCache, tasks, reviews) {
  var list = projects || []
  return Navigation.rows(list, navigation, query, null, gitCache).map(function (row) {
    var project = list.filter(function (candidate) {
      return candidate.id === row.id
    })[0]
    var profile = Profiles.primary(project, tools)
    var start = profile
      ? {
          projectId: row.id,
          checkoutId: project.lastCheckoutId,
          profileId: profile.id,
          profileRevision: profile.revision
        }
      : null
    var env = returnable(runtime, row.id)
    var toReview = reviewCheckout(project, tasks || [], reviews || {})
    /** @type {SwitcherAction} */
    var action = toReview
      ? {
          kind: "review",
          label: "Review · " + (toReview.branch || "detached"),
          target: { projectId: row.id, checkoutId: toReview.id }
        }
      : env
      ? {
          kind: "return",
          label: "Return · workspace " + env.workspaceId,
          target: { projectId: row.id, environmentId: env.id }
        }
      : profile
        ? { kind: "start", label: "Start · " + profile.name, target: start }
        : { kind: "setup", label: "Set up first", target: { projectId: row.id } }
    return {
      id: row.id,
      name: row.name,
      branch: row.branch,
      path: row.path,
      review: !!toReview,
      action: action,
      startTarget: start
    }
  })
}

if (typeof module !== "undefined") module.exports = { switcherRows, returnable }
