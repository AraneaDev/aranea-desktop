// Pure helpers for the Aranea menu (Menu.qml): JSONC parsing, item merging,
// routing, visibility, search scoring and the batched guard script.
/* @aranea-facade-start: plugins/araneadev.menu/MenuPresentation.js */
// Presentation helpers for menu labels and stable route ids.

/**
 * Creates a stable route id from display text.
 * @param {*} value - Display text.
 * @returns {string} Stable route id.
 */
function slugify(value) {
  return (
    String(value || "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "item"
  )
}

if (typeof module !== "undefined") module.exports = { slugify: slugify }
/* @aranea-facade-end */

/**
 * One menu row: a JSONC entry, an app, or a provider-generated action.
 * @typedef {object} MenuItemFields
 * @property {string} id - dotted id such as `setup.power`
 * @property {string} parent - parent id ("" for root)
 * @property {string} kind - "menu", "link", "action" or "app"
 * @property {string} icon - glyph shown before the label
 * @property {string} [iconFont] - font for the glyph
 * @property {string} label - display label
 * @property {string} [title] - optional title text
 * @property {string} [target] - menu id a link opens
 * @property {string} [description] - secondary text, also searched
 * @property {string} [action] - shell command an action runs
 * @property {string} [provider] - provider key that fills this submenu
 * @property {Array<string>} [aliases] - extra route names and search words
 * @property {string} [when] - bash visibility guard
 * @property {string} [checked] - bash guard for the ✓ marker
 * @property {number} [order] - position in the merged item order
 * @property {string} [appId] - desktop id, for app rows
 * @property {string} [appIcon] - desktop icon, for app rows
 * @property {string} [providerMenu] - submenu whose provider made this row
 */

/**
 * A menu item: the known fields plus any extra keys carried over from JSONC.
 * @typedef {MenuItemFields & {[key: string]: *}} MenuItem
 */

/**
 * Menu items keyed by id.
 * @typedef {{[key: string]: MenuItem}} ItemMap
 */

/**
 * The key hint line for the menu's current state.
 * @param {{root: boolean, filter: boolean, dmenu: boolean, input: boolean, count: number, appRow: boolean}} state - root: root menu without a search; filter: a search is typed; dmenu/input: a dmenu request and its input mode; count: rows shown; appRow: the cursor row is an app
 * @returns {string} the hints
 */
function hintText(state) {
  /** @type {{[key: string]: *}} */
  var s = state || {}
  if (s.dmenu)
    return s.input
      ? "TYPE TO FILTER  ·  ESC CANCEL"
      : (Number(s.count) || 0) + " RESULTS  ·  ENTER SELECT  ·  ESC CANCEL"
  if (s.root) return "SYSTEM // READY"
  if (s.filter) return "ESC CLEAR  ·  ENTER OPEN"
  return "⌫ BACK  ·  ENTER OPEN" + (s.appRow ? "  ·  ^P PIN" : "") + "  ·  ESC CLOSE"
}

/**
 * Icon and text for an empty list: a search that found nothing says so;
 * otherwise loading, then a failed provider, then plain empty.
 * @param {{loading: boolean, error: boolean, filter: string}} state - the active menu's provider state and the search text
 * @returns {{icon: string, text: string}} what the empty state shows
 */
function emptyState(state) {
  /** @type {{[key: string]: *}} */
  var s = state || {}
  var filter = String(s.filter || "")
  if (filter) return { icon: "󰈉", text: "No matches for “" + filter + "”" }
  if (s.loading) return { icon: "󰑐", text: "Loading…" }
  if (s.error) return { icon: "󰀦", text: "Couldn’t load this list" }
  return { icon: "󰈉", text: "Nothing here yet" }
}

// Both merges below return fresh items/itemOrder objects for the caller to
// assign in one go. They must never write into the maps they are handed: those
// live in QML `var` properties, and an in-place write into such an object is
// occasionally dropped by the engine — the key lands with an undefined value.
// A lost write used to leave an id in itemOrder with no item behind it, and
// the next merge then kept that orphan and appended a second row for the same
// app, so the launcher listed it twice (and again on every later rescan).

/**
 * Returns an item's label with ` ✓` appended when its `checked:` held.
 * @param {MenuItem} entry - the item
 * @param {{[key: string]: boolean}} checkedResults - `checked:` results by id
 * @returns {string} the display label ("" for no item)
 */
function labelFor(entry, checkedResults) {
  if (!entry) return ""
  if (entry.checked && checkedResults && checkedResults[entry.id]) return entry.label + " ✓"
  return entry.label
}

/* @aranea-facade-start: plugins/araneadev.menu/MenuTree.js */
// Pure menu tree helpers: route resolution, ancestry, breadcrumbs and visibility.

/**
 * Looks up an item by id.
 * @param {ItemMap} items - items by id
 * @param {string} id - the id to find
 * @returns {?MenuItem} the item, or null
 */
function item(items, id) {
  return items && items[id] ? items[id] : null
}

/**
 * Resolves a route name to a menu item id.
 * @param {ItemMap} items - items by id
 * @param {Array<string>} itemOrder - item order
 * @param {*} input - the requested route
 * @returns {string} the matching route id
 */
function resolveRoute(items, itemOrder, input) {
  var raw = String(input || "")
    .toLowerCase()
    .replace(/_/g, "-")
  if (!raw || raw === "go" || raw === "menu") return "root"
  if (item(items, raw)) return raw
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(items, order[i])
    if (!entry || entry.kind === "app" || !entry.aliases) continue
    for (var j = 0; j < entry.aliases.length; j++) {
      var alias = String(entry.aliases[j] || "")
        .toLowerCase()
        .replace(/_/g, "-")
      if (alias === raw) return entry.id
    }
  }
  return raw
}

