// Behaviour of the menu's bash providers (MenuProviders.qml): output becomes
// action rows (the current value ticked, colliding slugs kept apart), a busy
// provider queues the next menu, a reset drops a stale run, and the Apps
// provider is handed back to the menu.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: fixture

  // rowsReady calls, as [menuId, rows].
  property var ready: []
  // How often the Apps provider was requested.
  property int appsRequests: 0
  // Private scratch directory for command files and captured argv.
  readonly property string scratch: Quickshell.env("TMPDIR")
  // Continuation for the one outstanding external command.
  property var afterCommand: null
  // Real menu instance loaded from the selected host menu definition.
  property var commandMenu: null

  // The real provider and menu action run bash against private command files.
  // BASH_ENV preserves that boundary even in the production login shell.
  Process {
    id: command
    environment: ({
        BASH_ENV: fixture.scratch + "/menu-command-env"
      })
    onExited: function (code) {
      t.equal(code, 0, "fixture command succeeds")
      var next = fixture.afterCommand
      fixture.afterCommand = null
      next()
    }
  }

  FileView {
    id: captured
    path: fixture.scratch + "/kernel-argv"
    blockLoading: true
    printErrors: false
  }

  Component {
    id: menuComponent
    Menu.Menu {
      windowEnabled: false
      run: function (action) {
        fixture.runCommand(["bash", "-lc", action], function () {
          captured.reload()
          t.equal(captured.text(), "set\nlinux\n", "selecting linux passes exactly set linux to omarchy-kernel")
          fixture.checkFreshKernels()
        })
      }
    }
  }

  // Executes a command through the private fixture environment.
  function runCommand(argv, next) {
    fixture.afterCommand = next
    command.command = argv
    command.running = true
  }

  // Redirects command lookup while retaining production Process commands.
  function scopeCommands(owner) {
    var children = t.childrenOf(owner)
    for (var i = 0; i < children.length; i++) {
      var child = children[i]
      if (child.command !== undefined && child.environment !== undefined)
        child.environment = ({
            BASH_ENV: fixture.scratch + "/menu-command-env"
          })
      scopeCommands(child)
    }
  }

  // Finds a visible menu row by its stable item id.
  function rowIndex(id) {
    for (var i = 0; i < fixture.commandMenu.displayModel.count; i++)
      if (fixture.commandMenu.displayModel.get(i).itemId === id)
        return i
    return -1
  }

  // Reopening the kernel menu must replace cached rows with a fresh list.
  function checkFreshKernels() {
    runCommand(["bash", "-c", 'printf "%s\\n" linux-zen linux-lts > "$1/kernel-list"', "fixture", fixture.scratch], function () {
      fixture.commandMenu.open(JSON.stringify({
        menu: "update.kernel"
      }))
      t.waitFor(function () {
        return rowIndex("update.kernel.linux-zen") >= 0
      }, 10000, "second kernel visit enumerates again", function () {
        t.equal(rowIndex("update.kernel.linux"), -1, "fresh enumeration removes the old kernel")
        t.equal(fixture.commandMenu.displayModel.count, 2, "second visit keeps both new kernel rows")
        fixture.commandMenu.destroy()
        t.done()
      })
    })
  }

  // Exercises shipped Appearance and Kernel routes with fake command I/O.
  function checkShippedProviders() {
    var kernelScript = '#!/bin/bash\ncase "$1" in\nget) printf "%s\\n" linux-lts ;;\nlist) cat "' + fixture.scratch + '/kernel-list" ;;\nset) printf "%s\\n" "$@" > "' + fixture.scratch + '/kernel-argv" ;;\n*) exit 64 ;;\nesac\n';
    var fontScript = '#!/bin/bash\ncase "${0##*/}" in\nomarchy-font-current) printf "%s\\n" "Fira Code" ;;\nomarchy-font-list) printf "%s\\n" "Fira Code" "Iosevka" ;;\n*) exit 64 ;;\nesac\n'
    runCommand(["bash", "-c", 'mkdir -p "$1/menu-bin"; printf "%s" "$2" > "$1/menu-bin/omarchy-kernel"; printf "%s" "$3" > "$1/menu-bin/omarchy-font-current"; cp "$1/menu-bin/omarchy-font-current" "$1/menu-bin/omarchy-font-list"; chmod +x "$1"/menu-bin/*; printf "%s" "$4" > "$1/menu-command-env"; printf "%s\\n" linux linux-lts > "$1/kernel-list"', "fixture", fixture.scratch, kernelScript, fontScript, 'export PATH="' + fixture.scratch + '/menu-bin:$PATH"\n'], function () {
      // Default path is the selected host's actual shipped JSONC, not our
      // small shared fixture: acceptance follows the target menu contract.
      fixture.commandMenu = menuComponent.createObject(fixture)
      scopeCommands(fixture.commandMenu)
      t.waitFor(function () {
        return fixture.commandMenu.menuSourcesReady
      }, 10000, "target shipped menu loads", function () {
        var roots = fixture.commandMenu.itemOrder.filter(function (id) {
          return fixture.commandMenu.items[id].parent === "root" && id !== "aranea.projects"
        })
        t.equal(roots.join(","), "apps,trigger,software,settings,learn,system", "shipped command center retains the consolidated root groups")
        t.equal(fixture.commandMenu.items.appearance.parent, "settings", "shipped Appearance belongs under Settings")
        t.equal(fixture.commandMenu.items.setup.parent, "settings", "shipped Devices belongs under Settings")
        t.equal(fixture.commandMenu.items.install.parent, "software", "shipped Install belongs under Software")
        t.equal(fixture.commandMenu.items.trigger.label, "Actions", "shipped Trigger retains the Actions label")
        t.equal(fixture.commandMenu.items.learn.label, "Help", "shipped Learn retains the Help label")
        fixture.commandMenu.open(JSON.stringify({
          menu: "appearance"
        }))
        t.equal(fixture.commandMenu.activeMenu, "appearance", "shipped Appearance route opens")
        t.check(rowIndex("appearance.font") >= 0, "shipped Appearance exposes its Font provider")
        fixture.commandMenu.activateIndex(rowIndex("appearance.font"))
        t.waitFor(function () {
          return rowIndex("appearance.font.fira-code") >= 0
        }, 10000, "shipped Appearance font provider is populated", function () {
          t.equal(fixture.commandMenu.displayModel.count, 2, "fonts enumerate through the production provider")
          t.equal(fixture.commandMenu.cardWidth, Math.min(Style.space(560), fixture.commandMenu.screenWidth - Style.gapsOut * 2), "shipped font picker retains its wider card layout")
          fixture.commandMenu.open(JSON.stringify({
            menu: "update"
          }))
          t.waitFor(function () {
            return rowIndex("update.kernel") >= 0
          }, 10000, "shipped Kernel route is visible with multiple kernels", function () {
            fixture.commandMenu.activateIndex(rowIndex("update.kernel"))
            t.equal(fixture.commandMenu.activeMenu, "update.kernel", "shipped Update Kernel route opens")
            t.waitFor(function () {
              return rowIndex("update.kernel.linux") >= 0
            }, 10000, "kernel provider enumerates the installed kernels", function () {
              t.equal(fixture.commandMenu.displayModel.count, 2, "both installed kernels are offered")
              t.equal(fixture.commandMenu.displayModel.get(rowIndex("update.kernel.linux-lts")).icon, "✓", "current kernel is checked")
              t.equal(fixture.commandMenu.displayModel.get(rowIndex("update.kernel.linux")).icon, String.fromCodePoint(0xf17c), "other kernel uses the Linux icon")
              fixture.commandMenu.activateIndex(rowIndex("update.kernel.linux"))
            })
          })
        })
      })
    })
  }

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
      fixture.ready = fixture.ready.concat([[menuId, rows]])
    }
    onAppsRequested: fixture.appsRequests += 1
  }

  Component.onCompleted: t.step(0, function () {
    providers.load("apps")
    t.equal(fixture.appsRequests, 1, "the Apps provider is handed to the menu")
    t.equal(providers.loaded["apps"], true, "and counts as loaded")

    providers.load("slow")
    providers.load("fonts")
    t.equal(JSON.stringify(providers.queue), JSON.stringify(["fonts"]), "a busy provider queues the next menu")
    t.equal(providers.loadingMenus["slow"], true, "the running menu shows as loading")
    t.waitFor(function () {
      return fixture.ready.length === 2
    }, 10000, "both providers report", function () {
      t.equal(fixture.ready[0][0], "slow", "the running one first")
      var rows = fixture.ready[1][1]
      t.equal(fixture.ready[1][0], "fonts", "then the queued one")
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
        t.equal(fixture.ready.length, 2, "output of a run from before a reset is dropped")
        checkShippedProviders()
      })
    })
  })
}
