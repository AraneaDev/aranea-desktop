// Behaviour of the menu's bash providers (MenuProviders.qml): output becomes
// action rows (the current value ticked, colliding slugs kept apart), a busy
// provider queues the next menu, a reset drops a stale run, and the Apps
// provider is handed back to the menu.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // rowsReady calls, as [menuId, rows].
  property var ready: []
  // How often the Apps provider was requested.
  property int appsRequests: 0

  QmlTest {
    id: t
  }

  Menu.MenuProviders {
    id: providers
    items: ({
        fonts: {
          id: "fonts",
          provider: "echo"
        },
        slow: {
          id: "slow",
          provider: "slow"
        },
        apps: {
          id: "apps",
          provider: "apps"
        }
      })
    itemOrder: ["fonts", "slow", "apps"]
    specs: ({
        echo: {
          script: "printf 'Fira Code\\tFira Code\\tone\\nFira-Code\\tFira-Code\\tone\\none\\tone\\tone\\n'",
          icon: "F",
          actionFor: function (value) {
            return "pick " + value
          }
        },
        slow: {
          script: "sleep 0.4; printf 'late\\tlate\\t\\n'",
          icon: "S",
          actionFor: function (value) {
            return "slow " + value
          }
        }
      })
    onRowsReady: function (menuId, rows) {
      shell.ready = shell.ready.concat([[menuId, rows]])
    }
    onAppsRequested: shell.appsRequests += 1
  }

  Component.onCompleted: t.step(0, function () {
    providers.load("apps")
    t.equal(shell.appsRequests, 1, "the Apps provider is handed to the menu")
    t.equal(providers.loaded["apps"], true, "and counts as loaded")

    providers.load("slow")
    providers.load("fonts")
    t.equal(JSON.stringify(providers.queue), JSON.stringify(["fonts"]), "a busy provider queues the next menu")
    t.equal(providers.loadingMenus["slow"], true, "the running menu shows as loading")
    t.waitFor(function () {
      return shell.ready.length === 2
    }, 10000, "both providers report", function () {
      t.equal(shell.ready[0][0], "slow", "the running one first")
      var rows = shell.ready[1][1]
      t.equal(shell.ready[1][0], "fonts", "then the queued one")
      t.equal(rows.length, 3, "one row per output line")
      t.equal(rows[0].id, "fonts.fira-code", "rows get slug ids")
      t.equal(rows[1].id, "fonts.fira-code-", "colliding slugs are kept apart")
      t.equal(rows[2].icon, "✓", "the current value is ticked")
      t.equal(rows[0].icon, "F", "others get the provider icon")
      t.equal(rows[0].action, "pick Fira Code", "the action comes from the provider")
      t.equal(providers.loadingMenus["fonts"], undefined, "loading clears")

      providers.reset()
      providers.load("slow")
      providers.reset()
      t.step(1000, function () {
        t.equal(shell.ready.length, 2, "output of a run from before a reset is dropped")
        t.done()
      })
    })
  })
}