/**
 * Counts how many menus lie between an item and the root.
 * @param {ItemMap} items - items by id
 * @param {string} id - the item id
 * @returns {number} the depth
 */
function depthFor(items, id) {
  var depth = 0
  var current = item(items, id)
  var guard = 0
  while (current && current.parent && current.parent !== "root" && guard < 32) {
    depth += 1
    current = item(items, current.parent)
    guard += 1
  }
  return depth
}

/**
 * Joins labels from the root down to an item.
 * @param {ItemMap} items - items by id
 * @param {string} id - the item id
 * @returns {string} the breadcrumb path
 */
function pathFor(items, id) {
  var labels = []
  var current = item(items, id)
  var guard = 0
  while (current && current.id !== "root" && guard < 32) {
    labels.unshift(current.label)
    current = item(items, current.parent)
    guard += 1
  }
  return labels.join(" › ")
}

/**
 * Returns the breadcrumb path of an item's parent.
 * @param {ItemMap} items - items by id
 * @param {string} id - the item id
 * @returns {string} the parent path
 */
function parentPathFor(items, id) {
  var entry = item(items, id)
  if (!entry || !entry.parent || entry.parent === "root") return ""
  return pathFor(items, entry.parent)
}

/**
 * Tells whether an item sits below an ancestor.
 * @param {ItemMap} items - items by id
 * @param {string} id - the item id
 * @param {string} ancestorId - the candidate ancestor
 * @returns {boolean} true when it is a descendant
 */
function isDescendantOf(items, id, ancestorId) {
  if (ancestorId === "root") return id !== "root"
  var current = item(items, id)
  var guard = 0
  while (current && current.parent && guard < 32) {
    if (current.parent === ancestorId) return true
    current = item(items, current.parent)
    guard += 1
  }
  return false
}

/**
 * Counts an item's direct children.
 * @param {ItemMap} items - items by id
 * @param {Array<string>} itemOrder - item order
 * @param {string} id - the parent id
 * @returns {number} the child count
 */
function childCount(items, itemOrder, id) {
  var count = 0
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(items, order[i])
    if (entry && entry.parent === id) count += 1
  }
  return count
}

