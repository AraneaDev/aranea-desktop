// Pure rules for the Aranea Tray dropdowns (the app menu and the manage
// panel): mnemonic stripping, the row list a QsMenuOpener's children become
// (with stock's hiding quirks applied), keyed rows so a live menu rebuild
// never retargets a click, cursor movement for both popups (wrapping in the
// menu, clamping in manage), jump-to-letter, the breadcrumb, pin/hide list
// edits and the IPC `menu <index>` target. No QML, no Qt enums (`checkState`
// and `buttonType` are plain strings here; Task 5 converts
// `QsMenuButtonType`/`Qt.Checked` into this shape); tests/js/tray-logic.test.js
// runs this under Node.
//
// Stock quirks are read from
// `/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml` (850 lines):
// `rootTitleEntry`/`leadingSeparator`/`hiddenRow` (~652-663), `displayName`
// (manage row, ~448-456) and `togglePin`/`toggleHide` (~189-211). Stock
// itself never strips mnemonics (its row Text just shows `modelData.text`
// raw); `labelOf` is this rebuild's own addition for the keyboard-menus
// extra (type-to-jump) and is applied to every row's `label` before the
// root-title comparison, so a title entry carrying a mnemonic still matches
// a plain `appTitle`.

/**
 * A DBus menu entry, shaped like `QsMenuEntry` (Task 5 converts the real
 * `QsMenuButtonType`/`Qt.Checked` values into these plain strings).
 * @typedef {{id: *, text: string, enabled: boolean, isSeparator: boolean, hasChildren: boolean, buttonType: ("none"|"check"|"radio"), checkState: ("checked"|"unchecked"|"partial"), icon: *}} MenuEntry
 */

/**
 * One row `TrayMenuView.qml` draws. The row's own `index` is the DBus source
 * entry's index in the array `menuRows` was given, needed to activate the
 * real `QsMenuEntry`. It is not the `index` the view's actions and cursor
 * carry: an action's `index` is a position in the rows array, checked
 * against its `key` (refusing a stale action after a live menu rebuild)
 * before the entry at `rows[index].index` is activated.
 * @typedef {{key: string, label: string, separator: boolean, enabled: boolean, selectable: boolean, mark: ("" | "check" | "radio"), markOn: boolean, hasChildren: boolean, icon: *, index: number}} MenuRow
 */

/**
 * The manage panel's keyboard cursor: which row, and which pill (Pin is 0,
 * Hide is 1).
 * @typedef {{row: number, pill: (0|1)}} ManageCursor
 */

/**
 * The lists `togglePin`/`toggleHide` return, ready for
 * `bar.shell.updateEntryInline`.
 * @typedef {{pinned: Array<string>, hidden: Array<string>}} PinHideLists
 */

/**
 * Where IPC's `menu <index>` points: the pinned item at that index, or the
 * drawer item when the index is past the pinned items.
 * @typedef {{bucket: ("pinned"|"drawer"), index: number}} MenuTarget
 */

/**
 * Coerces a value to an array, matching stock's
 * `settings.pinned instanceof Array ? settings.pinned : []` guard.
 * @param {*} v - the value
 * @returns {Array<*>} v itself when it is an array, else []
 */
function toArray(v) {
  return Array.isArray(v) ? v : []
}

/**
 * Strips a QMenu-style mnemonic marker from a label: a single `_` or `&` is
 * removed (the character it marks becomes the shortcut), and a doubled
 * `__`/`&&` is a literal `_`/`&` in the text. The result is trimmed. Stock
 * never does this itself (its row text shows the marker raw); it exists for
 * this rebuild's type-to-jump and for matching a root title entry whose text
 * carries a mnemonic.
 * @param {*} text - the raw entry text
 * @returns {string} the display label
 */
function labelOf(text) {
  var s = String(text === undefined || text === null ? "" : text)
  var out = ""
  for (var i = 0; i < s.length; i++) {
    var c = s[i]
    if ((c === "_" || c === "&") && s[i + 1] === c) {
      out += c
      i++
    } else if (c === "_" || c === "&") {
      // Mnemonic marker: dropped, marks no visible character.
    } else {
      out += c
    }
  }
  return out.trim()
}

