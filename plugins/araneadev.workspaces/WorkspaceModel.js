// Pure workspace normalization for the bar widget. It deliberately accepts
// plain data so the behavior can be tested without Quickshell.

// Generated copy of the shared cursor rules (tools/js-facade-generator.mjs),
// since there is no cross-.js-file import usable from both QML and Node;
// the keyed cursor helpers below wrap its keyed helpers with workspaceKey.
/* @aranea-facade-start: plugins/araneadev.shared/CursorLogic.js */
// Shared keyboard-cursor safety rules, moved out of the Network plugin so
// araneadev.vpn can reuse them: a cursor follows the row key it was put on
// (never its position), a lost or evacuated key is refused rather than
// retargeted, and a pointer action only ever lands on the row it names. No
// QML, no I/O; tests/js/cursor-logic.test.js runs this under Node. The
// keyed helpers (keyIndex, keyStep, keyedMove, keyedPress, keyedOutline)
// are Health's and Workspaces' dropdown cursors, keyed by a host function.

/**
 * The index a list cursor should sit on after its rows changed: the row
 * whose `key` equals `key` wherever it moved, else `fallback` clamped into
 * the list. Lets a cursor follow its network or profile across a re-sort
 * instead of staying on a position that now holds another row.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the new rows
 * @param {string|null|undefined} key - the key the cursor was on
 * @param {number} fallback - the index to clamp when the key is gone
 * @returns {number} the index, or -1 when there are no rows
 */
function reselectIndex(rows, key, fallback) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0) return -1
  if (typeof key === "string") {
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (row && row.key === key) return i
    }
  }
  var f = Math.floor(Number(fallback)) || 0
  return Math.max(0, Math.min(list.length - 1, f))
}

/**
 * Where a list cursor goes after its rows changed: onto the row whose `key`
 * equals `key`, wherever it moved. When that row is gone (or there was no
 * key), the index is clamped into the list but the key is dropped, so the
 * row that slid into its place is never adopted as the user's choice.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the new rows
 * @param {string|null|undefined} key - the key the cursor was deliberately put on, or ""
 * @param {number} index - the cursor's index before the change
 * @returns {{index: number, key: string, confirmed: boolean}} the new index (-1 with no rows), the key it keeps ("" when lost) and whether the cursor's row is the chosen one
 */
function followCursor(rows, key, index) {
  var list = Array.isArray(rows) ? rows : []
  var chosen = typeof key === "string" && key !== "" ? key : null
  var next = reselectIndex(list, chosen, index)
  var row = next >= 0 ? list[next] : null
  var confirmed = chosen !== null && !!row && row.key === chosen
  return { index: next, key: confirmed ? chosen : "", confirmed: confirmed }
}

/**
 * Whether the cursor's row is still the one the user chose: `key` isn't
 * empty (a hidden SSID or no choice never is) and the row at `index` has it.
 * Keyboard actions refuse otherwise.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the section's rows
 * @param {string|null|undefined} key - the key the cursor was put on
 * @param {number} index - the cursor's index
 * @returns {boolean} true when the keyboard may act on that row
 */
function cursorConfirmed(rows, key, index) {
  if (!Array.isArray(rows) || typeof key !== "string" || key === "") return false
  var row = rows[index]
  return !!row && row.key === key
}

/**
 * What Enter or `x` does: nothing before any cursor exists, only reveal a
 * cursor the keyboard isn't showing (one the pointer placed), else act.
 * @param {boolean} cursorActive - whether a cursor has been placed
 * @param {boolean} keyboardCursor - whether its outline is showing
 * @returns {string} `ignore`, `reveal` or `act`
 */
function pressIntent(cursorActive, keyboardCursor) {
  if (!cursorActive) return "ignore"
  return keyboardCursor ? "act" : "reveal"
}

/**
 * Hands back the array last stored under `name` when `next` has the same
 * content, so a view's Repeater keeps its delegates (and nothing slides
 * under a still pointer) on a refresh that changed nothing. Stores `next`
 * otherwise. `cache` is mutated in place.
 * @param {Record<string, any>|null|undefined} cache - the arrays kept so far, by name
 * @param {string} name - which row array this is
 * @param {Array<any>} next - the freshly built rows
 * @returns {Array<any>} the kept array or `next`
 */
function keepRows(cache, name, next) {
  if (!cache || typeof cache !== "object") return next
  var prev = cache[name]
  if (prev !== undefined && JSON.stringify(prev) === JSON.stringify(next)) return prev
  cache[name] = next
  return next
}

