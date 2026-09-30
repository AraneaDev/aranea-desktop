// Behaviour of the menu's app history (MenuAppHistory.qml): pins and recents
// persist to menu.json, a 13th pin is refused with a notice, the Apps rows
// carry Favorites and Recent with copies of their apps, uninstalled ids are
// pruned, and closing the menu clears the uninstall prompt.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // Notices the history asked for.
  property var notices: []
  // Apps the fake library lists.
  property var apps: [{
      id: "firefox",
      name: "Firefox"
    }, {
      id: "gimp",
      name: "GIMP"
    }]
  // State directory for this run (the sandbox creates it; menu.json goes straight in).
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME")

  QmlTest {
    id: t
  }

  // Stands in for the shared app library.
  QtObject {
    id: fakeLibrary
    // Every app, as the library's sorted rows.
    function sortedEntries(query) {
      return shell.apps.map(function (entry) {
        return {
          entry: entry
        }
      })
    }
    // Display name of an entry.
    function entryName(entry) {
      return entry.name
    }
    // Subtext of an entry.
    function entrySubtext(entry) {
      return ""
    }
  }

  Menu.MenuAppHistory {
    id: history
    stateRoot: shell.stateRoot
    onNoticeRequested: function (text) {
      shell.notices = shell.notices.concat([text])
    }
  }

  // Creates a second history on the same state file.
  Component {
    id: historyComponent
    Menu.MenuAppHistory {}
  }

  // Ids of ROWS whose parent is PARENT.
  function childIds(rows, parent) {
    return rows.filter(function (row) {
      return row.parent === parent
    }).map(function (row) {
      return row.id
    })
  }

  Component.onCompleted: {
    history.toggleFavorite("firefox")
    history.recordRecent("gimp")
    t.equal(JSON.stringify(history.favoriteAppIds), JSON.stringify(["firefox"]), "a pin is recorded")
    t.equal(JSON.stringify(history.recentAppIds), JSON.stringify(["gimp"]), "a launch is recorded")

    var rows = history.rowsFor(fakeLibrary)
    t.check(childIds(rows, "apps").indexOf("apps.favorites") >= 0, "Apps carries Favorites")
    t.check(childIds(rows, "apps").indexOf("apps.recent") >= 0, "Apps carries Recent")
    t.check(childIds(rows, "apps").indexOf("apps.firefox") >= 0, "Apps lists every app")
    t.equal(childIds(rows, "apps.favorites").length, 1, "Favorites holds the pinned app")
    t.equal(childIds(rows, "apps.recent").length, 1, "Recent holds the launched app")

    for (var i = 0; i < 12; i++)
      history.toggleFavorite("extra" + i)
    t.equal(history.favoriteAppIds.length, 12, "twelve pins at most")
    t.equal(shell.notices[shell.notices.length - 1], "12 FAVOURITES · UNPIN ONE FIRST", "the 13th asks to unpin one")

    history.rowsFor(fakeLibrary)
    t.equal(JSON.stringify(history.favoriteAppIds), JSON.stringify(["firefox"]), "uninstalled pins are pruned")

    history.requestDelete("gimp", "GIMP")
    t.equal(history.deleteConfirmOpen, true, "the uninstall prompt opens")
    history.opened = true
    history.opened = false
    t.equal(history.deleteConfirmOpen, false, "closing the menu clears it")
    t.equal(history.deleteTarget, null, "and its target")
    history.requestDelete("gimp", "GIMP")
    t.equal(history.takeDeleteTarget().appId, "gimp", "confirm takes the target")
    t.equal(history.deleteConfirmOpen, false, "and closes the prompt")

    var reloaded = historyComponent.createObject(shell, {
      stateRoot: shell.stateRoot
    })
    t.waitFor(function () {
      return reloaded.favoriteAppIds.length === 1
    }, 10000, "a new history reads the state file", function () {
      t.equal(JSON.stringify(reloaded.recentAppIds), JSON.stringify(["gimp"]), "recents survive a restart")
      t.done()
    })
  }
}