/**
 * A menu row's keyed identity: the DBus entry's `id` plus its stripped
 * label, so a live menu rebuild (an app replacing its menu while open) can
 * be told apart from the row that used to be at the same index. A
 * non-object entry reads as the key for an empty id and label, never
 * throwing.
 * @param {MenuEntry|null|undefined} entry - the entry
 * @returns {string} "id|label"
 */
function rowKey(entry) {
  var id = entry && typeof entry === "object" ? entry.id : undefined
  var text = entry && typeof entry === "object" ? entry.text : undefined
  return String(id === undefined || id === null ? "" : id) + "|" + labelOf(text)
}

/**
 * The rows `TrayMenuView.qml` draws from a `QsMenuOpener`'s children,
 * applying stock's two root-only hiding quirks
 * (`/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml` ~652-663):
 * - a leading separator (`isSeparator` at source index 0 or 1) is dropped;
 * - a root title entry (source index 0, `hasChildren`, whose stripped label
 *   equals `appTitle` case-insensitively) is dropped, so an app that
 *   repeats its own name as the first menu entry does not show it twice.
 *
 * Both quirks apply only `atRoot`; a drilled-in submenu's own first rows are
 * real entries and are never hidden. A non-array `entries` gives [].
 * @param {Array<MenuEntry>|null|undefined} entries - the opener's children, in source order
 * @param {boolean} atRoot - whether this is the root menu (not a drilled-in submenu)
 * @param {string} appTitle - the tray item's title, for the root-title quirk
 * @returns {Array<MenuRow>} the rows to draw, source order
 */
function menuRows(entries, atRoot, appTitle) {
  if (!Array.isArray(entries)) return []
  var title = String(appTitle === undefined || appTitle === null ? "" : appTitle)
    .trim()
    .toLowerCase()
  /** @type {Array<MenuRow>} */
  var rows = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!entry || typeof entry !== "object") continue
    var isSeparator = !!entry.isSeparator
    var hasChildren = !!entry.hasChildren
    var label = labelOf(entry.text)

    var leadingSeparator = !!atRoot && isSeparator && i <= 1
    var rootTitleEntry = !!atRoot && i === 0 && hasChildren && label.toLowerCase() === title
    if (leadingSeparator || rootTitleEntry) continue

    var enabled = !!entry.enabled
    /** @type {"" | "check" | "radio"} */
    var mark = entry.buttonType === "check" || entry.buttonType === "radio" ? entry.buttonType : ""

    rows.push({
      key: rowKey(entry),
      label: label,
      separator: isSeparator,
      enabled: !isSeparator && enabled,
      selectable: !isSeparator && enabled,
      mark: isSeparator ? "" : mark,
      markOn: !isSeparator && entry.checkState === "checked",
      hasChildren: !isSeparator && hasChildren,
      icon: entry.icon,
      index: i
    })
  }
  return rows
}

/**
 * The index of the row keyed KEY, or -1. Used to refuse a `{index, key}`
 * action once the row at that index no longer carries that key (a menu
 * rebuilt live, or manage's item list changed).
 * @param {Array<{key: string}>|null|undefined} rows - the current rows
 * @param {*} key - the key a click or Enter carries
 * @returns {number} the row index, or -1
 */
function indexOfKey(rows, key) {
  if (!Array.isArray(rows)) return -1
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] && rows[i].key === key) return i
  }
  return -1
}

/**
 * True when a row can take the keyboard cursor: present, not a separator,
 * and enabled.
 * @param {MenuRow|null|undefined} row - the row
 * @returns {boolean} true when selectable
 */
function isSelectableRow(row) {
  return !!row && !row.separator && !!row.enabled
}

/**
 * The next selectable row from a keyboard cursor move, skipping separators
 * and disabled rows and wrapping at either end. `from` of -1 (no cursor
 * yet) starts the search so the first selectable row is picked for a
 * forward move (`delta > 0`) and the last selectable row for a backward one
 * (`delta < 0`). -1 when no row is selectable, or `rows` is empty.
 * @param {Array<MenuRow>|null|undefined} rows - the current rows
 * @param {number} from - the current cursor row, or -1 for none
 * @param {number} delta - the direction: positive for next, negative for previous
 * @returns {number} the next cursor row, or -1
 */
