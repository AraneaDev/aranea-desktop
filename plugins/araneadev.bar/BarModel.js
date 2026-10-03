// Pure layout and routing helpers for the araneadev.bar plugin, imported by
// Bar.qml as BarModel and required by the Node tests. No QML dependencies.

/**
 * A plain object with arbitrary keys (settings, layouts).
 * @typedef {{[key: string]: *}} Dict
 */

/**
 * A layout entry in object form: `id` plus inline widget settings.
 * @typedef {{[key: string]: *}} EntryObject
 */

/**
 * A bar slot item (a QML Item) as seen from here: visible, width, height.
 * @typedef {{[key: string]: *}} SlotItem
 */

/**
 * @typedef {object} BarLayout
 * @property {Array<(string|EntryObject)>} left - left region entries
 * @property {Array<(string|EntryObject)>} center - center region entries
 * @property {Array<(string|EntryObject)>} right - right region entries
 */

/**
 * @typedef {object} SettingsChange
 * @property {string} region - "left", "center" or "right"
 * @property {number} index - entry position within the region
 * @property {(string|EntryObject)} entry - the entry's new value
 */

/**
 * @typedef {object} PanelCandidate
 * @property {SlotItem} slot - the widget's slot item
 * @property {string} screenName - monitor the copy lives on
 * @property {boolean} opened - whether this copy's panel is open
 */

/**
 * @typedef {object} DropCandidate
 * @property {SlotItem} slot - the widget's slot item
 * @property {number} x - left edge along the bar
 * @property {number} y - top edge along the bar
 * @property {number} width - slot width
 * @property {number} height - slot height
 */

/**
 * Tell whether a value is a non-null, non-array object.
 * @param {*} value - value to test
 * @returns {boolean} true for a plain object
 */
function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

/**
 * Map a semantic state name (healthy, warning, error...) to a theme color key.
 * @param {?string} state - state name; unknown or empty falls back to muted
 * @returns {string} theme color key such as "accent" or "red"
 */
function semanticColor(state) {
  /** @type {{[key: string]: string}} */
  var colors = {
    healthy: "accent",
    focus: "accent_secondary",
    attention: "ceremony",
    warning: "yellow",
    error: "red",
    muted: "dark_foreground",
    charging: "accent",
    privacy: "accent_secondary"
  }
  return colors[String(state || "")] || colors.muted
}

/**
 * Whether the bar is drawn as glass: Aranea's default, so only an explicit
 * `transparent: false` in the bar config gives the opaque bar.
 * @param {*} config - the bar config object; anything else counts as {}
 * @returns {boolean} true unless config.transparent is exactly false
 */
function barTransparent(config) {
  return !(config && typeof config === "object" && config.transparent === false)
}

/**
 * Normalize a bar position to top, bottom, left or right (default top).
 * @param {?string} value - raw position from config
 * @returns {string} a valid position
 */
function normalizePosition(value) {
  var next = String(value || "").trim()
  return /^(top|bottom|left|right)$/.test(next) ? next : "top"
}

/**
 * Normalize a layout object to copied left, center and right entry arrays.
 * @param {*} value - raw layout from shell.json; anything that is not an object gives empty regions
 * @returns {BarLayout} layout with all three regions present
 */
function normalizeLayout(value) {
  var layout = isPlainObject(value) ? value : {}
  return {
    left: Array.isArray(layout.left) ? layout.left.slice() : [],
    center: Array.isArray(layout.center) ? layout.center.slice() : [],
    right: Array.isArray(layout.right) ? layout.right.slice() : []
  }
}

/**
 * Return a shallow copy of an entry object's settings, without its id.
 * @param {*} entry - layout entry (id string or object); a string or anything else has no settings
 * @returns {Dict} the entry's settings
 */
function entrySettings(entry) {
  if (!isPlainObject(entry)) return {}
  /** @type {Dict} */
  var copy = {}
  for (var key in entry) {
    if (key === "id") continue
    copy[key] = entry[key]
  }
  return copy
}

