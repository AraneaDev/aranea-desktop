// Menu sources: JSONC parsing, item normalization, merging the default and
// user files, and swapping provider rows into the items.

/** @typedef {{id: string, label: string, kind?: string, parent?: string, icon?: string, iconFont?: string, title?: string, target?: string, description?: string, action?: string, provider?: string, aliases?: Array<*>, when?: string, checked?: string, providerMenu?: string, [key: string]: *}} MenuItem */
/** @typedef {{[key: string]: MenuItem}} ItemMap */
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
 * @param {boolean} [settingsAvailable] - whether the settings plugin manifest is installed
 * @returns {{items: ItemMap, itemOrder: Array<string>}} items by id and their order
 */
function mergeMenuSources(defaultItems, userItems, settingsAvailable) {
  /** @type {{[key: string]: *}} */
  var nextItems = {}
  var nextOrder = []
  var settings = settingsAvailable
    ? [
        normalizeItem("aranea.settings", {
          parent: "setup",
          label: "Aranea settings",
          icon: "aranea-brand",
          description: "Wallpaper, motion, schedule, integrations and notifications",
          aliases: ["settings", "aranea-settings"],
          action: 'omarchy-shell shell summon araneadev.settings \'{"section":"appearance"}\'',
          when: 'test -f "$HOME/.config/omarchy/plugins/araneadev.settings/manifest.json"'
        })
      ]
    : []
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

  if (settings.length && !nextItems["aranea.settings"]) {
    nextItems["aranea.settings"] = settings[0]
    nextOrder.push("aranea.settings")
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
// Returns fresh items/itemOrder objects for the caller to assign in one go;
// never writes into the maps it is handed, since those live in QML `var`
// properties, and an in-place write into such an object is occasionally
// dropped by the engine (the key lands with an undefined value), which used
// to leave an orphaned id in itemOrder that the next swap kept and duplicated.
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