function nextCursor(rows, from, delta) {
  if (!Array.isArray(rows) || rows.length === 0) return -1
  var n = rows.length
  var step = delta < 0 ? -1 : 1
  var valid = typeof from === "number" && from >= 0 && from < n
  var idx = valid ? from : step > 0 ? -1 : 0
  for (var i = 0; i < n; i++) {
    idx += step
    if (idx < 0) idx = n - 1
    else if (idx >= n) idx = 0
    if (isSelectableRow(rows[idx])) return idx
  }
  return -1
}

/**
 * The next selectable row after `from` whose label starts with `letter`
 * (case-insensitive; labels already have their mnemonic markers stripped by
 * `menuRows`), wrapping past the end and cycling back onto `from` itself
 * when it is the only match (so typing the same letter repeatedly cycles
 * through every row that starts with it). `from` when there is no match, no
 * `letter`, or `rows` is empty/invalid.
 * @param {Array<MenuRow>|null|undefined} rows - the current rows
 * @param {number} from - the current cursor row, or -1 for none
 * @param {string} letter - the typed character
 * @returns {number} the row to jump to, or `from`
 */
function jumpTo(rows, from, letter) {
  if (!Array.isArray(rows) || rows.length === 0) return from
  if (typeof letter !== "string" || letter.length === 0) return from
  var target = letter.charAt(0).toLowerCase()
  var n = rows.length
  var start = typeof from === "number" ? from : -1
  for (var i = 1; i <= n; i++) {
    var idx = (((start + i) % n) + n) % n
    var row = rows[idx]
    if (
      isSelectableRow(row) &&
      typeof row.label === "string" &&
      row.label.charAt(0).toLowerCase() === target
    ) {
      return idx
    }
  }
  return from
}

/**
 * The app menu's breadcrumb: the app title, then each drilled-into
 * submenu's title, joined "Courier › Send a file" style. Falsy entries
 * (including a non-array `stackTitles`) are skipped rather than throwing.
 * @param {Array<string>|null|undefined} stackTitles - the submenu stack's titles, outermost first
 * @param {string} appTitle - the tray item's title
 * @returns {string} the breadcrumb, or "" when nothing names it
 */
function crumb(stackTitles, appTitle) {
  var parts = []
  if (appTitle) parts.push(String(appTitle))
  var titles = toArray(stackTitles)
  for (var i = 0; i < titles.length; i++) {
    if (titles[i]) parts.push(String(titles[i]))
  }
  return parts.join(" › ")
}

/**
 * Toggles ID in `pinned`, matching stock's `togglePin`
 * (`/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml` ~189-199):
 * pinning un-hides the item (hide and pin are exclusive); unpinning leaves
 * `hidden` alone. Returns new arrays; the inputs are never mutated.
 * @param {Array<string>|null|undefined} pinned - the current pinned ids
 * @param {Array<string>|null|undefined} hidden - the current hidden ids
 * @param {string} id - the item id to toggle
 * @returns {PinHideLists} the updated lists
 */
function togglePin(pinned, hidden, id) {
  var p = toArray(pinned).slice()
  var h = toArray(hidden).slice()
  var idx = p.indexOf(id)
  if (idx !== -1) {
    p.splice(idx, 1)
  } else {
    p.push(id)
    var hi = h.indexOf(id)
    if (hi !== -1) h.splice(hi, 1)
  }
  return { pinned: p, hidden: h }
}

/**
 * Toggles ID in `hidden`, matching stock's `toggleHide`
 * (`/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml` ~201-211): hiding
 * un-pins the item; unhiding leaves `pinned` alone. Returns new arrays; the
 * inputs are never mutated.
 * @param {Array<string>|null|undefined} pinned - the current pinned ids
 * @param {Array<string>|null|undefined} hidden - the current hidden ids
 * @param {string} id - the item id to toggle
 * @returns {PinHideLists} the updated lists
 */