/**
 * Tells whether an item should be listed.
 * @param {ItemMap} items - items by id
 * @param {Array<string>} itemOrder - item order
 * @param {{[key: string]: boolean}} whenResults - guard results
 * @param {MenuItem} entry - the item to test
 * @param {number} [depth] - recursion depth
 * @returns {boolean} true when visible
 */
function isVisible(items, itemOrder, whenResults, entry, depth) {
  if (!entry) return false
  if (entry.when && whenResults && whenResults[entry.id] === false) return false
  if (entry.kind !== "menu" && entry.kind !== "link") return true
  if (entry.provider) return true

  var guard = depth || 0
  if (guard >= 32) return false
  var target = entry.kind === "link" ? entry.target : entry.id
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var child = item(items, order[i])
    if (
      child &&
      child.parent === target &&
      isVisible(items, itemOrder, whenResults, child, guard + 1)
    )
      return true
  }
  return false
}

if (typeof module !== "undefined") {
  module.exports = {
    item: item,
    resolveRoute: resolveRoute,
    depthFor: depthFor,
    pathFor: pathFor,
    parentPathFor: parentPathFor,
    isDescendantOf: isDescendantOf,
    childCount: childCount,
    isVisible: isVisible
  }
}
/* @aranea-facade-end */

/**
 * Builds the list-model row the menu renders for an item.
 * @param {ItemMap} items - items by id
 * @param {Array<string>} itemOrder - item order
 * @param {{[key: string]: boolean}} checkedResults - `checked:` results by id
 * @param {MenuItem} entry - the item
 * @param {*} detail - secondary text (replaced by a tagline for top-level sections)
 * @param {number} [score] - sort score (default 0)
 * @param {string} [section] - list section such as "drilldown" (default "")
 * @returns {object} the display row
 */
function displayRow(items, itemOrder, checkedResults, entry, detail, score, section) {
  var target = entry.kind === "link" ? entry.target : entry.id
  return {
    itemId: entry.id,
    kind: entry.kind,
    icon: entry.icon,
    iconFont: entry.iconFont || "",
    appIcon: entry.appIcon || "",
    appId: entry.appId || "",
    label: labelFor(entry, checkedResults),
    target: target,
    detail: semanticDetail(entry, detail),
    path: pathFor(items, entry.id),
    childCount:
      entry.kind === "menu" || entry.kind === "link" ? childCount(items, itemOrder, target) : 0,
    action: entry.action || "",
    provider: entry.provider || "",
    score: score || 0,
    section: section || ""
  }
}

/* @aranea-facade-start: plugins/araneadev.menu/MenuSearch.js */
// Pure search helpers for MenuModel.js: tokenization, matching and ranking.

/**
 * Replaces route separators with spaces so ids split into words.
 * @param {*} value - the token to normalize
 * @returns {string} the spaced token
 */
function searchableToken(value) {
  return String(value || "").replace(/[._-]+/g, " ")
}

/**
 * Returns the final segment of a dotted route id.
 * @param {*} id - the item id
 * @returns {string} the leaf segment
 */
function leafIdFor(id) {
  var parts = String(id || "").split(".")
  return parts.length > 0 ? parts[parts.length - 1] : id
}

/**
 * Builds the lower-cased text matched for an item's name.
 * @param {MenuItem} entry - the item
 * @returns {string} the searchable text
 */
function nameSearchText(entry) {
  if (!entry) return ""
  var aliases = []
  var values = Array.isArray(entry.aliases) ? entry.aliases : []
  for (var i = 0; i < values.length; i++) aliases.push(searchableToken(values[i]))
  return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")]
    .join(" ")
    .toLowerCase()
}

/**
 * Tells whether a term equals a whitespace-separated word.
 * @param {string} term - a lower-cased search term
 * @param {*} text - the text to split
 * @returns {boolean} true on a whole-word match
 */
