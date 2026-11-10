// Behaviour of the menu's JSONC sources (MenuSources.qml): both files report
// (a missing user file counts), the merge carries the default file's items,
// and reload() reads them again.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // How often the sources reported a change.
  property int updates: 0
  // Completed reads of the shipped menu FileView.
  property int defaultLoads: 0
  // Completed reads of the extension FileView.
  property int userLoads: 0
  // Production default reader observed by the test Connections.
  property var defaultView: null
  // Production extension reader observed by the test Connections.
  property var userView: null
  Connections {
    target: shell.defaultView
    function onLoaded() {
      shell.defaultLoads += 1
    }
  }
  Connections {
    target: shell.userView
    function onLoaded() {
      shell.userLoads += 1
    }
  }
  // Private scratch directory supplied by the test sandbox.
  readonly property string scratch: Quickshell.env("TMPDIR")
  // Continuation for the one outstanding scratch-file write.
  property var afterWrite: null

  Process {
    id: writer
    onExited: function (code) {
      t.equal(code, 0, "scratch menu files are written")
      var next = shell.afterWrite
      shell.afterWrite = null
      next()
    }
  }

  // Writes both source files before running the next read assertions.
  function writeMenus(defaultRaw, userRaw, next) {
    shell.afterWrite = next
    writer.command = ["bash", "-c", 'printf "%s" "$2" > "$1"; printf "%s" "$4" > "$3"', "menu-fixture", shell.scratch + "/default.jsonc", defaultRaw, shell.scratch + "/user.jsonc", userRaw]
    writer.running = true
  }

  // Wait on each production FileView, so unrelated manifest updates cannot
  // make a partial-read check pass before the menu files have been read.
  function menuFile(owner, path) {
    var children = t.childrenOf(owner)
    for (var i = 0; i < children.length; i++)
      if (children[i].path === path)
        return children[i]
    throw new Error("menu FileView not found: " + path)
  }

  // Reloads both source files and waits for each specific reader to finish.
  function readMenus(next) {
    var defaults = shell.defaultLoads
    var users = shell.userLoads
    sources.reload()
    t.waitFor(function () {
      return shell.defaultLoads > defaults && shell.userLoads > users
    }, 10000, "both scratch menu sources reload", next)
  }

  Component {
    id: menuComponent
    Menu.Menu {
      windowEnabled: false
    }
  }

  // A complete source becomes available after startup without a watcher event.
  function checkStartupRetry() {
    writeMenus('{"startup":', "", function () {
      var menu = menuComponent.createObject(shell, {
        defaultMenuPath: shell.scratch + "/default.jsonc"
      })
      var source
      var children = t.childrenOf(menu)
      for (var i = 0; i < children.length; i++)
        if (children[i].defaultMenuItems !== undefined)
          source = children[i]
      // Hold the external watcher steady: recovery must come from open().
      menuFile(source, source.defaultMenuPath).watchChanges = false
      t.waitFor(function () {
        return source.ready
      }, 10000, "startup partial source settles", function () {
        t.equal(source.defaultMenuItems.length, 0, "startup partial read has no default rows")
        writeMenus('{"startup":{"label":"Recovered"}}', "", function () {
          menu.open("{}")
          t.waitFor(function () {
            return !!menu.items.startup
          }, 10000, "opening retries a startup partial read", function () {
            t.equal(menu.items.startup.label, "Recovered", "open accepts the now-complete shipped menu")
            menu.destroy()
            t.done()
          })
        })
      })
    })
  }

  // Files move through complete, truncated, empty, and complete replacements.
  function checkPartialReads() {
    writeMenus('{"old":{"label":"Original"}}', '{"custom":{"label":"User"}}', function () {
      sources.defaultMenuPath = shell.scratch + "/default.jsonc"
      sources.userMenuPath = shell.scratch + "/user.jsonc"
      shell.defaultView = menuFile(sources, sources.defaultMenuPath)
      shell.userView = menuFile(sources, sources.userMenuPath)
      readMenus(function () {
        t.equal(sources.merge().items.old.label, "Original", "valid scratch default is loaded")
        t.equal(sources.merge().items.custom.label, "User", "valid scratch extension is loaded")
        writeMenus('{"replacement":', '{"custom":', function () {
          readMenus(function () {
            t.check(!!sources.merge().items.old, "truncated default retains previous rows")
            t.check(!!sources.merge().items.custom, "truncated extension retains previous rows")
            writeMenus("", "// user cleared extensions", function () {
              readMenus(function () {
                t.check(!!sources.merge().items.old, "empty shipped menu retains previous rows")
                t.check(!sources.merge().items.custom, "comment-only user file clears extensions")
                writeMenus('{"replacement":{"label":"Complete"}}', '{"newUser":{"label":"New user"}}', function () {
                  readMenus(function () {
                    t.check(!sources.merge().items.old, "complete default replaces previous rows")
                    t.equal(sources.merge().items.replacement.label, "Complete", "complete replacement default is accepted")
                    t.check(!!sources.merge().items.newUser, "complete replacement extension is accepted")
                    sources.userMenuPath = "/nonexistent/aranea-test/removed-menu.jsonc"
                    t.waitFor(function () {
                      return sources.userMenuItems.length === 0
                    }, 10000, "missing user extension clears its previous rows", checkStartupRetry)
                  })
                })
              })
            })
          })
        })
      })
    })
  }

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
      t.equal(merged.items["aranea.settings"].parent, "root", "installed settings route belongs in the command center")
      t.equal(merged.items["aranea.settings"].label, "Settings", "command center uses the concise Settings label")
      sources.settingsManifestPath = "/nonexistent/aranea-test/settings/manifest.json"
      var before = shell.updates
      sources.reload()
      t.waitFor(function () {
        return shell.updates > before && !sources.settingsAvailable
      }, 10000, "reload reads the files again", function () {
        t.check(!sources.merge().items["aranea.settings"], "missing settings manifest removes only its generated route")
        checkPartialReads()
      })
    })
  }
}
