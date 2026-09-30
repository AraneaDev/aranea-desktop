// Root API edge cases of the Aranea menu (Menu.qml, window off): every route
// clears a pending Favorites/Recent route, and the uninstall prompt opens only
// on an app row, clears when the menu closes, and removes the app on confirm.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // Commands and library calls the menu made, newest last.
  property var ran: []

  QmlTest {
    id: t
  }

  // Stands in for the host's shared app library (adds remove()).
  QtObject {
    id: fakeLibrary
    signal appsChanged

    // Display name of an entry.
    function entryName(entry) {
      return entry.name
    }
    // Subtext of an entry.
    function entrySubtext(entry) {
      return ""
    }
    // Two apps, as the library's sorted rows.
    function sortedEntries(query) {
      return [{
          entry: {
            id: "firefox",
            name: "Firefox"
          }
        }, {
          entry: {
            id: "gimp",
            name: "GIMP"
          }
        }]
    }
    // Nothing to refresh offscreen.
    function refreshIcons() {
    }
    // Records a launch.
    function launch(id, label) {
      shell.ran = shell.ran.concat([["launch", id]])
    }
    // Records an uninstall.
    function remove(id, label) {
      shell.ran = shell.ran.concat([["remove", id, label]])
    }
  }

  // Stands in for the host's scoped shell object.
  QtObject {
    id: fakeShell
    property var appLibrary: fakeLibrary
  }

  Menu.Menu {
    id: menu
    windowEnabled: false
    shell: fakeShell
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
    run: function (command) {
      shell.ran = shell.ran.concat([command])
    }
  }

  // A fake key event.
  function key(code) {
    return {
      key: code,
      modifiers: Qt.NoModifier,
      text: "",
      accepted: false
    }
  }

  // Index of the display row with ITEMID, or -1.
  function rowIndex(itemId) {
    for (var i = 0; i < menu.displayModel.count; i++)
      if (menu.displayModel.get(i).itemId === itemId)
        return i
    return -1
  }

  // Whether the uninstall prompt is showing.
  function deleteOpen() {
    return menu.deleteConfirmOpen
  }

  Component.onCompleted: {
    t.waitFor(function () {
      return menu.rowsLoaded && menu.menuSourcesReady
    }, 10000, "menu sources load", function () {
      // Every route clears a pending Favorites/Recent route.
      menu.pendingInitialMenu = "apps.recent"
      menu.openRoute("system")
      t.equal(menu.pendingInitialMenu, "", "another route clears it")
      menu.pendingInitialMenu = "apps.recent"
      menu.cancel()
      t.equal(menu.pendingInitialMenu, "", "cancel clears it")
      menu.pendingInitialMenu = "apps.recent"
      menu.open(JSON.stringify({
        mode: "select",
        options: ["One"]
      }))
      t.equal(menu.pendingInitialMenu, "", "a dmenu request clears it")
      menu.cancel()
      menu.pendingInitialMenu = "apps.recent"
      menu.resolvePendingAppsRoute()
      t.equal(menu.pendingInitialMenu, "", "resolving clears it")
      t.equal(menu.activeMenu, "apps.recent", "and opens the route")

      // Uninstall prompt: only on an app row.
      menu.openRoute("system")
      menu.selectedIndex = 0
      menu.cursorActive = true
      menu.handleKey(key(Qt.Key_Delete))
      t.equal(deleteOpen(), false, "Delete on a non-app row does nothing")
      menu.openRoute("apps")
      menu.selectedIndex = rowIndex("apps.gimp")
      menu.cursorActive = true
      menu.handleKey(key(Qt.Key_Delete))
      t.equal(deleteOpen(), true, "Delete on an app row asks")
      menu.cancel()
      t.equal(deleteOpen(), false, "closing the menu clears the prompt")
      menu.openRoute("apps")
      menu.selectedIndex = rowIndex("apps.gimp")
      menu.cursorActive = true
      menu.handleKey(key(Qt.Key_Delete))
      menu.confirmDelete()
      t.equal(deleteOpen(), false, "confirm closes the prompt")
      t.equal(menu.opened, false, "confirm closes the menu")
      t.equal(JSON.stringify(shell.ran[shell.ran.length - 1]), JSON.stringify(["remove", "gimp", "GIMP"]), "confirm removes the app")
      t.done()
    })
  }
}