function termInSearchWords(term, text) {
  var words = String(text || "")
    .toLowerCase()
    .split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i] === term) return true
  }
  return false
}

/**
 * Tells whether every query term is a whole word in the supplied text.
 * @param {*} query - the search query
 * @param {*} text - the description text
 * @returns {boolean} true when all terms match
 */
function descriptionTextMatches(query, text) {
  var terms = String(query || "")
    .toLowerCase()
    .trim()
    .split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termInSearchWords(terms[i], text)) return false
  }
  return true
}

/**
 * Tells whether a visible item matches every query term.
 * @param {MenuItem} entry - the item
 * @param {*} query - the search query
 * @param {boolean} visible - whether the item is visible
 * @returns {boolean} true when it matches
 */
function matchesQuery(entry, query, visible) {
  if (!entry || entry.id === "root") return false
  if (!visible) return false

  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var terms = String(query || "")
    .toLowerCase()
    .trim()
    .split(/\s+/)

  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    if (nameText.indexOf(terms[i]) >= 0) continue
    if (termInSearchWords(terms[i], descriptionText)) continue
    return false
  }

  return true
}

/**
 * Finds an item's depth without depending on MenuModel's other helpers.
 * @param {ItemMap} items - items by id
 * @param {string} id - the item id
 * @returns {number} the depth
 */
function searchDepthFor(items, id) {
  var depth = 0
  var current = items && items[id]
  /** @type {{[key: string]: boolean}} */
  var seen = {}
  while (current && current.parent && current.parent !== "root" && !seen[current.id]) {
    seen[current.id] = true
    depth++
    current = items[current.parent]
  }
  return depth
}

/**
 * Scores a search hit by match tier, depth and declared order.
 * @param {ItemMap} items - items by id
 * @param {MenuItem} entry - the item
 * @param {*} query - the search query
 * @returns {number} the sortable score
 */
function searchScore(items, entry, query) {
  var needle = String(query || "")
    .toLowerCase()
    .trim()
  var label = entry.label.toLowerCase()
  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var score = 80

  if (label === needle) score = entry.parent === "root" ? 2 : 0
  else if (entry.kind === "app" && label.split(/\s+/).indexOf(needle) >= 0) score = 0
  else if (label.indexOf(needle) === 0) score = 10
  else if (label.indexOf(needle) >= 0) score = 30
  else if (nameText.indexOf(needle) >= 0) score = 40
  else if (descriptionTextMatches(needle, descriptionText)) score = 60

  if (entry.kind === "menu" || entry.kind === "link") score -= 2
  if (entry.kind === "app") score -= 5

  return score * 1000 + searchDepthFor(items, entry.id) * 25 + entry.order
}

if (typeof module !== "undefined") {
  module.exports = {
    searchableToken: searchableToken,
    leafIdFor: leafIdFor,
    nameSearchText: nameSearchText,
    termInSearchWords: termInSearchWords,
    descriptionTextMatches: descriptionTextMatches,
    matchesQuery: matchesQuery,
    searchScore: searchScore
  }
}
/* @aranea-facade-end */

/* @aranea-facade-start: plugins/araneadev.menu/MenuAppRows.js */
// App history and the generated Apps rows: favourite and recent ids, the
// state file format, pruning, and the rows merged into the menu items.

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
/* @aranea-facade-end */

/* @aranea-facade-start: plugins/araneadev.menu/MenuItemParsing.js */
// Menu sources: JSONC parsing, item normalization, merging the default and
// user files, and swapping provider rows into the items.

/**
 * Strips whole-line `//` comments and trailing commas so JSONC parses as JSON.
 * @param {*} raw - JSONC text; null or undefined is treated as empty
 * @returns {string} the JSON text
 */
function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

/**
 * Coerces an `aliases` value to a list of non-empty strings.
 * @param {*} value - an array, a single string, or anything else (yields [])
 * @returns {Array<string>} the aliases
 */
