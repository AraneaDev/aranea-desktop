// Pure workspace normalization for the bar widget. It deliberately accepts
// plain data so the behavior can be tested without Quickshell.

/**
 * Convert a value to a finite number or return the fallback.
 * @param {*} value - Candidate numeric value.
 * @param {*} fallback - Value used when conversion fails.
 * @returns {number|null} The finite number or fallback.
 */
function numberOr(value, fallback) {
  var number = Number(value)
  return Number.isFinite(number) ? number : fallback
}

/**
 * Extract a workspace id from a row-like value.
 * @param {*} row - Workspace row or primitive id.
 * @returns {number|null} The normalized workspace id.
 */
function workspaceId(row) {
  if (typeof row === "number" || typeof row === "string") return numberOr(row, null)
  if (!row || typeof row !== "object") return null
  return numberOr(row.id !== undefined ? row.id : row.workspaceId, null)
}

/**
 * Resolve the display name for a workspace row.
 * @param {*} row - Workspace row.
 * @param {number} id - Fallback workspace id.
 * @returns {string} The display name.
 */
function workspaceName(row, id) {
  if (row && typeof row === "object" && row.name !== undefined && row.name !== null)
    return String(row.name)
  return String(id)
}

/**
 * Convert arrays and QML list wrappers to a plain array.
 * @param {*} collection - Collection or list wrapper.
 * @returns {Array<any>} Collection values.
 */
function collectionValues(collection) {
  if (Array.isArray(collection)) return collection
  if (collection && collection.values !== undefined) return collectionValues(collection.values)
  if (collection && Number.isFinite(Number(collection.length))) {
    var values = []
    for (var index = 0; index < Number(collection.length); index++) values.push(collection[index])
    return values
  }
  return []
}

/**
 * Count windows in a workspace row.
 * @param {*} row - Workspace row.
 * @returns {number} Window count.
 */
function windowCount(row) {
  if (!row || typeof row !== "object") return 0
  var windows = row.windows !== undefined ? row.windows : row.toplevels
  var values = collectionValues(windows)
  if (values.length) return values.length
  return Math.max(0, numberOr(row.windows, 0))
}

/**
 * Extract readable labels from a workspace's windows.
 * @param {*} row - Workspace row.
 * @returns {Array<string>} Window labels.
 */
function windowLabels(row) {
  if (!row || typeof row !== "object") return []
  var windows = row.windows !== undefined ? row.windows : row.toplevels
  return collectionValues(windows)
    .map(function (/** @type {*} */ window) {
      if (typeof window === "string") return window
      if (!window || typeof window !== "object") return ""
      return String(window.title || window.appId || window.class || window.address || "")
    })
    .filter(function (/** @type {string} */ label) {
      return label !== ""
    })
}

/**
 * Determine whether a workspace row represents a special workspace.
 * @param {*} row - Workspace row.
 * @param {string} name - Workspace name.
 * @param {number} id - Workspace id.
 * @returns {boolean} Whether the workspace is special.
 */
function isSpecial(row, name, id) {
  return (
    !!(row && typeof row === "object" && row.special) || id < 0 || name.indexOf("special:") === 0
  )
}

/**
 * Normalize raw workspace rows and derive their display state.
 * @param {*} rawWorkspaces - Workspace collection.
 * @param {*} focusedId - Focused workspace id.
 * @param {*} monitorName - Fallback monitor name.
 * @returns {Array<any>} Normalized workspace states.
 */
function normalizeWorkspaces(rawWorkspaces, focusedId, monitorName) {
  var rows = []
  if (Array.isArray(rawWorkspaces)) {
    rows = rawWorkspaces
  } else if (rawWorkspaces && Number.isFinite(Number(rawWorkspaces.length))) {
    // Quickshell exposes some object-list properties as QML list wrappers,
    // which are indexable but do not pass Array.isArray in JavaScript.
    for (var index = 0; index < Number(rawWorkspaces.length); index++)
      rows.push(rawWorkspaces[index])
  }
  var focused = numberOr(focusedId, null)
  if (!rows.length && focused !== null) rows = [{ id: focused }]
  var fallbackMonitor = String(monitorName || "")
  /** @type {{[key: string]: any}} */
  var byId = {}

  /** @param {*} row */
  rows.forEach(function (row) {
    var id = workspaceId(row)
    if (id === null) return
    var name = workspaceName(row, id)
    var windows = windowCount(row)
    var labels = windowLabels(row)
    var existing = byId[id]
    var monitor =
      row && typeof row === "object" && row.monitor !== undefined
        ? String(row.monitor || "")
        : fallbackMonitor
    var state = {
      id: id,
      name: name,
      active: id === focused,
      occupied: windows > 0,
      urgent: !!(row && typeof row === "object" && (row.urgent || row.hasUrgentWindow)),
      monitor: monitor,
      windows: windows,
      windowLabels: labels,
      special: isSpecial(row, name, id)
    }
    if (!existing) {
      byId[id] = state
      return
    }
    existing.active = existing.active || state.active
    existing.occupied = existing.occupied || state.occupied
    existing.urgent = existing.urgent || state.urgent
    existing.windows = Math.max(existing.windows, state.windows)
    existing.windowLabels = existing.windowLabels.concat(
      state.windowLabels.filter(function (label) {
        return existing.windowLabels.indexOf(label) === -1
      })
    )
    existing.special = existing.special || state.special
    if (!existing.monitor) existing.monitor = state.monitor
  })

  return Object.keys(byId)
    .map(function (key) {
      return byId[key]
    })
    .sort(function (left, right) {
      if (left.special !== right.special) return left.special ? 1 : -1
      return left.id - right.id
    })
}

