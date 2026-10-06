/** @typedef {{configured?:string|null,applied?:string|null,availability?:string,application?:string}} MotionState */
/** @typedef {{activeId?:string|null,availability?:string}} WallpaperState */
/** @typedef {{enabled?:boolean|null,applied?:boolean|null,availability?:string,dawn?:string|null,day?:string|null,dusk?:string|null,night?:string|null}} ScheduleState */
/** @typedef {{id:string,status?:string,availability?:string}} IntegrationState */
/** @typedef {{id:string,label?:string,path?:string,available:boolean}} WallpaperAsset */
/** @typedef {{monitor?:string|null,scale?:number|null,width?:number|null,height?:number|null,availability?:string,persistenceSupport?:string,configuredScale?:number|null}} DisplayState */
/** @typedef {{uiFamily:string,technicalFamily:string,families:Array<string>,monospaceFamilies:Array<string>,availability:string,catalogAvailable?:boolean}} FontsState */
/** @typedef {{fonts?:FontsState,display?:DisplayState,motion?:MotionState,wallpaper?:WallpaperState,schedule?:ScheduleState,integrations?:Array<IntegrationState>,wallpapers?:Array<WallpaperAsset>,integrationsAvailability?:string,wallpapersAvailability?:string}} SettingsState */
/** @typedef {{requested:string,monitor:string,width:number,height:number,expectedScale:number,effectiveScale?:number|null,confirmed:boolean,persistence:string}} DisplayScaleResult */
/** @typedef {{displayScale?:DisplayScaleResult}} MutationResult */
/** Normalize a requested settings destination.
 * @param {string} value Requested section.
 * @returns {string} Supported section.
 */
function normalizeSection(value) {
  return ["appearance", "display", "schedule", "integrations", "notifications"].indexOf(value) >= 0
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
/** Validate a typed custom scale without trimming or normalizing the request.
 * @param {string} value Typed scale.
 * @returns {{ok:boolean,message:string}} Validation result.
 */
function validateScale(value) {
  var valid =
    typeof value === "string" &&
    /^[0-9]+([.][0-9]+)?$/.test(value) &&
    Number(value) >= 1 &&
    Number(value) <= 4
  return {
    ok: valid,
    message: valid ? "" : "Enter a decimal scale from 1 to 4, such as 2.5 or 2.667."
  }
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
  if (section === "fonts") {
    var fonts = state.fonts
    if (
      operation !== "configure fonts" ||
      args.length !== 2 ||
      !fonts ||
      (fonts.availability !== "available" &&
        !(fonts.catalogAvailable === true && args[0] === "" && args[1] === "")) ||
      !Array.isArray(fonts.families) ||
      !Array.isArray(fonts.monospaceFamilies) ||
      typeof args[0] !== "string" ||
      typeof args[1] !== "string" ||
      (args[0] !== "" && fonts.families.indexOf(args[0]) < 0) ||
      (args[1] !== "" && fonts.monospaceFamilies.indexOf(args[1]) < 0)
    )
      return null
  } else if (section === "display-scale") {
    if (
      operation !== "set display-scale" ||
      args.length !== 1 ||
      !validateScale(args[0]).ok ||
      !state.display ||
      state.display.availability !== "available" ||
      !/^[A-Za-z0-9._-]+$/.test(state.display.monitor || "")
    )
      return null
    return [path, "set", "display-scale", args[0], "--monitor", state.display.monitor, "--json"]
  } else if (section === "integration") {
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
      result: value.result || null,
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
 * @param {MutationResult} [result] Mutation confirmation metadata.
 * @returns {string} User-facing result.
 */
function outcome(operation, args, state, succeeded, result) {
  state = state || {}
  if (!succeeded) {
    var failedMotion = operation === "set motion" && state.motion
    if (!failedMotion || failedMotion.configured !== args[0]) return "Failed"
    return (
      "Saved · live application " +
      (["on", "off"].indexOf(failedMotion.applied) >= 0 && failedMotion.applied !== args[0]
        ? "failed"
        : "unconfirmed")
    )
  }
  if (operation === "configure fonts")
    return state.fonts &&
      state.fonts.uiFamily === args[0] &&
      state.fonts.technicalFamily === args[1]
      ? "Applied"
      : "Save not confirmed"
  if (operation === "set display-scale") {
    var display = state.display || {}
    var scale = result && result.displayScale
    if (
      !scale ||
      scale.confirmed !== true ||
      scale.requested !== args[0] ||
      display.availability !== "available" ||
      display.monitor !== scale.monitor ||
      typeof display.scale !== "number" ||
      typeof scale.expectedScale !== "number" ||
      Math.abs(display.scale - scale.expectedScale) >= 0.00001 ||
      typeof scale.width !== "number" ||
      typeof scale.height !== "number" ||
      display.width !== scale.width ||
      display.height !== scale.height
    )
      return "Application not confirmed"
    return (
      "Applied · " +
      display.scale +
      " · " +
      (scale.persistence === "persisted" &&
      display.persistenceSupport === "supported" &&
      typeof display.configuredScale === "number" &&
      Math.abs(display.configuredScale - scale.expectedScale) < 0.00001
        ? "saved"
        : scale.persistence === "session-only"
          ? "session only"
          : "persistence unconfirmed")
    )
  }
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
    height: Math.max(1, Math.min(460 * scale, screenHeight - 48 * scale)),
    compact: width < 720 * scale
  }
}
if (typeof module !== "undefined")
  module.exports = {
    normalizeSection: normalizeSection,
    validateSchedule: validateSchedule,
    validateScale: validateScale,
    acceptRead: acceptRead,
    command: command,
    parseResponse: parseResponse,
    outcome: outcome,
    geometry: geometry
  }