function normalizeAliases(value) {
  if (Array.isArray(value))
    return value
      .map(function (v) {
        return String(v || "")
      })
      .filter(function (v) {
        return v
      })
  if (typeof value === "string" && value) return [value]
  return []
}

/**
 * Stringifies a value, falling back when it is null or undefined.
 * @param {*} value - the value to stringify
 * @param {*} fallback - returned as is when value is null or undefined
 * @returns {*} String(value), or the fallback unchanged
 */
function textValue(value, fallback) {
  if (value === undefined || value === null) return fallback
  return String(value)
}

/**
 * Returns the fixed tagline for a top-level section, keyed by the entry's id
 * (or its lowercased label when it has none), else `detail`.
 * @param {*} entry - the menu item
 * @param {*} detail - fallback detail text
 * @returns {string} the tagline, or the detail ("" when null or undefined)
 */
function semanticDetail(entry, detail) {
  var value = entry && typeof entry === "object" ? entry : {}
  if (String(value.parent || "") !== "root") return textValue(detail, "")

  /** @type {{[key: string]: string}} */
  var taglines = {
    apps: "FIND // LAUNCH // MANAGE",
    learn: "DOCUMENTATION // GUIDES // IDEAS",
    trigger: "AUTOMATE // SCRIPTS // WORKFLOWS",
    style: "APPEARANCE // THEMES // BEHAVIOR",
    setup: "SYSTEM // DEVICES // PREFERENCES",
    system: "SLEEP // RESTART // SHUTDOWN"
  }
  var key = textValue(value.id, textValue(value.label, "").toLowerCase())
  return taglines[key] || textValue(detail, "")
}

/**
 * Builds a full menu item from one JSONC entry, deriving parent and kind.
 * @param {*} id - the entry's key (dotted path such as `setup.power`)
 * @param {*} raw - the entry object; anything else is treated as {}
 * @returns {MenuItem} the normalized item
 */
function normalizeItem(id, raw) {
  var value = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
  var itemId = textValue(id, "")
  var aliases = normalizeAliases(value.aliases)
  var parent = textValue(value.parent, "")
  if (!parent) parent = itemId.indexOf(".") >= 0 ? itemId.split(".").slice(0, -1).join(".") : "root"
  if (itemId === "root") parent = ""

  var kind = value.action ? "action" : value.target ? "link" : "menu"

  return {
    id: itemId,
    parent: parent,
    kind: kind,
    icon: textValue(value.icon, ""),
    iconFont: textValue(value.iconFont, ""),
    label: textValue(value.label, itemId),
    title: textValue(value.title, ""),
    target: textValue(value.target, ""),
    description: textValue(value.description, ""),
    action: textValue(value.action, ""),
    provider: textValue(value.provider, ""),
    aliases: aliases,
    when: textValue(value.when, ""),
    checked: textValue(value.checked, "")
  }
}

/**
 * Parses a JSONC menu file (top-level map or an `items` map) into normalized items.
 * @param {*} raw - JSONC text
 * @returns {Array<MenuItem>} the items, or [] when the text is empty or invalid
 */
function parseMenuJsonc(raw) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return []

  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    return []
  }
  if (typeof parsed !== "object" || parsed === null) return []

  var source =
    parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items)
      ? parsed.items
      : parsed
  var out = []
  for (var id in source) {
    var entry = source[id]
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
    out.push(normalizeItem(id, entry))
  }
  return out
}

/**
 * Merges user items over default items key by key, adding a root item if missing.
 * @param {Array<MenuItem>} defaultItems - items from the shipped menu
 * @param {Array<MenuItem>} userItems - items from the user extension file
 * @returns {{items: ItemMap, itemOrder: Array<string>}} items by id and their order
 */
