// Pure adapters from existing menu/app rows and compositor identities to search
// records and typed dispatch data. Display strings never become instructions.

/** @typedef {{[key: string]: any}} SearchSnapshot */
/** @typedef {{[key: string]: any}} SourceRecord */

/**
 * Copies array and ObjectModel/list-wrapper values without retaining live lists.
 * @param {*} collection - raw collection
 * @returns {Array<any>} snapshot values
 */
function collectionValues(collection) {
  if (Array.isArray(collection)) return collection.slice()
  if (collection && collection.values !== undefined) return collectionValues(collection.values)
  var out = []
  if (collection && typeof collection.length === "number")
    for (var i = 0; i < collection.length; i++) out.push(collection[i])
  return out
}

/**
 * Accepts only nonzero exact hexadecimal compositor addresses.
 * @param {*} value - raw address
 * @returns {string} valid address, or empty text
 */
function windowAddress(value) {
  return typeof value === "string" && /^0x[0-9a-fA-F]+$/.test(value) && !/^0x0+$/.test(value)
    ? value
    : ""
}

/**
 * Selects a workspace by its raw canonical identity, never its display label.
 * Positive IDs are absolute; negative named IDs use explicit name selectors,
 * avoiding relative-ID interpretation. Special names retain their prefix.
 * @param {*} row - compositor workspace
 * @returns {string} selector, or empty text for unusable identity
 */
function workspaceSelector(row) {
  if (!row || typeof row.id !== "number" || !isFinite(row.id) || Math.floor(row.id) !== row.id)
    return ""
  if (row.id > 0) return String(row.id)
  if (row.id === 0 || row.id === -1) return ""
  var name = typeof row.name === "string" ? row.name : ""
  if (!name) return ""
  for (var i = 0; i < name.length; i++)
    if (name.charCodeAt(i) < 32 || name.charCodeAt(i) === 127) return ""
  return name === "special" || name.indexOf("special:") === 0 ? name : "name:" + name
}

/**
 * Encodes a Lua short string; JSON Unicode escapes are not Lua escapes.
 * @param {string} value - validated identity string
 * @returns {string} quoted Lua literal
 */
function luaString(value) {
  return '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
}

/**
 * Creates the complete common record shape before ranking normalization.
 * @param {string} type - result type
 * @param {string|number} identity - canonical identity
 * @param {string} label - display text
 * @param {*} target - typed activation data
 * @param {string} detail - description
 * @param {*} aliases - searchable aliases
 * @returns {SourceRecord} raw normalized source record
 */
function sourceRecord(type, identity, label, target, detail, aliases) {
  return {
    key: type + ":" + identity,
    type: type,
    label: label,
    detail: detail || "",
    aliases: collectionValues(aliases),
    target: target,
    available: true,
    pinned: false,
    recentRank: null,
    activeWorkspace: false
  }
}

/**
 * Builds static setting destinations. Availability comes from the existing
 * menu manifest watcher, not a second installation or settings state store.
 * @param {boolean} available - plugin manifest availability
 * @returns {Array<SourceRecord>} static destination records
 */
function settingRecords(available) {
  if (!available) return []
  return [
    sourceRecord(
      "setting",
      "appearance",
      "Appearance",
      { section: "appearance" },
      "Wallpaper and motion",
      ["wallpaper", "motion"]
    ),
    sourceRecord(
      "setting",
      "display",
      "Display",
      { section: "display" },
      "Focused display scaling",
      ["display", "scale", "scaling", "custom scale"]
    ),
    sourceRecord(
      "setting",
      "schedule",
      "Wallpaper schedule",
      { section: "schedule" },
      "Scheduled wallpaper times",
      ["schedule", "dawn", "day", "dusk", "night"]
    ),
    sourceRecord(
      "setting",
      "integrations",
      "Integrations",
      { section: "integrations" },
      "Application and desktop integrations",
      ["integration", "themes"]
    ),
    sourceRecord(
      "setting",
      "notifications",
      "Notifications",
      { section: "notifications" },
      "Do not disturb and quiet hours",
      ["dnd", "quiet hours", "notification"]
    )
  ]
}

/**
 * Converts a fresh snapshot using the existing generated app rows, merged menu
 * items and guard results. Unknown/headings and unavailable rows are omitted.
 * @param {SearchSnapshot} snapshot - current raw source snapshot
 * @returns {Array<SourceRecord>} selectable records, deduplicated by identity
 */
