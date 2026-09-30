// App history and the generated Apps rows: favourite and recent ids, the
// state file format, pruning, and the rows merged into the menu items.

/** @typedef {{id: string, label: string, kind?: string, parent?: string, appId?: string, [key: string]: *}} MenuItem */
/** @typedef {{[key: string]: MenuItem}} ItemMap */
/**
 * Trims and de-duplicates app ids, keeping at most `limit` of them in order.
 * @param {*} values - list of app ids (strings or finite numbers; anything else is skipped); a non-array yields []
 * @param {*} limit - maximum count; a negative or non-finite value means 12
 * @returns {Array<string>} the normalized ids
 */
function normalizeAppIds(values, limit) {
  var max = Number(limit)
  if (!isFinite(max) || max < 0) max = 12
  var rows = Array.isArray(values) ? values : []
  var out = []
  for (var i = 0; i < rows.length && out.length < Math.floor(max); i++) {
    var raw = rows[i]
    // Only strings and finite numbers are ids; objects would become "[object Object]".
    if (!(typeof raw === "string" || (typeof raw === "number" && isFinite(raw)))) continue
    var id = String(raw).trim()
    if (id && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

/**
 * Pins an app at the front of the favorites, or unpins it if already pinned;
 * a pin beyond the limit is refused (the list is left as it is).
 * @param {*} values - current favorite ids
 * @param {*} appId - app to toggle; empty leaves the list as is (normalized)
 * @param {*} limit - maximum number of favorites
 * @returns {{ids: Array<string>, refused: boolean}} the new favorite ids, and whether a pin was refused
 */
function toggleFavoriteApp(values, appId, limit) {
  var id = String(appId || "").trim()
  var current = normalizeAppIds(values, limit)
  if (!id) return { ids: current, refused: false }
  var index = current.indexOf(id)
  if (index >= 0) {
    current.splice(index, 1)
    return { ids: current, refused: false }
  }
  var max = Number(limit)
  if (isFinite(max) && max >= 0 && current.length >= Math.floor(max))
    return { ids: current, refused: true }
  return { ids: normalizeAppIds([id].concat(current), limit), refused: false }
}

/**
 * Reads the menu state file: {"favorites": [ids], "recent": [ids]}.
 * @param {*} text - the file contents; anything unparsable gives empty lists
 * @param {number} favoriteLimit - most favorite ids kept
 * @param {number} [recentLimit] - most recent ids kept (favoriteLimit when omitted)
 * @returns {{favorites: Array<string>, recent: Array<string>}} the normalized lists
 */
function parseAppHistory(text, favoriteLimit, recentLimit) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (e) {
    parsed = null
  }
  var value = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
  return {
    favorites: normalizeAppIds(
      Array.isArray(value.favorites) ? value.favorites : [],
      favoriteLimit
    ),
    recent: normalizeAppIds(
      Array.isArray(value.recent) ? value.recent : [],
      recentLimit === undefined ? favoriteLimit : recentLimit
    )
  }
}

/**
 * Writes the menu state file contents (pretty JSON with a trailing newline).
 * @param {*} favorites - pinned app ids
 * @param {*} recent - recently launched app ids
 * @param {number} favoriteLimit - most favorite ids kept
 * @param {number} [recentLimit] - most recent ids kept (favoriteLimit when omitted)
 * @returns {string} the file text
 */
function serializeAppHistory(favorites, recent, favoriteLimit, recentLimit) {
  return (
    JSON.stringify(
      {
        favorites: normalizeAppIds(favorites, favoriteLimit),
        recent: normalizeAppIds(recent, recentLimit === undefined ? favoriteLimit : recentLimit)
      },
      null,
      2
    ) + "\n"
  )
}

/**
 * Drops ids of apps that are not installed, so they do not use up slots.
 * @param {*} ids - app ids
 * @param {*} installed - ids of installed apps; not an array means unknown (nothing dropped)
 * @returns {Array<string>} the kept ids, in order
 */
function pruneAppIds(ids, installed) {
  var list = normalizeAppIds(ids, Array.isArray(ids) ? ids.length : 0)
  if (!Array.isArray(installed)) return list
  return list.filter(function (id) {
    return installed.indexOf(id) >= 0
  })
}

/**
 * Shows each app once among rows of kind "app": the real `apps.<appId>` row
 * when present (at its own position), else the first Favorites/Recent copy.
 * Other rows are kept; order is unchanged.
 * @param {Array<{[key: string]: *}>} rows - display rows
 * @returns {Array<{[key: string]: *}>} the rows without repeated apps
 */
function dedupeAppRows(rows) {
  var list = Array.isArray(rows) ? rows : []
  /** @type {{[key: string]: boolean}} */
  var hasReal = {}
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    if (r && r.kind === "app" && r.appId && r.itemId === "apps." + r.appId) hasReal[r.appId] = true
  }
  /** @type {{[key: string]: boolean}} */
  var seen = {}
  return list.filter(function (row) {
    if (!row || row.kind !== "app" || !row.appId) return true
    if (hasReal[row.appId]) return row.itemId === "apps." + row.appId
    if (seen[row.appId]) return false
    seen[row.appId] = true
    return true
  })
}

/**
 * Orders the Apps menu: menu rows (Favorites, Recent) first, then apps;
 * each group by label (case-insensitive), then by item id.
 * @param {Array<{[key: string]: *}>} rows - display rows of the Apps menu
 * @returns {Array<{[key: string]: *}>} a new, sorted array
 */
function sortAppsMenu(rows) {
  return (Array.isArray(rows) ? rows.slice() : []).sort(function (a, b) {
    var aApp = a.kind === "app" ? 1 : 0
    var bApp = b.kind === "app" ? 1 : 0
    if (aApp !== bApp) return aApp - bApp
    var aLabel = String(a.label || "").toLowerCase()
    var bLabel = String(b.label || "").toLowerCase()
    if (aLabel !== bLabel) return aLabel < bLabel ? -1 : 1
    var aId = String(a.itemId || "")
    var bId = String(b.itemId || "")
    return aId < bId ? -1 : aId > bId ? 1 : 0
  })
}

/**
 * Copies the app rows named by `ids`, in that order, re-parented under `parent`.
 * @param {Array<MenuItem>} appRows - all app rows (non-arrays are treated as empty)
 * @param {*} ids - app ids to pick; unknown ids are skipped
 * @param {string} parent - parent id for the copies ("root" when empty)
 * @param {string} prefix - id prefix for the copies (the parent when empty)
 * @returns {Array<{[key: string]: *}>} shallow copies of the rows with fresh id, parent and order
 */
function appRowsForIds(appRows, ids, parent, prefix) {
  var source = Array.isArray(appRows) ? appRows : []
  var wanted = normalizeAppIds(ids, source.length)
  /** @type {ItemMap} */
  var byId = {}
  for (var i = 0; i < source.length; i++) {
    var row = source[i]
    if (row && row.appId) byId[String(row.appId)] = row
  }

  var out = []
  var targetParent = String(parent || "root")
  var targetPrefix = String(prefix || targetParent)
  for (var j = 0; j < wanted.length; j++) {
    var sourceRow = byId[wanted[j]]
    if (!sourceRow) continue
    /** @type {{[key: string]: *}} */
    var copy = {}
    for (var key in sourceRow) copy[key] = sourceRow[key]
    copy.id = targetPrefix + "." + sourceRow.appId
    copy.parent = targetParent
    copy.order = out.length
    out.push(copy)
  }
  return out
}

// Swaps every app row for the current set. Rows keep the order they arrive in;
// ids already claimed (including duplicate desktop ids) are listed once.
/**
 * Replaces all app rows with a new set, returning fresh maps.
 * @param {ItemMap} items - current items by id (not modified)
 * @param {Array<string>} itemOrder - current item order
 * @param {Array<MenuItem>} appRows - the new app rows (not modified; copies get `order`)
 * @returns {{items: ItemMap, itemOrder: Array<string>}} the merged items and order
 */
function mergeAppRows(items, itemOrder, appRows) {
  var source = items || {}
  var order = Array.isArray(itemOrder) ? itemOrder : []
  var rows = Array.isArray(appRows) ? appRows : []
  /** @type {ItemMap} */
  var nextItems = {}
  var nextOrder = []

  for (var i = 0; i < order.length; i++) {
    var id = order[i]
    var existing = source[id]
    // Orphans (an id with no item) are dropped rather than carried forward,
    // so a single lost write cannot compound into a duplicate row.
    if (!existing || existing.kind === "app") continue
    nextItems[id] = existing
    nextOrder.push(id)
  }

  for (var j = 0; j < rows.length; j++) {
    var row = rows[j]
    if (!row || !row.id || nextItems[row.id]) continue
    /** @type {{[key: string]: *}} */
    var copy = {}
    for (var key in row) copy[key] = row[key]
    copy.order = nextOrder.length
    nextItems[row.id] = /** @type {MenuItem} */ (copy)
    nextOrder.push(row.id)
  }

  return { items: nextItems, itemOrder: nextOrder }
}

/**
 * Moves an app to the front of the recent list, trimming it to `limit`.
 * @param {*} values - current recent ids
 * @param {*} appId - app just launched; empty leaves the list as is (normalized)
 * @param {*} limit - maximum number of recent entries
 * @returns {Array<string>} the new recent ids
 */
function recordRecentApp(values, appId, limit) {
  var id = String(appId || "").trim()
  if (!id) return normalizeAppIds(values, limit)
  return normalizeAppIds([id].concat(Array.isArray(values) ? values : []), limit)
}

if (typeof module !== "undefined")
  module.exports = {
    normalizeAppIds: normalizeAppIds,
    toggleFavoriteApp: toggleFavoriteApp,
    parseAppHistory: parseAppHistory,
    serializeAppHistory: serializeAppHistory,
    pruneAppIds: pruneAppIds,
    dedupeAppRows: dedupeAppRows,
    sortAppsMenu: sortAppsMenu,
    appRowsForIds: appRowsForIds,
    mergeAppRows: mergeAppRows,
    recordRecentApp: recordRecentApp
  }
