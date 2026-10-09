/** @typedef {{[key:string]:any}} ProjectData */

/**
 * Projects registry and fresh runtime evidence to common typed search records.
 * The last selected checkout is authoritative even if missing; no fallback can
 * silently substitute another worktree. Runtime bindings must already have been
 * checked against a fresh compositor/process snapshot by the single live owner.
 * Display strings never become executable arguments or canonical identities.
 * @param {ProjectData} registry - validated persistent registry snapshot
 * @param {ProjectData} runtime - availability and current-session bindings
 * @returns {Array<ProjectData>} deduplicated project records
 */
function records(registry, runtime) {
  var live = runtime || {}
  /** @type {{[key:string]:boolean}} */
  var seen = {}
  /** @type {Array<ProjectData>} */
  var result = []
  /** @type {Array<ProjectData>} */
  var projects = (registry || {}).projects || []
  /** @type {Array<ProjectData>} */
  var bindings = live.bindings || []
  projects.forEach(function (project) {
    if (!project || !project.id || seen["project:" + project.id]) return
    seen["project:" + project.id] = true
    /** @type {Array<ProjectData>} */
    var checkouts = project.checkouts || []
    var checkout = checkouts.filter(function (candidate) {
      return candidate.id === project.lastCheckoutId
    })[0]
    var resume = bindings.some(function (binding) {
      return (
        binding.projectId === project.id &&
        binding.checkoutId === project.lastCheckoutId &&
        !!live.sessionId &&
        binding.sessionId === live.sessionId &&
        binding.evidence &&
        binding.evidence.processVerified === true &&
        ["process-only", "process-app-id"].indexOf(binding.evidence.mode) >= 0 &&
        binding.pid > 0 &&
        typeof binding.address === "string" &&
        /^0x[0-9a-fA-F]+$/.test(binding.address) &&
        !/^0x0+$/.test(binding.address)
      )
    })
    result.push({
      key: "project:" + project.id,
      type: "project",
      label: project.name,
      target: { projectId: project.id, checkoutId: project.lastCheckoutId },
      detail: checkout
        ? checkout.path + (checkout.branch ? " · " + checkout.branch : "")
        : "Selected checkout unavailable",
      aliases: checkout ? [checkout.path, checkout.branch || ""] : [],
      available: !!checkout && !!live.availability && live.availability.compositor === true,
      action: resume ? "resume" : "open",
      pinned: false,
      recentRank: null,
      activeWorkspace: false
    })
  })
  return result
}

if (typeof module !== "undefined") module.exports = { records }
