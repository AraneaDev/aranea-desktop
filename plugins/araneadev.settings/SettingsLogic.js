/** @typedef {{configured?:string|null,applied?:string|null,availability?:string,application?:string}} MotionState */
/** @typedef {{activeId?:string|null,availability?:string}} WallpaperState */
/** @typedef {{enabled?:boolean|null,applied?:boolean|null,availability?:string,dawn?:string|null,day?:string|null,dusk?:string|null,night?:string|null}} ScheduleState */
/** @typedef {{id:string,status?:string,availability?:string}} IntegrationState */
/** @typedef {{id:string,label?:string,path?:string,available:boolean}} WallpaperAsset */
/** @typedef {{motion?:MotionState,wallpaper?:WallpaperState,schedule?:ScheduleState,integrations?:Array<IntegrationState>,wallpapers?:Array<WallpaperAsset>,integrationsAvailability?:string,wallpapersAvailability?:string}} SettingsState */
/** Normalize a requested settings destination.
 * @param {string} value Requested section.
 * @returns {string} Supported section.
 */
function normalizeSection(value) {
  return ["appearance", "schedule", "integrations", "notifications"].indexOf(value) >= 0
    ? value
    : "appearance"
}
/** Validate four strictly ascending phase times without evaluating user text.
 * @param {Array<string>} times Phase times.
 * @returns {{ok:boolean,message:string}} Validation result.
 */
function validateSchedule(times) {
  if (!Array.isArray(times) || times.length !== 4)
    return { ok: false, message: "Enter all four phase times." }
  var previous = -1
  for (var i = 0; i < times.length; i++) {
    if (typeof times[i] !== "string" || !/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(times[i]))
      return { ok: false, message: "Use HH:MM with a valid 24-hour time." }
    var minute = Number(times[i].slice(0, 2)) * 60 + Number(times[i].slice(3))
    if (minute <= previous)
      return { ok: false, message: "Phase times must run from dawn to night in ascending order." }
    previous = minute
  }
  return { ok: true, message: "" }
}
/** Reject stale asynchronous reads.
 * @param {number} currentRevision Latest dispatched revision.
 * @param {number} responseRevision Completed revision.
 * @returns {boolean} Whether state may change.
 */
function acceptRead(currentRevision, responseRevision) {
  return currentRevision === responseRevision
}
/** Build an allowlisted argv; unavailable controls cannot start mutations.
 * @param {string} path Adapter path.
 * @param {string} operation Requested operation.
 * @param {Array<string>} args Arguments.
 * @param {SettingsState} state Observed backend state.
 * @returns {Array<string>|null} Command or rejected request.
 */
function command(path, operation, args, state) {
  args = args || []
  state = state || {}
  if (operation === "status" && args.length === 0) return [path, "status", "--json"]
  var section = operation.split(" ")[1]
  if (section === "integration") {
    if (
      operation !== "set integration" ||
      args.length !== 2 ||
      ["active", "inactive"].indexOf(args[1]) < 0 ||
      state.integrationsAvailability !== "available"
    )
      return null
    var item = (state.integrations || []).filter(function (v) {
      return v.id === args[0] && v.availability === "available"
    })[0]
    if (!item) return null
  } else if (section === "wallpaper") {
    if (
      operation !== "set wallpaper" ||
      args.length !== 1 ||
      state.wallpapersAvailability !== "available"
    )
      return null
    var asset = (state.wallpapers || []).filter(function (v) {
      return v.id === args[0] && v.available === true
    })[0]
    if (!asset) return null
  } else if (section === "schedule" || section === "motion") {
    if (!state[section] || state[section].availability !== "available") return null
    if (operation === "configure schedule") {
      if (!validateSchedule(args).ok) return null
    } else if (
      operation !== "set " + section ||
      args.length !== 1 ||
      ["on", "off"].indexOf(args[0]) < 0
    )
      return null
  } else return null
  return [path].concat(operation.split(" "), args, ["--json"])
}
/** Parse the versioned envelope, retaining partial readback on owner failure.
 * @param {string} stdout Adapter output.
 * @param {number} exitCode Process exit.
 * @returns {object} Safe envelope.
 */
function parseResponse(stdout, exitCode) {
  try {
    var value = JSON.parse(stdout)
    if (
      !value ||
      value.schemaVersion !== 1 ||
      typeof value.ok !== "boolean" ||
      (value.state !== null && typeof value.state !== "object")
    )
      throw new Error("Invalid envelope")
    return {
      ok: exitCode === 0 && value.ok,
      state: value.state,
      error:
        value.error ||
        (exitCode !== 0 ? { code: "HELPER_FAILED", message: "The settings command failed." } : null)
    }
  } catch (e) {
    return {
      ok: false,
      state: null,
      error: {
        code: "READ_FAILED",
        message: "Settings unavailable. Retry to read the current state."
      }
    }
  }
}
/** Describe observed application independently of persistence success.
 * @param {string} operation Mutation.
 * @param {Array<string>} args Requested values.
 * @param {SettingsState} state Owner readback.
 * @param {boolean} succeeded Helper success, including unrelated partial reads.
 * @returns {string} User-facing result.
 */
function outcome(operation, args, state, succeeded) {
  if (!succeeded) return "Failed"
  state = state || {}
  if (operation === "set motion") {
    var motion = state.motion || {}
    if (motion.configured !== args[0]) return "Save not confirmed"
    if (motion.applied === args[0]) return "Applied"
    return (
      "Saved · application " +
      (motion.application === "deferred"
        ? "deferred"
        : motion.applied === null || motion.applied === undefined
          ? "unavailable"
          : "pending")
    )
  }
  if (operation === "set wallpaper")
    return state.wallpaper && state.wallpaper.activeId === args[0]
      ? "Applied"
      : "Application not confirmed"
  if (operation === "set integration") {
    var item = (state.integrations || []).filter(function (v) {
      return v.id === args[0]
    })[0]
    return item && item.status === args[1] ? "Applied" : "Application not confirmed"
  }
  var schedule = state.schedule || {}
  if (operation === "configure schedule") {
    if (
      JSON.stringify([schedule.dawn, schedule.day, schedule.dusk, schedule.night]) !==
      JSON.stringify(args)
    )
      return "Save not confirmed"
    if (schedule.enabled === false) return "Saved"
  } else if (schedule.enabled !== (args[0] === "on")) return "Save not confirmed"
  return schedule.applied === schedule.enabled && typeof schedule.enabled === "boolean"
    ? "Applied"
    : "Saved · application " +
        (schedule.applied === null || schedule.applied === undefined ? "unavailable" : "pending")
}
/** Cap desired geometry with scaled screen margins.
 * @param {number} screenWidth Available width.
 * @param {number} screenHeight Available height.
 * @param {number} scale Host logical-unit scale.
 * @returns {object} Geometry and navigation mode.
 */
function geometry(screenWidth, screenHeight, scale) {
  scale = scale || 1
  var width = Math.max(1, Math.min(840 * scale, screenWidth - 48 * scale))
  return {
    width: width,
    height: Math.max(1, Math.min(620 * scale, screenHeight - 48 * scale)),
    compact: width < 720 * scale
  }
}
if (typeof module !== "undefined")
  module.exports = {
    normalizeSection: normalizeSection,
    validateSchedule: validateSchedule,
    acceptRead: acceptRead,
    command: command,
    parseResponse: parseResponse,
    outcome: outcome,
    geometry: geometry
  }