/**
 * Whether row `index` still carries `key`, so a pointer action reported for
 * one row never lands on another.
 * @param {Array<{key: string}|null|undefined>|undefined} rows - the section's rows
 * @param {number} index - the row the action names
 * @param {string|undefined} key - the key the view saw at that row
 * @returns {boolean} true when the row is the one the user clicked
 */
function rowKeyMatches(rows, index, key) {
  if (!Array.isArray(rows) || typeof key !== "string") return false
  var row = rows[index]
  return !!row && row.key === key
}

/**
 * Where the keyboard cursor goes after a row left the list (Bluetooth
 * Forget, Notifications Delete): the stop now at `lastIndex` (the row that
 * slid into the removed one's place), clamped to the last stop when it was
 * the bottom one. If `removedKey` still names a stop in `stops` (this read
 * hasn't caught up with the removal yet), that stop is returned as is
 * instead, since nothing has actually moved.
 * @param {Array<{key: string}|null|undefined>|undefined} stops - the stops, read after the removal
 * @param {string|null|undefined} removedKey - the key of the row that was removed
 * @param {number} lastIndex - the removed row's index before it left
 * @returns {{index: number, key: string}} the stop to keep the cursor on, or {index: -1, key: ""} with none left
 */
function afterRemoval(stops, removedKey, lastIndex) {
  var list = Array.isArray(stops) ? stops : []
  if (list.length === 0) return { index: -1, key: "" }
  if (typeof removedKey === "string" && removedKey !== "") {
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (row && row.key === removedKey) return { index: i, key: removedKey }
    }
  }
  var idx = Math.max(0, Math.min(list.length - 1, Math.floor(Number(lastIndex)) || 0))
  var stop = list[idx]
  return { index: idx, key: stop && typeof stop.key === "string" ? stop.key : "" }
}

/**
 * Position of the row whose `keyOf(row)` is `key`. The keyed-cursor helpers
 * below (keyStep, keyedMove, keyedPress, keyedOutline) follow a cursor by
 * the row key a host's `keyOf` gives (Health's problemKey, Workspaces'
 * workspaceKey), never by position.
 * @param {*} rows - the dropdown rows (anything but an array counts as none)
 * @param {string} key - the row key, or ""
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {number} its index, or -1 (always for an empty key)
 */
function keyIndex(rows, key, keyOf) {
  if (!key) return -1
  var list = Array.isArray(rows) ? rows : []
  for (var i = 0; i < list.length; i++) if (keyOf(list[i]) === key) return i
  return -1
}

/**
 * Key of the row `delta` steps from the row with this key, wrapping; the
 * first (delta > 0) or last row when the key is empty or gone.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the current cursor key, or ""
 * @param {number} delta - rows to move (sign matters)
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {string} the new cursor key, or "" when there are no rows
 */
function keyStep(rows, key, delta, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0) return ""
  var i = keyIndex(list, key, keyOf)
  if (i < 0) return keyOf(list[delta < 0 ? list.length - 1 : 0])
  return keyOf(list[(i + delta + list.length) % list.length])
}

/**
 * The cursor after an up or down key. Dropdowns are reveal-first: the first
 * key after opening or after pointer use (keyboard false) only reveals the
 * cursor, on the row the pointer left it on, else the first (dy > 0) or
 * last row. Later keys move it, wrapping.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {number} dy - rows to move (sign matters); 0 does nothing
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {{key: string, keyboard: boolean}} the new cursor key and mode
 */
function keyedMove(rows, key, keyboard, dy, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  if (list.length === 0 || !dy) return { key: key, keyboard: keyboard }
  if (!keyboard)
    return {
      key: keyIndex(list, key, keyOf) >= 0 ? key : keyStep(list, "", dy, keyOf),
      keyboard: true
    }
  return { key: keyStep(list, key, dy, keyOf), keyboard: true }
}

/**
 * What Enter or Space does on a keyed list. Like an arrow, it first only
 * reveals a cursor the keyboard is not showing: on its row when that is
 * still shown, else on the first row. Only on a shown cursor's row does it
 * hand that row back to act on. With no rows it does nothing.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {{key: string, keyboard: boolean, row: ?object}} the cursor key, the new mode and the row to act on, or null
 */
function keyedPress(rows, key, keyboard, keyOf) {
  var list = Array.isArray(rows) ? rows : []
  var i = keyIndex(list, key, keyOf)
  if (pressIntent(i >= 0, keyboard) === "act") return { key: key, keyboard: true, row: list[i] }
  if (list.length === 0) return { key: key, keyboard: keyboard, row: null }
  return { key: i >= 0 ? key : keyOf(list[0]), keyboard: true, row: null }
}

