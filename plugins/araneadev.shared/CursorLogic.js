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
