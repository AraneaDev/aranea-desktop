// Real Menu integration: root ranking, typed dispatch, scoped policy and race safety.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  // Existing launch/action and typed argv requests observed by the fixture.
  property var ran: []
  // Current application library entries used by the real menu.
  property var apps: [
    {
      id: "browser",
      name: "Project Browser"
    },
    {
      id: "other",
      name: "Project Other"
    }
  ]
  // Captured generation completions for query and close races.
  property var pending: []
  QmlTest {
    id: t
  }
  QtObject {
    id: library
    signal appsChanged
    function entryName(entry) {
      return entry.name
    }
    function entrySubtext(entry) {
      return "Launch application"
    }
    function sortedEntries(query) {
      return host.apps.map(function (entry) {
        return {
          entry: entry
        }
      })
    }
    function refreshIcons() {
    }
    function launch(id, label) {
      host.ran = host.ran.concat([["app", id]])
    }
  }
  QtObject {
    id: scoped
    property var appLibrary: library
  }
  Menu.Menu {
    id: menu
    windowEnabled: false
    shell: scoped
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
    run: function (command) {
      host.ran = host.ran.concat([command])
    }
  }
  FloatingWindow {
    implicitWidth: 520
    implicitHeight: 720
    visible: true
    Menu.MenuSurface {
      id: surface
      width: menu.cardWidth
      height: menu.cardHeight
      root: menu
    }
  }
  // Creates a keyboard event handled by the production menu.
  function key(code) {
    return {
      key: code,
      modifiers: Qt.NoModifier,
      text: "",
      accepted: false
    }
  }
  // Finds a displayed canonical desktop identity independently of its rank.
  function find(key) {
    for (var i = 0; i < menu.displayModel.count; i++)
      if (menu.displayModel.get(i).desktopKey === key)
        return i
    return -1
  }
  Component.onCompleted: {
    menu.openRoute("root")
    t.waitFor(function () {
      return menu.rowsLoaded && menu.opened
    }, 10000, "real menu opens", function () {
      menu.setFilter("window: Project")
      t.check(menu.displayModel.count === 0, "window prefix does not match ordinary command or app rows")
      if (!menu.desktopSearch) {
        t.check(menu.displayModel.count > 0, "root search includes live window results")
        t.done()
        return
      }
      var source = menu.desktopSearch
      source.compositor = null
      source.fixtureWindows = [
        {
          address: "0xabc",
          title: "Project <b>Window</b>",
          workspace: {
            id: 2
          }
        }
      ]
      source.fixtureWorkspaces = [
        {
          id: 2,
          name: "Project Development",
          windows: 1
        }
      ]
      source.settingsAvailable = true
      source.fixtureFocusedWorkspaceId = 2
      source.runner = function (argv) {
        host.ran = host.ran.concat([argv])
        return true
      }
      source.refreshNow()
      t.equal(menu.displayModel.count, 1, "root window prefix finds live window")

      t.equal(menu.displayModel.get(0).label, "Project <b>Window</b>", "untrusted display text remains literal data")
      t.check(menu.displayModel.get(0).icon.length > 0, "window result has a type icon without a desktop app icon")
      menu.setFilter("workspace: Project")
      t.equal(menu.displayModel.get(0).desktopKey, "workspace:2", "workspace prefix finds typed workspace")
      t.check(menu.displayModel.get(0).icon.length > 0, "workspace result reserves a recognizable icon")
      menu.setFilter("setting: scale")
      t.equal(menu.displayModel.get(0).desktopKey, "setting:display", "settings aliases find section destinations")
      t.check(menu.displayModel.get(0).icon.length > 0, "settings result has a type icon")
      menu.setFilter("command: power")
      t.equal(menu.displayModel.get(0).desktopKey, "command:setup.power", "command prefix finds existing item")
      menu.handleKey(key(Qt.Key_Return))
      t.equal(host.ran[0], "omarchy-launch-power", "command activation uses existing action")
      t.check(!menu.opened, "leaf command closes through existing handler")
      menu.openRoute("root")
      menu.setFilter("command: setup")
      menu.handleKey(key(Qt.Key_Return))
      t.equal(menu.activeMenu, "setup", "command menu navigates through existing handler")
      t.check(menu.opened, "command menu destination stays open")
      menu.setFilter("power")
      t.check(!menu.displayModel.get(0).desktopKey, "submenu query retains scoped rows")
      menu.searchEverywhere()
      t.equal(menu.filterText, "power", "Search everywhere preserves query")
      t.equal(menu.activeMenu, "root", "Search everywhere returns to root")
      t.equal(menu.displayModel.get(0).resultType, "command", "global result has controlled type badge")
      source.refreshNow()
      menu.setFilter("Project")
      t.equal(menu.displayModel.count, 4, "mixed app window workspace results share existing model")
      menu.selectedIndex = find("window:0xabc")
      menu.cursorActive = true
      var selected = menu.selectedIndex
      host.apps = [
        {
          id: "aaa",
          name: "Project AAA"
        }
      ].concat(host.apps.slice().reverse())
      library.appsChanged()
      t.equal(menu.displayModel.get(menu.selectedIndex).desktopKey, "window:0xabc", "app reorder preserves selected window identity")
      menu.applyProviderRows("setup", [
        {
          id: "setup.project",
          kind: "action",
          label: "Project Action",
          action: "fixture-action"
        }
      ])
      t.equal(menu.displayModel.get(menu.selectedIndex).desktopKey, "window:0xabc", "provider completion preserves selected identity")
      t.check(!menu.activateKey(find("app:browser"), "window:0xabc"), "pointer cannot activate another row after reorder")
      source.fixtureWindows = []
      host.ran = []
      menu.handleKey(key(Qt.Key_Return))
      t.equal(host.ran.length, 0, "fresh activation refuses window before refresh")
      t.equal(menu.notice, "Window is no longer open", "vanished target reports notice")
      t.check(menu.opened, "vanished window keeps menu open")
      source.refreshNow()
      t.check(!menu.cursorActive && menu.selectedIndex === -1, "disappeared selected identity clears cursor")
      menu.handleKey(key(Qt.Key_Return))
      menu.handleKey(key(Qt.Key_Return))
      t.equal(host.ran.length, 0, "Enter cannot transfer cleared target to a different row")
      menu.setFilter("app: Project Browser")
      t.equal(menu.selectedIndex, 0, "query edit resets highest ranked selection")
      menu.handleKey(key(Qt.Key_Return))
      t.equal(host.ran[0], ["app", "browser"], "type then Enter launches current app")
      t.equal(menu.appHistory.recentAppIds[0], "browser", "existing app history records launch")
      menu.openRoute("root")
      source.refreshNow()
      menu.setFilter("workspace: Project")
      menu.handleKey(key(Qt.Key_Return))
      t.equal(host.ran[1], ["hyprctl", "dispatch", 'hl.dsp.focus({ workspace = "2" })'], "typed workspace uses argv dispatch")
      t.check(!menu.opened, "accepted argv closes menu")
      menu.openRoute("root")
      menu.setFilter("setting: scale")
      source.runner = function (argv) {
        return false
      }
      menu.handleKey(key(Qt.Key_Return))
      t.check(menu.opened && menu.notice === "Could not open target", "dispatch refusal retains menu with notice")
      var many = []
      for (var n = 0; n < 60; n++)
        many.push({
          id: "bulk" + n,
          name: "Bulk " + n
        })
      host.apps = many
      library.appsChanged()
      menu.notice = ""
      menu.setFilter("app: Bulk")
      t.equal(menu.displayModel.count, 50, "global display caps results at fifty")
      t.check(menu.hint.indexOf("Refine your search") >= 0, "cap offers refinement hint")
      source.refreshReader = function (generation, complete) {
        host.pending = host.pending.concat([
          {
            generation: generation,
            complete: complete
          }
        ])
      }
      source.refreshNow()
      menu.setFilter("app: Bulk 12")
      var pending = host.pending[0]
      pending.complete(pending.generation, {
        compositorAvailable: true,
        windows: [
          {
            address: "0xdef",
            title: "Bulk 12"
          }
        ],
        workspaces: []
      })
      t.equal(menu.displayModel.get(menu.selectedIndex).desktopKey, "app:bulk12", "async source completion after typing preserves current query target")
      source.refreshNow()
      var late = host.pending[1]
      menu.cancel()
      late.complete(late.generation, {
        compositorAvailable: true,
        windows: [
          {
            address: "0xaaa",
            title: "Bulk"
          }
        ],
        workspaces: []
      })
      t.check(!source.records.some(function (r) {
        return r.key === "window:0xaaa"
      }), "late completion after close cannot restore a row")
      source.refreshReader = null
      source.fixtureWindows = null
      source.fixtureWorkspaces = null
      menu.openRoute("root")
      source.refreshNow()
      menu.setFilter("Bulk")
      t.check(menu.displayModel.count === 50 && !source.available, "no compositor preserves usable application results")
      menu.setFilter("")
      t.check(menu.fullRootHeader && find("workspace:2") === -1, "empty root retains existing tiles and rows")
      menu.open(JSON.stringify({
        mode: "select",
        options: ["window: Project", "Plain"]
      }))
      menu.setFilter("window: Project")
      t.equal(menu.displayModel.count, 1, "dmenu does not parse desktop prefixes")
      t.check(!source.active && !source.subscribed, "dmenu bypasses live search sources")
      menu.open(JSON.stringify({
        mode: "input",
        prompt: "Value"
      }))
      menu.setFilter("setting: scale")
      t.equal(menu.displayModel.count, 0, "input remains literal answer with no results")
      host.apps = [
        {
          id: "browser",
          name: "Project Browser"
        }
      ]
      library.appsChanged()
      menu.openRoute("root")
      source.fixtureWindows = [
        {
          address: "0xabc",
          title: "Project <b>Window</b>",
          workspace: {
            id: 2
          }
        }
      ]
      source.fixtureWorkspaces = [
        {
          id: 2,
          name: "Project Development",
          windows: 1
        }
      ]
      source.refreshNow()
      menu.setFilter("p")
      t.waitFor(function () {
        return t.findChild(surface, "menuResults").list.itemAtIndex(4) !== null
      }, 2000, "production result delegates appear", function () {
        var list = t.findChild(surface, "menuResults").list
        var seen = []
        for (var i = 0; i < menu.displayModel.count; i++) {
          var row = list.itemAtIndex(i)
          if (row) {
            var badge = t.findChild(row, "typeBadge")
            if (badge.visible && seen.indexOf(badge.text) < 0)
              seen.push(badge.text)
          }
        }
        t.equal(seen.sort(), ["App", "Command", "Setting", "Window", "Workspace"], "production card renders all five controlled type badges")
        var windowRow = list.itemAtIndex(find("window:0xabc"))
        t.equal(t.findChild(windowRow, "rowLabel").text, "Project <b>Window</b>", "hostile window markup is displayed literally")
        t.equal(t.findChild(windowRow, "rowLabel").textFormat, Text.PlainText, "window label cannot interpret rich text")
        t.check(surface.borderSpecOverride === menu.style.borderSpec && surface.cornerRadius === menu.style.cornerRadius, "production surface retains host frame and radius")
        t.done()
      })
    })
  }
}
