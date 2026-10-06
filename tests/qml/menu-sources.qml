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
    settingsManifestPath: Qt.resolvedUrl("plugins/araneadev.settings/manifest.json").toString().replace("file://", "")
    onUpdated: shell.updates += 1
  }

  Component.onCompleted: {
    var component = Qt.createComponent("plugins/araneadev.menu/MenuSources.qml")
    var pending = component.createObject(shell, {
      defaultMenuSeen: true,
      userMenuSeen: true,
      settingsManifestPath: "/nonexistent/settings/manifest.json"
    })
    t.check(!pending.ready, "route resolution waits for optional settings manifest to report")
    pending.destroy()

    t.waitFor(function () {
      return sources.ready && sources.settingsAvailable
    }, 10000, "both files report", function () {
      var merged = sources.merge()
      t.check(merged.itemOrder.indexOf("system.lock") >= 0, "the default file's items merge")
      t.equal(merged.items["setup"].label, "Setup", "with their labels")
      t.check(shell.updates >= 2, "each file reported once")
      t.equal(merged.items["aranea.settings"].parent, "setup", "installed settings route belongs under Setup")
      sources.settingsManifestPath = "/nonexistent/aranea-test/settings/manifest.json"
      var before = shell.updates
      sources.reload()
      t.waitFor(function () {
        return shell.updates > before && !sources.settingsAvailable
      }, 10000, "reload reads the files again", function () {
        t.check(!sources.merge().items["aranea.settings"], "missing settings manifest removes only its generated route")
        t.done()
      })
    })
  }
}