/**
 * Add standard workspace rows that are absent from compositor data.
 * @param {*} rawWorkspaces - Workspace collection.
 * @returns {Array<any>} Rows including workspaces one through five.
 */
function ensureStandardWorkspaces(rawWorkspaces) {
  var rows = []
  if (Array.isArray(rawWorkspaces)) {
    rows = rawWorkspaces.slice()
  } else if (rawWorkspaces && Number.isFinite(Number(rawWorkspaces.length))) {
    var indexed = /** @type {any} */ (rawWorkspaces)
    for (var index = 0; index < Number(rawWorkspaces.length); index++) rows.push(indexed[index])
  }
  /** @type {{[key: string]: boolean}} */
  var known = {}
  rows.forEach(function (row) {
    var id = workspaceId(row)
    if (id !== null) known[id] = true
  })
  for (var id = 1; id <= 5; id++) {
    if (!known[id]) rows.push({ id: id, windows: [] })
  }
  return rows
}

/**
 * Keep only meaningful workspaces for the overview.
 * @param {*} states - Normalized workspace states.
 * @returns {Array<any>} Visible workspace states.
 */
function visibleWorkspaces(states) {
  var rows = Array.isArray(states) ? states : []
  return rows.filter(function (row) {
    return row && (row.active || row.occupied || row.urgent || row.special)
  })
}

/**
 * Keep normal workspaces for the overview model.
 * @param {*} states - Normalized workspace states.
 * @returns {Array<any>} Normal workspace states.
 */
function overviewWorkspaces(states) {
  var rows = Array.isArray(states) ? states : []
  return rows.filter(function (row) {
    return row && !row.special
  })
}

/**
 * Build the standard workspace indicators for the bar.
 * @param {*} states - Normalized workspace states.
 * @returns {Array<any>} Indicator state rows.
 */
function indicatorDots(states) {
  return overviewWorkspaces(states).map(function (row) {
    return { id: row.id, active: !!row.active, urgent: !!row.urgent }
  })
}

/**
 * Select the next visible normal workspace in a direction.
 * @param {*} states - Normalized workspace states.
 * @param {*} currentId - Current workspace id.
 * @param {*} direction - Direction, where negative means previous.
 * @returns {number|null} Target workspace id.
 */
function cycleTarget(states, currentId, direction) {
  var rows = visibleWorkspaces(states).filter(function (row) {
    return !row.special
  })
  if (!rows.length) return null
  var current = numberOr(currentId, rows[0].id)
  var index = rows.findIndex(function (row) {
    return row.id === current
  })
  if (index < 0) index = 0
  var step = Number(direction) < 0 ? -1 : 1
  var target = (index + step + rows.length) % rows.length
  return rows[target].id
}

/**
 * The key a workspace row is followed and acted on by: its id.
 * @param {*} row - Workspace row.
 * @returns {string} The id as a string, "" when absent.
 */
function workspaceKey(row) {
  if (!row || typeof row !== "object" || row.id === undefined || row.id === null) return ""
  return String(row.id)
}

/**
 * Every row's workspaceKey joined by newlines, so a host can tell when the
 * rows really moved (an equal list rebuilt gives the same string).
 * @param {*} rows - Workspace rows.
 * @returns {string} The joined keys, "" for no rows.
 */
function workspaceKeys(rows) {
  return (Array.isArray(rows) ? rows : []).map(workspaceKey).join("\n")
}

/**
 * Position of the row with this key (its workspaceKey: the workspace id).
 * @param {*} rows - Workspace rows.
 * @param {string} key - The row key, e.g. "2".
 * @returns {number} Its index, or -1 (always for an empty key).
 */
function indexOfKey(rows, key) {
  if (!key) return -1
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) if (workspaceKey(list[i]) === key) return i
  return -1
}

