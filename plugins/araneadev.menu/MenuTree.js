// Pure menu tree helpers: route resolution, ancestry, breadcrumbs and visibility.

/** @typedef {{id: string, label: string, kind?: string, parent?: string, target?: string, aliases?: Array<*>, provider?: string, when?: string}} MenuItem */
/** @typedef {{[key: string]: MenuItem}} ItemMap */
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
