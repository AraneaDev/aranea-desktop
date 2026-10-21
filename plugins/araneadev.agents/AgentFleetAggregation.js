// Pure fleet reduction. The lifecycle owner supplies calendar dates, sanitized
// device identities and timestamps; this module never reads the clock or I/O.

/**
 * @typedef {object} ProviderAccumulator
 * @property {string} providerId - stable provider key
 * @property {string} providerName - first supplied nonempty name
 * @property {boolean} ready - whether a snapshot reports readiness
 * @property {boolean} hasLocalStats - whether any snapshot supports local stats
 * @property {boolean} hasPromptStats - whether any snapshot supports prompts
 * @property {number} todayPrompts - combined daily prompts
 * @property {number} todaySessions - combined daily sessions
 * @property {number} todayTotalTokens - combined daily tokens
 * @property {{[key: string]: number}} todayTokensByModel - daily model counters
 * @property {{[key: string]: number}} recentByDay - counters inside the supplied window
 * @property {number} totalPrompts - lifetime prompts
 * @property {number} totalSessions - lifetime sessions
 * @property {number} activeDays - widest legacy active-day count
 * @property {{[key: string]: boolean}} activeDates - union of recorded active dates
 * @property {{[key: string]: {[counter: string]: number}}} modelUsage - model token buckets
 * @property {{[key: string]: boolean}} devices - unique contributing device IDs
 */

/**
 * Converts a counter to a finite rounded number.
 * @param {*} value - incoming counter, including legacy string values
 * @returns {number} the rounded counter, or zero
 */
function numberValue(value) {
  var n = Number(value || 0)
  return isFinite(n) ? Math.round(n) : 0
}

/**
 * Creates the standard zeroed model token counters.
 * @returns {{[key: string]: number}} the new token bucket
 */
function emptyTokenBucket() {
  return {
    inputTokens: 0,
    outputTokens: 0,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0
  }
}

// Device-scoped stats add up across machines; account-scoped stats
// (Fireworks' billing API) are replicas of the same upstream truth on
// every synced device, so the widest value wins; summing them would
// double every token per machine.
/**
 * Adds device counters or takes the widest replicated account counter.
 * @param {boolean} additive - whether the incoming snapshot is device scoped
 * @param {*} current - the accumulated counter
 * @param {*} value - the incoming counter
 * @returns {number} the combined finite rounded counter
 */
function combineNumber(additive, current, value) {
  return additive
    ? numberValue(current) + numberValue(value)
    : Math.max(numberValue(current), numberValue(value))
}

// Combines every numeric key of source into target with combineNumber.
/**
 * Merges every source counter, including model-specific extension keys.
 * @param {boolean} additive - whether incoming counters add
 * @param {{[key: string]: number}} target - the counters to mutate
 * @param {{[key: string]: *}} source - incoming counters, or falsy
 * @returns {void}
 */
function combineObjectNumbers(additive, target, source) {
  if (!source) return
  for (let key in source) target[key] = combineNumber(additive, target[key], source[key])
}

/**
 * Initializes one provider with a zero-filled calendar window.
 * @param {string} id - provider key
 * @param {string[]} dates - recent calendar dates in output order
 * @returns {ProviderAccumulator} a fresh mutable accumulator
 */
function createProviderAccumulator(id, dates) {
  /** @type {{[key: string]: number}} */
  var recentByDay = {}
  for (let d = 0; d < dates.length; d++) recentByDay[dates[d]] = 0
  return {
    providerId: id,
    providerName: "",
    ready: false,
    hasLocalStats: false,
    hasPromptStats: false,
    todayPrompts: 0,
    todaySessions: 0,
    todayTotalTokens: 0,
    todayTokensByModel: {},
    recentByDay: recentByDay,
    totalPrompts: 0,
    totalSessions: 0,
    activeDays: 0,
    activeDates: {},
    modelUsage: {},
    devices: {}
  }
}

/**
 * Merges one device's provider record using its incoming scope.
 * @param {ProviderAccumulator} acc - provider state to mutate
 * @param {{[key: string]: *}} stats - parsed provider record or an empty object
 * @param {string} device - already sanitized device identity
 * @returns {void}
 */