/**
 * The row a keyed action names: row `index`, but only while it still has
 * `key`, so a click or Enter aimed before the workspaces change never
 * focuses another one.
 * @param {*} rows - Workspace rows.
 * @param {number} index - The row the action names.
 * @param {*} key - The key the view saw at that row.
 * @returns {?object} The row, or null when it no longer carries the key.
 */
function keyedWorkspace(rows, index, key) {
  if (typeof key !== "string" || key === "") return null
  var list = Array.isArray(rows) ? rows : []
  var row = list[index]
  return row && workspaceKey(row) === key ? row : null
}

/**
 * Key of the row delta steps from the row with this key, wrapping; the
 * first (delta > 0) or last row when the key is empty or gone.
 * @param {*} rows - Workspace rows.
 * @param {string} key - The current cursor key, or "".
 * @param {number} delta - Rows to move (sign matters).
 * @returns {string} The new cursor key, or "" when there are no rows.
 */
function moveCursorKey(rows, key, delta) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0) return ""
  var i = key ? indexOfKey(list, key) : -1
  if (i < 0) return workspaceKey(list[delta < 0 ? list.length - 1 : 0])
  return workspaceKey(list[(i + delta + list.length) % list.length])
}

/**
 * The cursor after an up or down key. The first key after opening or after
 * pointer use (keyboard false) only reveals the cursor: on the row the
 * pointer left it on, else the first (dy > 0) or last row. Later keys move
 * it, wrapping.
 * @param {*} rows - Workspace rows.
 * @param {string} key - The cursor's key, or "".
 * @param {boolean} keyboard - Whether the keyboard is showing the cursor.
 * @param {number} dy - Rows to move (sign matters); 0 does nothing.
 * @returns {{key: string, keyboard: boolean}} The new cursor key and mode.
 */
function cursorMove(rows, key, keyboard, dy) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0 || !dy) return { key: key, keyboard: keyboard }
  if (!keyboard)
    return {
      key: indexOfKey(list, key) >= 0 ? key : moveCursorKey(list, "", dy),
      keyboard: true
    }
  return { key: moveCursorKey(list, key, dy), keyboard: true }
}

/**
 * What Enter or Space does: nothing without a cursor, only reveal one the
 * keyboard is not showing, else focus the cursor's workspace.
 * @param {*} rows - Workspace rows.
 * @param {string} key - The cursor's key, or "".
 * @param {boolean} keyboard - Whether the keyboard is showing the cursor.
 * @returns {{keyboard: boolean, row: ?object}} The new mode and the row to
 *   focus, or null.
 */
function cursorPress(rows, key, keyboard) {
  var i = indexOfKey(rows, key)
  if (i < 0) return { keyboard: keyboard, row: null }
  return { keyboard: true, row: keyboard ? rows[i] : null }
}

/**
 * The row the mint outline is drawn on: the cursor's, only while the
 * keyboard drives it.
 * @param {*} rows - Workspace rows.
 * @param {string} key - The cursor's key, or "".
 * @param {boolean} keyboard - Whether the keyboard is showing the cursor.
 * @returns {number} The row index, or -1 for no outline.
 */
function outlineIndex(rows, key, keyboard) {
  return keyboard ? indexOfKey(rows, key) : -1
}

/**
 * The dropdown header's caption: how many workspaces are shown.
 * @param {number} count - Number of visible workspace rows.
 * @returns {string} "N open".
 */
function openCaption(count) {
  return Math.max(0, Number(count) || 0) + " open"
}

/**
 * A row's label: "Workspace" plus its display name.
 * @param {*} row - Workspace row.
 * @returns {string} The row's label.
 */
function workspaceLabel(row) {
  var name = row && row.name !== undefined && row.name !== null ? row.name : ""
  return "Workspace " + name
}

/**
 * A row's trailing detail: the window count ("empty" for none), with
 * "current" appended for the active workspace.
 * @param {*} row - Workspace row.
 * @returns {string} The detail text.
 */
function workspaceDetail(row) {
  var windows = Math.max(0, Number(row && row.windows) || 0)
  var label = windows === 0 ? "empty" : windows + (windows === 1 ? " window" : " windows")
  return row && row.active ? label + " · current" : label
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeWorkspaces,
    ensureStandardWorkspaces,
    visibleWorkspaces,
    overviewWorkspaces,
    indicatorDots,
    cycleTarget,
    workspaceKey,
    workspaceKeys,
    indexOfKey,
    keyedWorkspace,
    moveCursorKey,
    cursorMove,
    cursorPress,
    outlineIndex,
    openCaption,
    workspaceLabel,
    workspaceDetail
  }
}
