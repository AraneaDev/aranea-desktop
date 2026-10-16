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
        : "Selected checkout not available",
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

/**
 * Project-specific provider suggestion callback.
 * @callback ProjectChoiceFor
 * @param {ProjectData} project - project identity and saved tools
 * @returns {ProjectData} installed options and suggested provider
 */

/**
 * One explicit launcher action per installed provider and project.
 * Suggestion is presentation metadata; the target always names the provider.
 * @param {ProjectData} registry - validated persistent registry snapshot
 * @param {ProjectData} runtime - fresh owner availability
 * @param {ProjectChoiceFor} choiceFor - suggestion per project
 * @returns {Array<ProjectData>} agent start records
 */
function agentRecords(registry, runtime, choiceFor) {
  var live = runtime || {}
  /** @type {Array<ProjectData>} */
  var result = []
  /** @type {{[key:string]:boolean}} */
  var seen = {}
  /** @type {Array<ProjectData>} */
  var projects = (registry || {}).projects || []
  projects.forEach(function (project) {
    if (!project || !project.id) return
    /** @type {Array<ProjectData>} */
    var checkouts = project.checkouts || []
    var checkout = checkouts.filter(function (candidate) {
      return candidate.id === project.lastCheckoutId
    })[0]
    var choice = choiceFor(project) || { options: [] }
    /** @type {Array<ProjectData>} */
    var options = (choice.options || []).filter(function (/** @type {ProjectData} */ option) {
      return option && option.available === true && ["claude", "codex"].indexOf(option.id) >= 0
    })
    options.sort(function (/** @type {ProjectData} */ a, /** @type {ProjectData} */ b) {
      return Number(b.id === choice.suggestedId) - Number(a.id === choice.suggestedId)
    })
    options.forEach(function (option) {
      var key = "project-agent:" + project.id + ":" + option.id
      if (seen[key]) return
      seen[key] = true
      var suggested = option.id === choice.suggestedId
      result.push({
        key: key,
        type: "project-agent",
        label: "Start " + (option.id === "claude" ? "Claude" : "Codex") + " in " + project.name,
        target: { projectId: project.id, checkoutId: project.lastCheckoutId, agentId: option.id },
        detail: (suggested ? "Suggested · " : "") + (option.reason || "Not known yet"),
        aliases: ["agent", option.id, project.name],
        available: !!checkout && !!live.availability && live.availability.compositor === true,
        action: "agent",
        suggested: suggested,
        pinned: false,
        recentRank: null,
        activeWorkspace: false
      })
    })
  })
  return result
}

if (typeof module !== "undefined") module.exports = { records, agentRecords, environmentRecords }

/** Exact saved environment Return records; owner-supplied observed roles retain fresh proof.
 * @param {ProjectData} registry - saved project names
 * @param {ProjectData} runtime - shared owner snapshot
 * @returns {Array<ProjectData>} typed focus-only targets
 */
function environmentRecords(registry, runtime) {
  return ((runtime || {}).environments || []).map(function (/** @type {ProjectData} */ e) {
    var project = ((registry || {}).projects || []).find(function (/** @type {ProjectData} */ p) {
      return p.id === e.projectId
    })
    /** @type {ProjectData} */
    var record = {
      key: "project-environment:" + e.id,
      type: "project-environment",
      label: "Return " + e.profileSnapshot.name + (project ? " · " + project.name : ""),
      target: { projectId: e.projectId, environmentId: e.id },
      detail:
        "Workspace " +
        e.workspaceId +
        " · " +
        (e.checkoutSnapshot.branch || "detached") +
        " at launch · " +
        e.checkoutSnapshot.path +
        " · " +
        ((e.observedRoles || []).length
          ? "Found: " + e.observedRoles.join(", ")
          : "Tools not checked"),
      aliases: [e.profileSnapshot.name, e.checkoutSnapshot.path, e.checkoutSnapshot.branch || ""],
      available: !!runtime.availability && runtime.availability.compositor === true,
      action: "return",
      pinned: false,
      recentRank: null,
      activeWorkspace: false
    }
    return record
  })
}
