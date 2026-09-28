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

if (typeof module !== "undefined") {
  module.exports = {
    normalizeWorkspaces,
    ensureStandardWorkspaces,
    visibleWorkspaces,
    overviewWorkspaces,
    indicatorDots,
    cycleTarget
  }
}