/**
 * Return a layout entry's module id, from a string entry or an object's id.
 * @param {*} entry - layout entry (id string or object); anything else is treated as empty
 * @returns {string} the id, or "" when there is none
 */
function entryId(entry) {
  if (typeof entry === "string") return entry
  if (isPlainObject(entry)) {
    var id = entry["id"]
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

/**
 * Move the tray entry (stock's omarchy.tray or its Aranea clone araneadev.tray)
 * to the inner edge of a region: first on the right, last elsewhere.
 * @param {Array<(string|EntryObject)>} entries - region entries; non-arrays count as empty
 * @param {string} section - region name ("left", "center" or "right")
 * @returns {Array<(string|EntryObject)>} a new array with the tray repositioned
 */
function pinTrayToInner(entries, section) {
  var trayEntry = null
  var result = []
  var values = Array.isArray(entries) ? entries : []
  for (var i = 0; i < values.length; i++) {
    var id = entryId(values[i])
    if (id === "omarchy.tray" || id === "araneadev.tray") trayEntry = values[i]
    else result.push(values[i])
  }
  if (trayEntry) {
    if (section === "right") result.unshift(trayEntry)
    else result.push(trayEntry)
  }
  return result
}

/**
 * Read one entry setting as a string, or the fallback when it is missing or null.
 * @param {*} entry - layout entry (id string or object); anything else is treated as empty
 * @param {string} key - setting name
 * @param {?string} fallback - value returned when the setting is absent
 * @returns {?string} the setting as a string, or the fallback
 */
function moduleString(entry, key, fallback) {
  var settings = entrySettings(entry)
  var value = settings[key]
  return value === undefined || value === null ? fallback : String(value)
}

/**
 * Find the position of the first entry with a given id.
 * @param {Array<(string|EntryObject)>} entries - region entries
 * @param {string} name - module id to look for
 * @returns {number} the index, or -1 when absent (or entries is not an array)
 */
function entryIndex(entries, name) {
  if (!Array.isArray(entries)) return -1
  for (var i = 0; i < entries.length; i++) {
    if (entryId(entries[i]) === name) return i
  }
  return -1
}

/**
 * Return the entries that come before the first entry with a given id.
 * @param {Array<(string|EntryObject)>} entries - region entries
 * @param {string} name - module id to split at
 * @returns {Array<(string|EntryObject)>} the preceding entries, or [] when the id is absent
 */
function entriesBefore(entries, name) {
  var index = entryIndex(entries, name)
  return index <= 0 ? [] : entries.slice(0, index)
}

/**
 * Return the entries that come after the first entry with a given id.
 * @param {Array<(string|EntryObject)>} entries - region entries
 * @param {string} name - module id to split at
 * @returns {Array<(string|EntryObject)>} the following entries, or [] when the id is absent
 */
function entriesAfter(entries, name) {
  var index = entryIndex(entries, name)
  return index === -1 ? [] : entries.slice(index + 1)
}

/**
 * Diff two normalized layouts for a settings-only change.
 *
 * A shell.json write that only changes inline widget settings (the battery
 * percentage toggle, a clock format change) must not rebuild the bar.
 * Compare two normalized layouts: when the structure is unchanged (same
 * entry ids in the same order per region), return the settings-only changes
 * as {region, index, entry}. Return null when the change is structural, or
 * touches an entry a live settings push cannot safely reach: custom modules
 * read their entry directly rather than an injected settings property, and
 * a duplicated id makes the push ambiguous.
 * @param {Dict} current - the layout the bar is built from
 * @param {Dict} next - the newly read layout
 * @returns {?Array<SettingsChange>} the changed entries, or null when a rebuild is needed
 */
function inlineSettingsDelta(current, next) {
  if (!isPlainObject(current) || !isPlainObject(next)) return null
  var regions = ["left", "center", "right"]
  /** @type {{[key: string]: number}} */
  var counts = {}
  for (var r = 0; r < regions.length; r++) {
    var entries = Array.isArray(next[regions[r]]) ? next[regions[r]] : []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      counts[id] = (counts[id] || 0) + 1
    }
  }
  var changes = []
  for (var s = 0; s < regions.length; s++) {
    var region = regions[s]
    var a = Array.isArray(current[region]) ? current[region] : []
    var b = Array.isArray(next[region]) ? next[region] : []
    if (a.length !== b.length) return null
    for (var j = 0; j < a.length; j++) {
      if (entryId(a[j]) !== entryId(b[j])) return null
      if (JSON.stringify(a[j]) === JSON.stringify(b[j])) continue
      if (customModuleType(a[j]) || customModuleType(b[j])) return null
      if (counts[entryId(b[j])] > 1) return null
      changes.push({ region: region, index: j, entry: b[j] })
    }
  }
  return changes
}

/**
 * Expand a leading "~/" or "$HOME/" in a path to the home directory.
 * @param {?string} value - path from config
 * @param {string} home - home directory, without a trailing slash
 * @returns {string} the expanded path, or "" for an empty value
 */
function expandPath(value, home) {
  var path = String(value || "")
  if (path === "") return ""
  if (path.indexOf("~/") === 0) return home + path.substring(1)
  if (path.indexOf("$HOME/") === 0) return home + path.substring(5)
  return path
}

/**
 * Tell whether a module name is safe to use as a file name (non-empty, not absolute, no "..").
 * @param {?string} name - custom module name
 * @returns {boolean} true when the name can be joined to the modules directory
 */
function customModuleSafeName(name) {
  var value = String(name || "")
  return value !== "" && value.indexOf("..") === -1 && value[0] !== "/"
}

/**
 * Work out a custom module's type: its explicit type, else "command" for exec, "qml" for source.
 * @param {*} entry - layout entry (id string or object); anything else is treated as empty
 * @returns {string} the type, or "" for a built-in module
 */
function customModuleType(entry) {
  var settings = entrySettings(entry)
  var type = String(settings.type || "")
  if (type) return type
  if (settings.exec) return "command"
  if (settings.source) return "qml"
  return ""
}

/**
 * Resolve a custom QML module's file: its expanded source, else <configDir>/bar/modules/<id>.qml.
 * @param {*} entry - layout entry (id string or object); anything else is treated as empty
 * @param {string} home - home directory, used to expand the source path
 * @param {?string} configDir - omarchy config directory
 * @returns {string} the file path, or "" when the id is unsafe and no source is set
 */
function customModulePath(entry, home, configDir) {
  var settings = entrySettings(entry)
  var name = entryId(entry)
  var source = settings.source ? expandPath(settings.source, home) : ""
  if (!source && customModuleSafeName(name))
    source = String(configDir || "") + "/bar/modules/" + String(name) + ".qml"
  return source
}

/**
 * Tell whether a slot is the copy actually drawn (visible, non-zero size).
 *
 * A center module is mounted twice once an anchor is set: the copy that is
 * actually drawn, and a zero-size placeholder holding its place in the flow
 * beside the anchor. Panel routing has to pick the drawn one (it is the only
 * one that can anchor a popup, carry the open-panel mark, or be found again
 * by switchPanelFrom) and fall back to the placeholder only when nothing is
 * on screen. The order the two are registered in is not stable across a live
 * bar reconfiguration, so picking the first match is not good enough.
 * @param {?SlotItem} slot - slot item (anything with visible, width and height)
 * @returns {boolean} true when the slot is visible with a non-zero size
 */
function isDrawnSlot(slot) {
  return !!slot && slot.visible === true && slot.width > 0 && slot.height > 0
}

/**
 * Pick the drawn slot from a list, else the first non-null one (the placeholder).
 * @param {?Array<SlotItem>} slots - candidate slot items
 * @returns {?SlotItem} the chosen slot, or null for an empty list
 */
function pickDrawnSlot(slots) {
  var placeholder = null
  var list = slots || []
  for (var i = 0; i < list.length; i++) {
    if (!list[i]) continue
    if (isDrawnSlot(list[i])) return list[i]
    if (!placeholder) placeholder = list[i]
  }
  return placeholder
}

/**
 * Choose which monitor's copy of a widget a panel hotkey acts on.
 *
 * A bar surface is built per monitor, so a panel hotkey has several live
 * copies of the same widget to route to, and the panel opens on whichever
 * monitor's copy answers. Candidates are `{ slot, screenName, opened }`.
 *
 * An open copy wins first: hide and toggle have to reach the panel the user
 * can actually see, wherever it was opened from. Otherwise the focused
 * monitor's copy wins, so a summon lands where the user is working instead of
 * on whichever output registered its slot first. Neither narrowing applies on
 * a single monitor, or when the focused output has no bar of its own.
 * @param {Array<PanelCandidate>} candidates - one row per live copy of the widget
 * @param {?string} focusedScreen - name of the focused monitor
 * @returns {?SlotItem} the slot to route the panel action to, or null
 */
function pickPanelSlot(candidates, focusedScreen) {
  var rows = Array.isArray(candidates) ? candidates : []
  var pool = rows.filter(function (row) {
    return row && row.opened === true
  })
  if (pool.length === 0)
    pool = rows.filter(function (row) {
      return !!row
    })

  var focused = String(focusedScreen || "")
  if (focused) {
    var onFocused = pool.filter(function (row) {
      return row.screenName === focused
    })
    if (onFocused.length > 0) pool = onFocused
  }

  return pickDrawnSlot(
    pool.map(function (row) {
      return row.slot
    })
  )
}

/**
 * Find the slot edge nearest a drag pointer along the bar's axis.
 *
 * Resolve a pointer anywhere along the bar to the closest insertion edge.
 * Requiring the pointer to sit inside another widget makes the empty space
 * around a centered group a dead zone, even though it visually reads as the
 * most natural place to drop.
 * @param {Array<DropCandidate>} candidates - slots with their geometry along the bar
 * @param {{x: number, y: number}} point - pointer position in the same coordinates
 * @param {boolean} vertical - true for a left or right bar (use the y axis)
 * @returns {?{slot: SlotItem, after: boolean}} the nearest slot and whether to drop after it, or null
 */
function nearestDropTarget(candidates, point, vertical) {
  var rows = Array.isArray(candidates) ? candidates : []
  var axis = vertical ? Number(point && point.y) : Number(point && point.x)
  if (!isFinite(axis)) return null

  var best = null
  var bestDistance = Infinity
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || !row.slot) continue

    var start = Number(vertical ? row.y : row.x)
    var size = Number(vertical ? row.height : row.width)
    if (!isFinite(start) || !isFinite(size) || size <= 0) continue

    var beforeDistance = Math.abs(axis - start)
    var afterDistance = Math.abs(axis - (start + size))
    var after = afterDistance < beforeDistance
    var distance = after ? afterDistance : beforeDistance
    if (distance < bestDistance) {
      best = { slot: row.slot, after: after }
      bestDistance = distance
    }
  }
  return best
}

if (typeof module !== "undefined") {
  module.exports = {
    isDrawnSlot: isDrawnSlot,
    pickDrawnSlot: pickDrawnSlot,
    pickPanelSlot: pickPanelSlot,
    nearestDropTarget: nearestDropTarget,
    barTransparent: barTransparent,
    normalizePosition: normalizePosition,
    entrySettings: entrySettings,
    entryId: entryId,
    pinTrayToInner: pinTrayToInner,
    moduleString: moduleString,
    entryIndex: entryIndex,
    entriesBefore: entriesBefore,
    entriesAfter: entriesAfter,
    inlineSettingsDelta: inlineSettingsDelta,
    expandPath: expandPath,
    customModuleSafeName: customModuleSafeName,
    customModuleType: customModuleType,
    customModulePath: customModulePath,
    semanticColor: semanticColor,
    normalizeLayout: normalizeLayout
  }
}
