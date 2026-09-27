// Behaviour of the Aranea menu's non-visual entry (Menu.qml) with its window
// switched off, a fake app library and a recorder for commands: a 13th pin
// is refused with a notice, search shows an app once, hints follow the
// state, Ctrl+P pins and Ctrl+1..3 open the tiles, and a Favorites route
// opens once the rows exist.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // Commands the menu tried to run, newest last.
  property var ran: []
  // Apps the fake library lists.
  property var apps: []

  QmlTest {
    id: t
  }

  // Stands in for the host's shared app library.
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
    // Every app, as the library's sorted rows.
    function sortedEntries(query) {
      return shell.apps.map(function (entry) {
        return {
          entry: entry
        }
      })
    }
    // Icons are resolved lazily by the real library; nothing to do here.
    function refreshIcons() {
    }
    // Records an uninstall request.
    function uninstall(id) {
      shell.ran = shell.ran.concat([["uninstall", id]])
    }
    // Records a launch.
    function launch(id, label) {
      shell.ran = shell.ran.concat([["launch", id]])
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
    run: function (command) {
      shell.ran = shell.ran.concat([command])
    }
  }

  // A fake key event.
  function key(code, modifiers) {
    return {
      key: code,
      modifiers: modifiers || Qt.NoModifier,
      text: "",
      accepted: false
    }
  }

  // Display rows whose appId is ID.
  function rowsFor(id) {
    var out = []
    for (var i = 0; i < menu.displayModel.count; i++)
      if (menu.displayModel.get(i).appId === id)
        out.push(menu.displayModel.get(i))
    return out
  }

  Component.onCompleted: {
    var list = []
    for (var i = 0; i < 14; i++)
      list.push({
        id: "app" + i,
        name: "App " + i
      })
    list.push({
      id: "firefox",
      name: "Firefox"
    })
    shell.apps = list
    menu.openRoute("apps.favorites")
    t.step(800, function () {
      t.check(menu.rowsLoaded, "menu sources loaded")
      t.check(menu.opened, "Favorites route opened once rows existed")
      t.equal(menu.activeMenu, "apps.favorites", "the Favorites list is shown")

      // Twelve pins, then the thirteenth is refused with a notice.
      for (var p = 0; p < 12; p++)
        menu.toggleFavoriteApp("app" + p)
      t.equal(menu.favoriteAppIds.length, 12, "twelve pinned")
      menu.toggleFavoriteApp("app12")
      t.equal(menu.favoriteAppIds.length, 12, "thirteenth pin refused")
      t.equal(menu.notice, "12 FAVOURITES · UNPIN ONE FIRST", "refusal notice")
      menu.notice = ""

      // Pinned and recent: search still shows the app once.
      menu.toggleFavoriteApp("app0")
      menu.toggleFavoriteApp("firefox")
      t.check(menu.favoriteAppIds.indexOf("firefox") >= 0, "unpinning one makes room for another")
      menu.recordRecentApp("firefox")
      menu.openRoute("root")
      menu.setFilter("fire")
      t.equal(rowsFor("firefox").length, 1, "search shows Firefox once")
      t.equal(menu.hint, "ESC CLEAR  ·  ENTER OPEN", "hint while searching")
      menu.setFilter("")
      t.equal(menu.hint, "SYSTEM // READY", "hint on the root")

      // Ctrl+P on an app row pins or unpins it (app1 is pinned: it unpins).
      menu.openRoute("apps")
      var appIndex = -1
      for (var r = 0; r < menu.displayModel.count; r++)
        if (menu.displayModel.get(r).itemId === "apps.app1")
          appIndex = r
      menu.selectedIndex = appIndex
      menu.cursorActive = true
      t.check(menu.hint.indexOf("^P PIN") >= 0, "hint offers pinning on an app row")
      menu.handleKey(key(Qt.Key_P, Qt.ControlModifier))
      t.check(menu.favoriteAppIds.indexOf("app1") < 0, "Ctrl+P unpins the cursor app")

      // Ctrl+2 opens a terminal; Ctrl+3 opens Setup.
      menu.openRoute("root")
      menu.handleKey(key(Qt.Key_2, Qt.ControlModifier))
      t.check(shell.ran.indexOf("xdg-terminal-exec") >= 0, "Ctrl+2 opens a terminal")
      menu.openRoute("root")
      menu.handleKey(key(Qt.Key_3, Qt.ControlModifier))
      t.equal(menu.activeMenu, "setup", "Ctrl+3 opens Setup")
      t.done()
    })
  }
}