function mergeMenuSources(defaultItems, userItems) {
  /** @type {{[key: string]: *}} */
  var nextItems = {}
  var nextOrder = []
  var sources = [defaultItems || [], userItems || []]

  for (var s = 0; s < sources.length; s++) {
    var src = sources[s]
    for (var i = 0; i < src.length; i++) {
      var entry = src[i]
      if (!entry || !entry.id) continue
      if (!nextItems[entry.id]) nextOrder.push(entry.id)
      /** @type {{[key: string]: *}} */
      var prior = nextItems[entry.id] || {}
      /** @type {{[key: string]: *}} */
      var merged = {}
      for (var k in prior) merged[k] = prior[k]
      for (var k2 in entry) merged[k2] = entry[k2]
      merged.id = entry.id
      nextItems[entry.id] = merged
    }
  }

  if (!nextItems.root) {
    nextItems.root = {
      id: "root",
      parent: "",
      kind: "menu",
      icon: "",
      iconFont: "",
      label: "Go",
      title: "",
      target: "",
      description: "",
      aliases: [],
      when: "",
      checked: "",
      action: "",
      provider: ""
    }
    nextOrder.unshift("root")
  }
  for (var k3 = 0; k3 < nextOrder.length; k3++) nextItems[nextOrder[k3]].order = k3

  return {
    items: nextItems,
    itemOrder: nextOrder
  }
}

// Swaps the rows one provider contributed, leaving every other item untouched.
// Rows carry the id of the submenu that produced them, so a provider that runs
// again drops its previous batch (a plugin that was just enabled disappears
// from the Enable list), without disturbing static children declared in JSONC.
/**
 * Replaces the rows one provider produced for a submenu, returning fresh maps.
 * @param {ItemMap} items - current items by id (not modified)
 * @param {Array<string>} itemOrder - current item order
 * @param {string} menuId - id of the submenu whose provider produced the rows
 * @param {Array<MenuItem>} rows - the new rows (not modified; copies get `providerMenu` and `order`)
 * @returns {{items: ItemMap, itemOrder: Array<string>}} the merged items and order
 */
function swapProviderRows(items, itemOrder, menuId, rows) {
  var source = items || {}
  var order = Array.isArray(itemOrder) ? itemOrder : []
  var incoming = Array.isArray(rows) ? rows : []
  /** @type {ItemMap} */
  var nextItems = {}
  var nextOrder = []

  for (var i = 0; i < order.length; i++) {
    var id = order[i]
    var existing = source[id]
    if (!existing || existing.providerMenu === menuId) continue
    nextItems[id] = existing
    nextOrder.push(id)
  }

  for (var j = 0; j < incoming.length; j++) {
    var row = incoming[j]
    if (!row || !row.id || nextItems[row.id]) continue
    /** @type {{[key: string]: *}} */
    var copy = {}
    for (var key in row) copy[key] = row[key]
    copy.providerMenu = menuId
    copy.order = nextOrder.length
    nextItems[row.id] = /** @type {MenuItem} */ (copy)
    nextOrder.push(row.id)
  }

  return { items: nextItems, itemOrder: nextOrder }
}

if (typeof module !== "undefined")
  module.exports = {
    stripJsonc: stripJsonc,
    normalizeAliases: normalizeAliases,
    textValue: textValue,
    semanticDetail: semanticDetail,
    normalizeItem: normalizeItem,
    parseMenuJsonc: parseMenuJsonc,
    mergeMenuSources: mergeMenuSources,
    swapProviderRows: swapProviderRows
  }
/* @aranea-facade-end */

/* @aranea-facade-start: plugins/araneadev.menu/MenuGuardScript.js */
// The batch bash script that answers every `when:` and `checked:` guard.

// Commands a `checked:` expression reads a value out of. Every sibling row
// asks the same one -- Defaults > Browser has seven rows all comparing
// against `omarchy-default-browser` -- so the batch runs it once and the rows
// read the captured answer.
//
// The capture has to be eager. These are read inside `$(...)`, and a value
// cached while one expression runs lives in that subshell only, so a lazy
// memo never survives to the expression after it.
var GUARD_READERS = [
  "omarchy-channel-current",
  "omarchy-default-agent",
  "omarchy-default-browser",
  "omarchy-default-editor",
  "omarchy-default-terminal",
  "omarchy-dns"
]

