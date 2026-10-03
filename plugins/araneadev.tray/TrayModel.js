// Stock's tray bucket helpers, copied verbatim from
// `/usr/share/omarchy/shell/plugins/bar/widgets/TrayModel.js` apart from the
// docs: which tray items Omarchy itself owns (and so hides from the tray),
// and the small bar-layout lookup that drives the Dropbox case.

/**
 * Lowercase a tray item field for a case-insensitive name match.
 * @param {*} value - the raw field value
 * @returns {string} the lowercased string, "" for a missing value
 */
function text(value) {
  return String(value || "").toLowerCase()
}

/**
 * Whether a tray item's id, title or tooltip title contains a name.
 * @param {*} item - a SystemTray item (id, title, tooltipTitle)
 * @param {string} name - the lowercase name to look for
 * @returns {boolean} true when any field matches
 */
function itemNamed(item, name) {
  if (!item) return false
  return (
    text(item.id).indexOf(name) !== -1 ||
    text(item.title).indexOf(name) !== -1 ||
    text(item.tooltipTitle).indexOf(name) !== -1
  )
}

/**
 * A bar layout entry's module id, from a string entry or an object's id.
 * @param {*} entry - a layout entry (id string or {id} object)
 * @returns {string} the id, or "" when there is none
 */
function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object") {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

/**
 * Whether a bar layout places a given widget id in any section.
 * @param {*} layout - the bar's layout object ({left, center, right})
 * @param {string} id - the widget id to look for
 * @returns {boolean} true when the id appears in left, center or right
 */
function layoutHasWidget(layout, id) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout && layout[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return true
    }
  }
  return false
}

/**
 * Whether a tray item belongs to Omarchy itself, and so is hidden from the
 * tray rather than shown pinned, drawer or hidden. LocalSend's item shows no
 * state, offers only Open and Quit, and its primary click is a no-op, so
 * Share > Receive is the whole surface. Hiding it by hand doesn't stick
 * either: LocalSend picks a fresh tray id every launch.
 * @param {*} item - a SystemTray item
 * @param {*} layout - the bar's layout object, to detect the Dropbox widget
 * @returns {boolean} true when the item is owned by Omarchy
 */
function ownedByOmarchy(item, layout) {
  return (
    itemNamed(item, "localsend") ||
    (layoutHasWidget(layout, "omarchy.dropbox") && itemNamed(item, "dropbox"))
  )
}

if (typeof module !== "undefined") {
  module.exports = {
    itemNamed: itemNamed,
    entryId: entryId,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy
  }
}
