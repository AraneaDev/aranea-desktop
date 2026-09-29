// Menu history behavior extracted from the generated MenuModel facade.

/**
 * Records an app id at the front of recent history.
 * @param {*} values - Existing recent ids.
 * @param {*} appId - App id to record.
 * @param {*} limit - Maximum number of ids.
 * @returns {Array<string>} Updated recent ids.
 */
function recordRecentApp(values, appId, limit) {
  var id = String(appId || "").trim()
  if (!id) return normalizeHistoryIds(values, limit)
  return normalizeHistoryIds([id].concat(Array.isArray(values) ? values : []), limit)
}

if (typeof module !== "undefined") module.exports = { recordRecentApp: recordRecentApp }

/**
 * Normalizes recent ids for the standalone history module.
 * @param {*} values - Candidate ids.
 * @param {*} limit - Maximum number of ids.
 * @returns {Array<string>} Normalized ids.
 */
function normalizeHistoryIds(values, limit) {
  var max = Number(limit)
  if (!isFinite(max) || max < 0) max = 12
  var rows = Array.isArray(values) ? values : []
  var out = []
  for (var i = 0; i < rows.length && out.length < Math.floor(max); i++) {
    var raw = rows[i]
    if (!(typeof raw === "string" || (typeof raw === "number" && isFinite(raw)))) continue
    var id = String(raw).trim()
    if (id && out.indexOf(id) === -1) out.push(id)
  }
  return out
}