// Package and command presence account for most of what the guards ask, and
// asked one at a time they are almost all fork: the shipped menu spends over
// a second on them. Answer them inside the guard process instead. These
// shadow the real commands for the batch only, so they have to agree with
// them everywhere, including for no arguments at all (present is true of
// nothing, missing is not).
//
// `pacman -Q` resolves a name through what installed packages provide, not
// just what they are called -- with gvim installed it reports `vim` as
// present -- so the set has to carry provides too, or `install.editor.vim`
// comes back and offers to install what is already there. A version
// constraint (`bash>=1`) is not a name any set can answer, so it goes to
// pacman itself; no shipped guard writes one.
//
// `pacman -Qi` wraps a long list across continuation lines whenever COLUMNS
// is set in the environment, which a login shell may well have done, so the
// parser follows the indented lines rather than reading the first one and
// dropping half of what is installed.
/**
 * Returns the bash helpers that answer package and command checks in-process.
 * @returns {string} bash defining the package set and the omarchy-pkg-/cmd-present/missing shadows
 */
function guardHelpers() {
  return (
    "declare -A __omarchy_pkgs=()\n" +
    "mapfile -t __omarchy_pkg_names < <({ pacman -Qq; LC_ALL=C pacman -Qi" +
    ' | awk \'/^[A-Za-z]/ { provides = ($0 ~ /^Provides/); sub(/^[^:]*: /, "") }' +
    ' provides && $0 != "None" { n = split($0, p, " ");' +
    ' for (i = 1; i <= n; i++) { sub(/[<>=].*/, "", p[i]); print p[i] } }\'; } 2>/dev/null)\n' +
    'for __omarchy_pkg in "${__omarchy_pkg_names[@]}"; do __omarchy_pkgs[$__omarchy_pkg]=1; done\n' +
    "__omarchy_pkg_has() { [[ -n ${__omarchy_pkgs[$1]-} ]] && return 0; " +
    '[[ $1 == *[\\<\\>=]* ]] && { pacman -Q "$1" &>/dev/null; return; }; return 1; }\n' +
    'omarchy-pkg-present() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 1; done; return 0; }\n' +
    'omarchy-pkg-missing() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 0; done; return 1; }\n' +
    'omarchy-cmd-present() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 1; done; return 0; }\n' +
    'omarchy-cmd-missing() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 0; done; return 1; }\n'
  )
}

// Substitute the captured answer into the expression rather than shadowing
// the reader with a function. `$(reader)` and the variable holding what it
// printed are interchangeable -- both strip trailing newlines, both split the
// same way unquoted -- while a function would also catch `command -v reader`,
// `VAR=x reader`, and every other form, and answer those wrong. Anything but
// the plain substitution is left alone to run the real command.
/**
 * Returns the helpers plus eager captures of the readers the guards use.
 * @param {string} guards - the guard lines, already substituted
 * @returns {string} the helpers plus a capture line for each reader the guards use
 */
function guardPrelude(guards) {
  var prelude = guardHelpers()

  for (var i = 0; i < GUARD_READERS.length; i++) {
    // The guards arrive already substituted, so what marks a reader as wanted
    // is the slot standing in for it, not the call it replaced.
    if (guards.indexOf(guardReaderSlot(i)) < 0) continue
    // `|| :` so a reader that exits nonzero cannot take the batch down with
    // it under a login shell that turned on errexit.
    prelude += "__omarchy_read_" + i + "=$(" + GUARD_READERS[i] + " 2>/dev/null) || :\n"
  }

  return prelude
}

/**
 * Returns the bash variable that holds a reader's captured output.
 * @param {number} index - index into GUARD_READERS
 * @returns {string} the `${__omarchy_read_N}` expansion
 */
function guardReaderSlot(index) {
  return "${__omarchy_read_" + index + "}"
}