/**
 * The row the mint outline is drawn on: the cursor's, only while the
 * keyboard drives it.
 * @param {*} rows - the dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {(row: any) => string} keyOf - a row's key
 * @returns {number} the row index, or -1 for no outline
 */
function keyedOutline(rows, key, keyboard, keyOf) {
  return keyboard ? keyIndex(rows, key, keyOf) : -1
}

if (typeof module !== "undefined")
  module.exports = {
    reselectIndex: reselectIndex,
    followCursor: followCursor,
    cursorConfirmed: cursorConfirmed,
    pressIntent: pressIntent,
    keepRows: keepRows,
    rowKeyMatches: rowKeyMatches,
    afterRemoval: afterRemoval,
    keyIndex: keyIndex,
    keyStep: keyStep,
    keyedMove: keyedMove,
    keyedPress: keyedPress,
    keyedOutline: keyedOutline
  }
/* @aranea-facade-end */

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
 * Position of the row with this key (workspaceKey), by CursorLogic.keyIndex.
 * @param {*} rows - dropdown rows
 * @param {string} key - the row key
 * @returns {number} its index, or -1 (always for an empty key)
 */
function indexOfKey(rows, key) {
  return keyIndex(rows, key, workspaceKey)
}

/**
 * Key of the row delta steps from the row with this key, wrapping
 * (CursorLogic.keyStep).
 * @param {*} rows - dropdown rows
 * @param {string} key - the current cursor key, or ""
 * @param {number} delta - rows to move (sign matters)
 * @returns {string} the new cursor key, or "" when there are no rows
 */
function moveCursorKey(rows, key, delta) {
  return keyStep(rows, key, delta, workspaceKey)
}

/**
 * The cursor after an up or down key; the first key after opening or after
 * pointer use only reveals it (CursorLogic.keyedMove).
 * @param {*} rows - dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @param {number} dy - rows to move (sign matters); 0 does nothing
 * @returns {{key: string, keyboard: boolean}} the new cursor key and mode
 */
function cursorMove(rows, key, keyboard, dy) {
  return keyedMove(rows, key, keyboard, dy, workspaceKey)
}

/**
 * What Enter or Space does (CursorLogic.keyedPress): like an arrow, only
 * reveal a cursor the keyboard is not showing (on the first row when it
 * has none), else focus the cursor's row.
 * @param {*} rows - dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @returns {{key: string, keyboard: boolean, row: ?object}} the cursor key, the new mode and the row to focus, or null
 */
function cursorPress(rows, key, keyboard) {
  return keyedPress(rows, key, keyboard, workspaceKey)
}

/**
 * The row the mint outline is drawn on: the cursor's, only while the
 * keyboard drives it (CursorLogic.keyedOutline).
 * @param {*} rows - dropdown rows
 * @param {string} key - the cursor's key, or ""
 * @param {boolean} keyboard - whether the keyboard is showing the cursor
 * @returns {number} the row index, or -1 for no outline
 */
function outlineIndex(rows, key, keyboard) {
  return keyedOutline(rows, key, keyboard, workspaceKey)
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
 * "current" appended for the active workspace and "attention" appended for
 * an urgent one (either, both, or neither).
 * @param {*} row - Workspace row.
 * @returns {string} The detail text.
 */
function workspaceDetail(row) {
  var windows = Math.max(0, Number(row && row.windows) || 0)
  var parts = [windows === 0 ? "empty" : windows + (windows === 1 ? " window" : " windows")]
  if (row && row.active) parts.push("current")
  if (row && row.urgent) parts.push("attention")
  return parts.join(" · ")
}

/**
 * A row's secondary text: its open windows' titles, joined, "" when there
 * are none to show (so the row stays a single line).
 * @param {*} row - Workspace row.
 * @returns {string} The joined window titles.
 */
function workspaceTitles(row) {
  var labels = row && Array.isArray(row.windowLabels) ? row.windowLabels : []
  return labels
    .filter(function (/** @type {*} */ label) {
      return typeof label === "string" && label !== ""
    })
    .join(" · ")
}

/**
 * A host's layout-shift signature: every row's id paired with whether it
 * shows a titles line, joined. Unlike workspaceKeys (id order alone), this
 * also changes when a row's titles line appears or disappears, since that
 * resizes the row and can shift the ones below it under a resting pointer.
 * @param {*} rows - Workspace rows.
 * @returns {string} The joined signature, "" for no rows.
 */
function workspaceLayoutSignature(rows) {
  return (Array.isArray(rows) ? rows : [])
    .map(function (row) {
      return workspaceKey(row) + ":" + (workspaceTitles(row) !== "" ? "1" : "0")
    })
    .join("\n")
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
    workspaceDetail,
    workspaceTitles,
    workspaceLayoutSignature
  }
}
