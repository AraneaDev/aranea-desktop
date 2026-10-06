// Health decision and compact resource values. Unknown readings stay unknown.

/**
 * Describes availability before status or issue count.
 * @param {boolean} available - whether the service has metrics
 * @param {string} status - existing service severity
 * @param {?Array<object>} problems - open annotated problems
 * @returns {{label: string, tone: string}} summary caption and semantic tone
 */
function summaryFor(available, status, problems) {
  if (!available) return { label: "Health data unavailable", tone: "unavailable" }
  var count = (problems || []).length
  if (count > 0)
    return {
      label: count + (count === 1 ? " issue needs attention" : " issues need attention"),
      tone: status === "critical" ? "critical" : "attention"
    }
  return { label: "No detected problems", tone: "healthy" }
}

/**
 * Accepts a known, finite, non-negative numeric reading.
 * @param {*} value - sampled value
 * @returns {?number} value, or null without a valid reading
 */
function knownNumber(value) {
  if (
    value === null ||
    value === undefined ||
    (typeof value !== "number" && typeof value !== "string") ||
    (typeof value === "string" && value.trim() === "")
  )
    return null
  var number = Number(value)
  return isFinite(number) && number >= 0 ? number : null
}

/**
 * Selects known CPU/memory values and the fullest valid mounted disk.
 * @param {?{cpu?: *, mem?: {memUsed?: *, memTotal?: *}, diskRows?: Array<{target?: *, percent?: *}>}} metrics - service metrics
 * @returns {{cpu: ?number, memory: ?object, disk: ?object}} compact resources
 */
function resourceSummary(metrics) {
  var cpu = knownNumber(metrics && metrics.cpu)
  if (cpu !== null && cpu > 100) cpu = null
  var mem = metrics && metrics.mem
  var used = knownNumber(mem && mem.memUsed)
  var total = knownNumber(mem && mem.memTotal)
  var memory =
    used !== null && total !== null && total > 0 && used <= total
      ? { used: used, total: total }
      : null
  var disk = null
  var rows = metrics && metrics.diskRows ? metrics.diskRows : []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var percent = knownNumber(row && row.percent)
    if (
      row &&
      typeof row.target === "string" &&
      row.target !== "" &&
      percent !== null &&
      percent <= 100 &&
      (!disk || percent > disk.percent)
    )
      disk = { target: row.target, percent: percent }
  }
  return { cpu: cpu, memory: memory, disk: disk }
}

/**
 * Adds disclosure headings after every actionable problem.
 * @param {?Array<object>} problems - live problems, already sorted
 * @returns {Array<object>} keyed keyboard navigation stops
 */
function keyboardStops(problems) {
  return (problems || []).concat([{ key: "details:resources" }, { key: "details:processes" }])
}

if (typeof module !== "undefined")
  module.exports = {
    summaryFor: summaryFor,
    resourceSummary: resourceSummary,
    knownNumber: knownNumber,
    keyboardStops: keyboardStops
  }