/**
 * Replaces each plain `$(reader)` in an expression with that reader's captured variable.
 * @param {string} expression - a `when:` or `checked:` bash expression
 * @returns {string} the substituted expression
 */
function substituteGuardReaders(expression) {
  for (var i = 0; i < GUARD_READERS.length; i++)
    expression = expression.split("$(" + GUARD_READERS[i] + ")").join(guardReaderSlot(i))

  return expression
}

/**
 * Wraps one guard expression in a bash `if` that prints `<id>:<tag>:<0|1>`.
 * @param {string} id - the item id
 * @param {string} tag - "w" for `when:`, "c" for `checked:`
 * @param {string} expression - the bash expression
 * @returns {string} one line of bash
 */
function guardLine(id, tag, expression) {
  return (
    "if { " +
    substituteGuardReaders(expression) +
    "; } >/dev/null 2>&1; then echo " +
    id +
    ":" +
    tag +
    ":1; else echo " +
    id +
    ":" +
    tag +
    ":0; fi\n"
  )
}

// One bash script for every `when:` and `checked:` in the menu, reporting
// `<id>:<w|c>:<0|1>` per line. Speed is the whole point: the menu opens on
// the last evaluation's answers, so however long this takes is how long a row
// can contradict the state it describes.
/**
 * Builds the batch bash script that evaluates every `when:` and `checked:` guard.
 * @param {ItemMap} items - items by id
 * @returns {string} the script, or "" when no item has a guard
 */
function guardScript(items) {
  var guards = ""
  var ids = Object.keys(items || {})

  for (var i = 0; i < ids.length; i++) {
    var entry = items[ids[i]]
    if (!entry) continue
    if (entry.when) guards += guardLine(ids[i], "w", entry.when)
    if (entry.checked) guards += guardLine(ids[i], "c", entry.checked)
  }

  return guards ? guardPrelude(guards) + guards : ""
}

if (typeof module !== "undefined")
  module.exports = {
    guardReaders: GUARD_READERS,
    guardHelpers: guardHelpers,
    guardPrelude: guardPrelude,
    guardReaderSlot: guardReaderSlot,
    substituteGuardReaders: substituteGuardReaders,
    guardLine: guardLine,
    guardScript: guardScript
  }
/* @aranea-facade-end */

if (typeof module !== "undefined") {
  module.exports = {
    guardReaders: GUARD_READERS,
    guardScript: guardScript,
    stripJsonc: stripJsonc,
    normalizeAliases: normalizeAliases,
    normalizeAppIds: normalizeAppIds,
    toggleFavoriteApp: toggleFavoriteApp,
    parseAppHistory: parseAppHistory,
    serializeAppHistory: serializeAppHistory,
    pruneAppIds: pruneAppIds,
    dedupeAppRows: dedupeAppRows,
    sortAppsMenu: sortAppsMenu,
    hintText: hintText,
    emptyState: emptyState,
    recordRecentApp: recordRecentApp,
    appRowsForIds: appRowsForIds,
    semanticDetail: semanticDetail,
    normalizeItem: normalizeItem,
    parseMenuJsonc: parseMenuJsonc,
    mergeMenuSources: mergeMenuSources,
    mergeAppRows: mergeAppRows,
    swapProviderRows: swapProviderRows,
    item: item,
    resolveRoute: resolveRoute,
    slugify: slugify,
    depthFor: depthFor,
    pathFor: pathFor,
    parentPathFor: parentPathFor,
    isDescendantOf: isDescendantOf,
    childCount: childCount,
    isVisible: isVisible,
    labelFor: labelFor,
    searchableToken: searchableToken,
    leafIdFor: leafIdFor,
    nameSearchText: nameSearchText,
    termInSearchWords: termInSearchWords,
    descriptionTextMatches: descriptionTextMatches,
    matchesQuery: matchesQuery,
    searchScore: searchScore,
    displayRow: displayRow
  }
}
