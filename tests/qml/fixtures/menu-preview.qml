// Inert preview of the production menu entry and card. No live desktop reads.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: harness
  // Capture variant supplied by the isolated renderer.
  readonly property string fixture: Quickshell.env("ARANEA_MENU_RENDER_FIXTURE")
  // Prevent repeated fixture initialization while the sources settle.
  property bool prepared: false
  // Allows the theme and fonts to settle before the card is grabbed.
  property int polls: 0
  // Report a process or render failure to the renderer.
  function finish(ok, message) {
    console.log((ok ? "MENURENDER OK " : "MENURENDER FAIL ") + message)
    Qt.quit()
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
      return [
        {
          entry: {
            id: "browser",
            name: "Project Browser"
          }
        }
      ]
    }
    function refreshIcons() {
    }
    function iconSource(icon) {
      return ""
    }
    function launch(id, label) {
      harness.finish(false, "unexpected launch")
    }
  }
  QtObject {
    id: scoped
    property var appLibrary: library
  }
  Menu.Menu {
    id: entry
    windowEnabled: false
    shell: scoped
    defaultMenuPath: Quickshell.env("ARANEA_MENU_RENDER_ROOT") + "/tests/qml/fixtures/omarchy-menu.jsonc"
    run: function (command) {
      harness.finish(false, "unexpected command")
    }
  }
  FloatingWindow {
    implicitWidth: 520
    implicitHeight: 510
    color: "transparent"
    visible: true
    Menu.MenuSurface {
      id: surface
      width: entry.cardWidth
      height: entry.cardHeight
      anchors.centerIn: parent
      root: entry
    }
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    entry.desktopSearch.compositor = null
    entry.desktopSearch.runner = function (argv) {
      return false
    }
    entry.openRoute("root")
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (!entry.rowsLoaded || !entry.opened)
        return
      if (!harness.prepared) {
        harness.prepared = true
        var source = entry.desktopSearch
        source.settingsAvailable = true
        if (harness.fixture !== "no-compositor") {
          source.fixtureWindows = [
            {
              address: "0xabc",
              title: "Project notes \u2014 Browser",
              workspace: {
                id: 2
              }
            }
          ]
          source.fixtureWorkspaces = [
            {
              id: 2,
              name: "Project Development",
              windows: 3
            }
          ]
          source.fixtureFocusedWorkspaceId = 2
        }
        var items = Object.assign({}, entry.items)
        items["setup.project"] = {
          id: "setup.project",
          parent: "setup",
          kind: "action",
          label: "Project controls",
          description: "Open project controls",
          action: "inert"
        }
        entry.items = items
        entry.itemOrder = entry.itemOrder.concat(["setup.project"])
        source.refreshNow()
        entry.setFilter(harness.fixture === "no-match" ? "zzzz no matches" : "p")
        if (harness.fixture === "vanished") {
          entry.setFilter("window: Project")
          source.fixtureWindows = []
          entry.handleKey({
            key: Qt.Key_Return,
            modifiers: Qt.NoModifier,
            text: "",
            accepted: false
          })
        }
        return
      }
      if (++harness.polls < 10)
        return
      stop()
      if (!surface.grabToImage(function (result) {
        harness.finish(result.saveToFile(Quickshell.env("ARANEA_MENU_RENDER_OUTPUT")), result.image.width + "x" + result.image.height)
      }, Qt.size(surface.width, surface.height)))
        harness.finish(false, "grab refused")
    }
  }
}