function mergeProviderSnapshot(acc, stats, device) {
  acc.devices[device] = true
  if (stats.providerName && acc.providerName === "") acc.providerName = String(stats.providerName)
  acc.ready = acc.ready || stats.ready === true
  acc.hasLocalStats = acc.hasLocalStats || stats.hasLocalStats !== false
  // Snapshots from before the field existed only came from agents that
  // count prompts, so a missing value reads as true.
  acc.hasPromptStats = acc.hasPromptStats || stats.hasPromptStats !== false
  let additive = String(stats.scope || "device") !== "account"
  acc.todayPrompts = combineNumber(additive, acc.todayPrompts, stats.todayPrompts)
  acc.todaySessions = combineNumber(additive, acc.todaySessions, stats.todaySessions)
  acc.todayTotalTokens = combineNumber(additive, acc.todayTotalTokens, stats.todayTotalTokens)
  acc.totalPrompts = combineNumber(additive, acc.totalPrompts, stats.totalPrompts)
  acc.totalSessions = combineNumber(additive, acc.totalSessions, stats.totalSessions)
  // Active days overlap between machines, so union the dates rather than
  // summing counts. Snapshots written before activeDates existed only
  // carry a count; the widest one stands in for them.
  let activeDates = Array.isArray(stats.activeDates) ? stats.activeDates : []
  for (let ad = 0; ad < activeDates.length; ad++) acc.activeDates[String(activeDates[ad])] = true
  acc.activeDays = Math.max(acc.activeDays, numberValue(stats.activeDays))
  combineObjectNumbers(additive, acc.todayTokensByModel, stats.todayTokensByModel || {})

  let recent = Array.isArray(stats.recentDays) ? stats.recentDays : []
  for (let r = 0; r < recent.length; r++) {
    let day = recent[r] || {}
    let date = String(day.date || "")
    if (acc.recentByDay[date] !== undefined)
      acc.recentByDay[date] = combineNumber(additive, acc.recentByDay[date], day.messageCount)
  }

  let usage = stats.modelUsage || {}
  for (let modelId in usage) {
    let bucket = acc.modelUsage[modelId]
    if (!bucket) bucket = acc.modelUsage[modelId] = emptyTokenBucket()
    combineObjectNumbers(additive, bucket, usage[modelId] || {})
  }
}

/**
 * Projects merged counters and sorted contributing devices into the wire shape.
 * @param {ProviderAccumulator} acc - merged provider state
 * @param {string[]} dates - recent calendar dates in output order
 * @returns {{[key: string]: *}} the public provider aggregate
 */
function projectProvider(acc, dates) {
  let recentDays = []
  for (let di = 0; di < dates.length; di++)
    recentDays.push({
      date: dates[di],
      messageCount: acc.recentByDay[dates[di]] || 0
    })
  let providerDevices = Object.keys(acc.devices).sort()
  return {
    providerId: acc.providerId,
    providerName: acc.providerName,
    ready: acc.ready || providerDevices.length > 0,
    hasLocalStats: acc.hasLocalStats,
    hasPromptStats: acc.hasPromptStats,
    todayPrompts: acc.todayPrompts,
    todaySessions: acc.todaySessions,
    todayTotalTokens: acc.todayTotalTokens,
    todayTokensByModel: acc.todayTokensByModel,
    recentDays: recentDays,
    totalPrompts: acc.totalPrompts,
    totalSessions: acc.totalSessions,
    activeDays: Math.max(acc.activeDays, Object.keys(acc.activeDates).length),
    modelUsage: acc.modelUsage,
    deviceCount: providerDevices.length,
    devices: providerDevices
  }
}

/**
 * Reduces snapshots without changing input records or acquiring runtime inputs.
 * Provider encounter order and each incoming record's scope remain significant.
 * @param {{deviceId: string, providers?: {[key: string]: *}}[]} snapshots - snapshots with sanitized identities
 * @param {string[]} dates - recent local calendar dates, today last
 * @param {string} updatedAt - ISO timestamp supplied by the lifecycle owner
 * @param {number} updatedAtMs - epoch timestamp supplied by the lifecycle owner
 * @returns {{[key: string]: *}} the fleet envelope with one aggregate per provider
 */
function aggregateSnapshots(snapshots, dates, updatedAt, updatedAtMs) {
  /** @type {{[key: string]: boolean}} */
  var devices = {}
  /** @type {{[key: string]: ProviderAccumulator}} */
  var providers = {}
  for (let i = 0; i < snapshots.length; i++) {
    let snapshot = snapshots[i]
    let device = snapshot.deviceId
    devices[device] = true
    let snapshotProviders = snapshot.providers || {}
    for (let providerId in snapshotProviders) {
      let stats = snapshotProviders[providerId] || {}
      let acc = providers[providerId]
      if (!acc) acc = providers[providerId] = createProviderAccumulator(String(providerId), dates)
      mergeProviderSnapshot(acc, stats, device)
    }
  }

  /** @type {{[key: string]: *}} */
  var outProviders = {}
  for (let id in providers) outProviders[id] = projectProvider(providers[id], dates)
  return {
    schemaVersion: 1,
    updatedAt: updatedAt,
    updatedAtMs: updatedAtMs,
    deviceCount: Object.keys(devices).length,
    devices: Object.keys(devices).sort(),
    providers: outProviders
  }
}

if (typeof module !== "undefined") module.exports = { aggregateSnapshots }
