// Pure provider suggestion from local usage records. Shared by project launch
// surfaces so ranking agrees everywhere. No I/O; every "now" is passed in.
.import "../araneadev.agents/AgentsLogic.js" as AgentsLogic

/** @typedef {{[key:string]:any}} SuggestionData */

var PROVIDERS = [
  { id: "claude", label: "Claude Code" },
  { id: "codex", label: "Codex" }
]
var ALARMING = 0.9
var DECISIVE = 0.15
// Decimal threshold differences may round slightly below the inclusive gap.
var GAP_TOLERANCE = 1e-12

/**
 * Two-digit local clock part.
 * @param {number} n - hour or minute
 * @returns {string} zero-padded value
 */
function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

/**
 * The busiest window of one record, unknown once that window has reset.
 * @param {?SuggestionData} record - parsed usage record
 * @param {number} nowMs - current time
 * @returns {{fraction:number, headline:?string, resetsAt:?string}} fraction -1 when unknown
 */
function busiest(record, nowMs) {
  var unknown = { fraction: -1, headline: null, resetsAt: null }
  var limits = record && Array.isArray(record.limits) ? record.limits : []
  var best = null
  var bestFraction = -1
  for (var i = 0; i < limits.length; i++) {
    var limit = limits[i]
    if (!limit) continue
    var raw = limit.percent !== undefined ? limit.percent : limit.used
    // Validate before the shared normalizer's numeric coercion. A malformed
    // primary percent never falls back to used and never becomes known zero.
    if (typeof raw !== "number" || !isFinite(raw) || raw < 0) continue
    var f = AgentsLogic.ringFraction([limit])
    if (f > bestFraction) {
      bestFraction = f
      best = limit
    }
  }
  if (!best) return unknown
  var reset = Date.parse(best.resetsAt)
  if (isFinite(reset) && reset <= nowMs) return unknown
  return {
    fraction: bestFraction,
    headline: String(best.label || ""),
    resetsAt: best.resetsAt || null
  }
}

/**
 * Short human reason for one provider option.
 * @param {SuggestionData} option - ranked option
 * @param {boolean} last - whether this project last used it
 * @returns {string} reason text
 */
function reasonFor(option, last) {
  var text
  if (option.fraction < 0) text = "Not known yet"
  else {
    var pct = Math.round(option.fraction * 100)
    if (option.fraction >= 0.8 && option.headline) {
      text = pct + "% of " + option.headline
      var reset = Date.parse(option.resetsAt)
      if (isFinite(reset)) {
        var d = new Date(reset)
        text += " · resets " + pad(d.getHours()) + ":" + pad(d.getMinutes())
      }
    } else text = pct + "% used"
  }
  return last ? text + " · last used here" : text
}

/**
 * Rank installed providers by usage headroom, then project history.
 * @param {?Array<SuggestionData>} agents - installed agent CLIs from the tool probe
 * @param {?SuggestionData} usage - usage records keyed by provider
 * @param {?string} lastAgentId - provider last started for this project
 * @param {number} nowMs - current time
 * @returns {{suggestedId:?string, options:Array<SuggestionData>}} suggestion in canonical provider order
 */
function suggest(agents, usage, lastAgentId, nowMs) {
  var installed = Array.isArray(agents) ? agents : []
  var records = usage || {}
  var options = PROVIDERS.map(function (p) {
    var probe = installed.filter(function (a) {
      return a && a.id === p.id
    })[0]
    var window = busiest(records[p.id], nowMs)
    var option = {
      id: p.id,
      label: (probe && probe.label) || p.label,
      available: !!probe && probe.available !== false,
      fraction: window.fraction,
      headline: window.headline,
      resetsAt: window.resetsAt,
      reason: ""
    }
    option.reason = reasonFor(option, p.id === lastAgentId)
    return option
  })
  var pool = options.filter(function (o) {
    return o.available
  })
  var pick = null
  if (pool.length === 1) pick = pool[0]
  else if (pool.length === 2) {
    var a = pool[0]
    var b = pool[1]
    var calm = pool.filter(function (o) {
      return o.fraction >= 0 && o.fraction < ALARMING
    })
    if (calm.length === 1) pick = calm[0]
    else if (
      a.fraction >= 0 &&
      b.fraction >= 0 &&
      Math.abs(a.fraction - b.fraction) + GAP_TOLERANCE >= DECISIVE
    )
      pick = a.fraction < b.fraction ? a : b
    else
      pick =
        pool.filter(function (o) {
          return o.id === lastAgentId
        })[0] || pool[0]
  }
  return { suggestedId: pick ? pick.id : null, options: options }
}

if (typeof module !== "undefined") module.exports = { suggest }
