// Fallback application-library adapter for Menu.qml.
// Host-provided app libraries remain preferred; this adapter keeps the menu
// usable on older shells without taking ownership of menu state.
// qmllint disable missing-property unqualified

import QtQuick
import Quickshell
import qs.Commons

QtObject {
  id: library

  // Menu composition root used for launching and removing applications.
  property var owner: null

  // Notifies consumers when the desktop-entry source changes.
  signal appsChanged

  // Returns the display name for a desktop entry.
  function entryName(entry): string {
    return String((entry && entry.name) || (entry && entry.id) || "")
  }

  // Returns the secondary text for a desktop entry.
  function entrySubtext(entry): string {
    return String((entry && entry.genericName) || "")
  }

  // Returns sorted, query-filtered desktop entries in the app-library shape.
  function sortedEntries(query): var {
    var needle = String(query || "").trim().toLowerCase()
    var values = DesktopEntries.applications.values || []
    var rows = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay || !entryName(entry))
        continue
      var text = [entryName(entry), entrySubtext(entry), entry.comment, entry.id].join(" ").toLowerCase()
      if (needle && text.indexOf(needle) < 0)
        continue
      rows.push({
        entry: entry,
        score: needle ? 1 : 0,
        key: entryName(entry).toLowerCase(),
        name: entryName(entry).toLowerCase()
      })
    }
    rows.sort(function (a, b) {
      return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0)
    })
    return rows
  }

  // Resolves an icon name to a displayable URL.
  function iconSource(icon): string {
    var value = String(icon || "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
      return value
    if (value.charAt(0) === "/")
      return Util.fileUrl(value)
    return Quickshell.iconPath(value || "application-x-executable", true)
  }

  // Compatibility hook for host app-library refreshes.
  function refreshIcons(): void {
  }

  // Launches an application through the menu owner.
  function launch(desktopId, name): void {
    var id = String(desktopId || "")
    if (id && library.owner && library.owner.run)
      library.owner.run("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  // Removes an application entry through the menu owner.
  function remove(desktopId, name): void {
    var id = String(desktopId || "")
    if (id && library.owner && library.owner.run)
      library.owner.run(Util.shellQuote(library.owner.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " " + Util.shellQuote(id) + " " + Util.shellQuote(String(name || id)))
  }
}