function toggleHide(pinned, hidden, id) {
  var p = toArray(pinned).slice()
  var h = toArray(hidden).slice()
  var idx = h.indexOf(id)
  if (idx !== -1) {
    h.splice(idx, 1)
  } else {
    h.push(id)
    var pi = p.indexOf(id)
    if (pi !== -1) p.splice(pi, 1)
  }
  return { pinned: p, hidden: h }
}

/**
 * The manage panel's cursor after an arrow key: up/down move between rows
 * (clamped to `[0, rowCount)`, never wrapping, unlike the app menu); left
 * picks the Pin pill, right picks the Hide pill. An out-of-range or missing
 * `cursor` reads as `{row: 0, pill: 0}` first. `rowCount` of 0 clamps the
 * row to 0.
 * @param {ManageCursor|null|undefined} cursor - the current cursor
 * @param {number} rowCount - how many rows the panel has
 * @param {("up"|"down"|"left"|"right")} key - the key pressed
 * @returns {ManageCursor} the new cursor
 */
function manageMove(cursor, rowCount, key) {
  var n = Math.max(0, Math.floor(Number(rowCount)) || 0)
  var row =
    cursor && typeof cursor === "object" && typeof cursor.row === "number" && isFinite(cursor.row)
      ? cursor.row
      : 0
  /** @type {0 | 1} */
  var pill = cursor && typeof cursor === "object" && cursor.pill === 1 ? 1 : 0

  if (key === "up") row -= 1
  else if (key === "down") row += 1
  else if (key === "left") pill = 0
  else if (key === "right") pill = 1

  var maxRow = Math.max(0, n - 1)
  if (row < 0) row = 0
  else if (row > maxRow) row = maxRow

  return { row: row, pill: pill }
}

/**
 * Where IPC's `menu <index>` opens: the pinned item at INDEX, or the drawer
 * item at `index - pinnedCount` when INDEX is past the pinned items. null
 * when INDEX is negative, non-finite or past both buckets (a no-op).
 * @param {number} pinnedCount - how many items are pinned
 * @param {number} drawerCount - how many items are in the drawer
 * @param {number} index - the index IPC named
 * @returns {MenuTarget|null} the target, or null
 */
function menuTarget(pinnedCount, drawerCount, index) {
  var p = Math.max(0, Math.floor(Number(pinnedCount)) || 0)
  var d = Math.max(0, Math.floor(Number(drawerCount)) || 0)
  var i = Math.floor(Number(index))
  if (!isFinite(i) || i < 0) return null
  if (i < p) return { bucket: "pinned", index: i }
  var di = i - p
  if (di < d) return { bucket: "drawer", index: di }
  return null
}

/**
 * The manage row's display name, matching stock's fallback order
 * (`/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml` ~448-456):
 * `title`, then `tooltipTitle`, then the id after its last `/`, then
 * "Unknown". A missing/non-object `item` reads as "Unknown" too.
 * @param {{title?: *, tooltipTitle?: *, id?: *}|null|undefined} item - the tray item
 * @returns {string} the name to show
 */
function displayName(item) {
  var it = item && typeof item === "object" ? item : {}
  var t = String(it.title === undefined || it.title === null ? "" : it.title).trim()
  if (t) return t
  var tt = String(
    it.tooltipTitle === undefined || it.tooltipTitle === null ? "" : it.tooltipTitle
  ).trim()
  if (tt) return tt
  var id = String(it.id === undefined || it.id === null ? "" : it.id)
  var slash = id.lastIndexOf("/")
  return slash !== -1 ? id.substring(slash + 1) : id || "Unknown"
}

if (typeof module !== "undefined")
  module.exports = {
    labelOf: labelOf,
    rowKey: rowKey,
    menuRows: menuRows,
    indexOfKey: indexOfKey,
    nextCursor: nextCursor,
    jumpTo: jumpTo,
    crumb: crumb,
    togglePin: togglePin,
    toggleHide: toggleHide,
    manageMove: manageMove,
    menuTarget: menuTarget,
    displayName: displayName
  }