function sourceRecords(snapshot) {
  var data = snapshot || {}
  /** @type {Array<SourceRecord>} */
  var rows = []
  /** @type {{[key: string]: boolean}} */
  var seen = {}
  var favorites = collectionValues(data.favoriteAppIds)
  var recent = collectionValues(data.recentAppIds)
  collectionValues(data.appRows).forEach(function (app) {
    if (
      !app ||
      app.kind !== "app" ||
      typeof app.appId !== "string" ||
      !app.appId.trim() ||
      !app.label ||
      app.available === false
    )
      return
    var id = app.appId.trim()
    if (seen["app:" + id]) return
    seen["app:" + id] = true
    var row = sourceRecord(
      "app",
      id,
      app.label,
      { appId: id },
      app.description || "Launch application",
      app.aliases
    )
    row.pinned = favorites.indexOf(id) >= 0
    var index = recent.indexOf(id)
    row.recentRank = index >= 0 ? index : null
    rows.push(row)
  })
  var items = data.menuItems || {}
  var menu = Array.isArray(items)
    ? items
    : Object.keys(items).map(function (key) {
        return items[key]
      })
  menu.forEach(function (item) {
    if (
      !item ||
      ["action", "menu", "link"].indexOf(item.kind) < 0 ||
      !item.id ||
      item.id === "root" ||
      !item.label ||
      item.available === false ||
      (item.when && data.whenResults && data.whenResults[item.id] === false)
    )
      return
    if (seen["command:" + item.id]) return
    seen["command:" + item.id] = true
    rows.push(
      sourceRecord(
        "command",
        item.id,
        item.label,
        { itemId: item.id },
        item.description || "Open " + item.label,
        item.aliases
      )
    )
  })
  rows = rows.concat(settingRecords(data.settingsAvailable === true))
  if (data.compositorAvailable !== true) return rows
  collectionValues(data.windows).forEach(function (window) {
    if (!window) return
    var address = windowAddress(window.address)
    if (!address || window.available === false || seen["window:" + address]) return
    seen["window:" + address] = true
    var ipc = window.lastIpcObject || {}
    var app = window.appId || window.class || ipc.class || ""
    var id = window.workspace ? window.workspace.id : ipc.workspace ? ipc.workspace.id : null
    var detail = id !== null && id !== undefined ? "Switch to workspace " + id : "Switch to window"
    var row = sourceRecord(
      "window",
      address,
      window.title || app || "Window " + address,
      { address: address },
      detail,
      app ? [app] : []
    )
    row.activeWorkspace = id !== null && id !== undefined && id === data.focusedWorkspaceId
    rows.push(row)
  })
  collectionValues(data.workspaces).forEach(function (workspace) {
    var selector = workspaceSelector(workspace)
    if (!selector || workspace.available === false || seen["workspace:" + workspace.id]) return
    seen["workspace:" + workspace.id] = true
    var windows = collectionValues(workspace.toplevels || workspace.windows)
    var count =
      windows.length || (typeof workspace.windows === "number" ? Math.max(0, workspace.windows) : 0)
    var label = workspace.name || String(workspace.id)
    if (label === String(workspace.id)) label = "Workspace " + label
    rows.push(
      sourceRecord(
        "workspace",
        workspace.id,
        label,
        { workspaceId: workspace.id, selector: selector },
        "Workspace " + workspace.id + " · " + count + (count === 1 ? " window" : " windows"),
        []
      )
    )
  })
  return rows
}

/**
 * Resolves again from raw data, so cached/ranked records and selectors cannot
 * dispatch vanished identities or stale metadata. Returns host handler requests
 * for existing actions, and argv for the installed Lua/IPC boundaries.
 * @param {*} record - current record resolved by the ranking facade
 * @param {SearchSnapshot} snapshot - fresh raw snapshot
 * @returns {?object} typed dispatch request, or null
 */
function dispatchTarget(record, snapshot) {
  if (!record || !record.key) return null
  var current = sourceRecords(snapshot).filter(function (row) {
    return row.key === record.key
  })[0]
  if (!current) return null
  if (current.type === "app")
    return { kind: "app", appId: current.target.appId, label: current.label }
  if (current.type === "command") return { kind: "command", itemId: current.target.itemId }
  if (current.type === "setting")
    return {
      kind: "argv",
      argv: [
        "omarchy-shell",
        "shell",
        "summon",
        "araneadev.settings",
        JSON.stringify({ section: current.target.section })
      ]
    }
  var field = current.type === "window" ? "window" : "workspace"
  var identity =
    current.type === "window" ? "address:" + current.target.address : current.target.selector
  return {
    kind: "argv",
    argv: ["hyprctl", "dispatch", "hl.dsp.focus({ " + field + " = " + luaString(identity) + " })"]
  }
}

if (typeof module !== "undefined")
  module.exports = {
    collectionValues,
    windowAddress,
    workspaceSelector,
    luaString,
    sourceRecords,
    dispatchTarget,
    settingRecords
  }
