// Unified results preserve real guard decoration, visibility and link semantics.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  // Actions requested by the existing menu action handler.
  property var ran: []
  QmlTest {
    id: t
  }
  Menu.Menu {
    id: menu
    windowEnabled: false
    defaultMenuPath: Qt.resolvedUrl("fixtures/desktop-search-menu.jsonc").toString().replace("file://", "")
    run: function (command) {
      host.ran = host.ran.concat([command])
    }
  }
  Component.onCompleted: {
    menu.openRoute("root")
    t.waitFor(function () {
      return menu.rowsLoaded && menu.desktopSearch.whenResults["setup.hidden"] === false
    }, 10000, "real guard batch finishes", function () {
      menu.setFilter("command: control")
      t.equal(menu.displayModel.count, 1, "global search excludes hidden guarded command")
      t.equal(menu.displayModel.get(0).desktopKey, "command:setup.checked", "visible guarded result retains typed identity")
      t.equal(menu.displayModel.get(0).label, "Checked control ✓", "global command keeps existing checked decoration")
      menu.handleKey({
        key: Qt.Key_Return,
        modifiers: Qt.NoModifier,
        text: "",
        accepted: false
      })
      t.equal(host.ran, ["fixture-checked"], "guarded command retains its exact action")
      menu.openRoute("root")
      menu.setFilter("command: shortcut")
      menu.handleKey({
        key: Qt.Key_Return,
        modifiers: Qt.NoModifier,
        text: "",
        accepted: false
      })
      t.check(menu.opened && menu.activeMenu === "setup", "global link redirects and remains open")
      menu.openRoute("custom-route")
      t.equal(menu.activeMenu, "setup", "custom alias route preserves existing link semantics")
      t.done()
    })
  }
}
