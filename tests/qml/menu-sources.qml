// Behaviour of the menu's JSONC sources (MenuSources.qml): both files report
// (a missing user file counts), the merge carries the default file's items,
// and reload() reads them again.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // How often the sources reported a change.
  property int updates: 0

  QmlTest {
    id: t
  }

  Menu.MenuSources {
    id: sources
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
    userMenuPath: "/nonexistent/aranea-test/omarchy-menu.jsonc"
    onUpdated: shell.updates += 1
  }

  Component.onCompleted: {
    t.waitFor(function () {
      return sources.ready
    }, 10000, "both files report", function () {
      var merged = sources.merge()
      t.check(merged.itemOrder.indexOf("system.lock") >= 0, "the default file's items merge")
      t.equal(merged.items["setup"].label, "Setup", "with their labels")
      t.check(shell.updates >= 2, "each file reported once")
      var before = shell.updates
      sources.reload()
      t.waitFor(function () {
        return shell.updates > before
      }, 10000, "reload reads the files again", function () {
        t.done()
      })
    })
  }
}
