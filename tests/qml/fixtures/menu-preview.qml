// Inert preview of the production menu entry and card. No live desktop reads.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.menu" as Menu
import "ProjectPreview.js" as ProjectPreview

ShellRoot {
  id: harness
  // Capture variant supplied by the isolated renderer.
  readonly property string fixture: Quickshell.env("ARANEA_MENU_RENDER_FIXTURE")
  // Prevent repeated fixture initialization while the sources settle.
  property bool prepared: false
  // Allows the theme and fonts to settle before the card is grabbed.
  property int polls: 0
  // Logical screen boundary for compact and scaled visual comparisons.
  property int logicalWidth: Math.max(240, Number(Quickshell.env("ARANEA_MENU_RENDER_WIDTH") || 1920))
  // Logical screen height, independent of the offscreen window's size.
  property int logicalHeight: Math.max(240, Number(Quickshell.env("ARANEA_MENU_RENDER_HEIGHT") || 1080))
  // Report a process or render failure to the renderer.
  function finish(ok, message) {
    console.log((ok ? "MENURENDER OK " : "MENURENDER FAIL ") + message)
    Qt.quit()
  }
  QtObject {
    id: previewScreen
    property int width: harness.logicalWidth
    property int height: harness.logicalHeight
  }
  QtObject {
    id: previewView
    property var screen: previewScreen
    property int width: harness.logicalWidth
    property int height: harness.logicalHeight
    property int cardTop: -1
    property int maxRowsHeight: -1
    function focusKeys() {
    }
    function freezeCardTop() {
    }
    function revealCursor() {
    }
    function disarmPointer() {
    }
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
    entry.view = previewView
    if (Quickshell.env("ARANEA_MENU_RENDER_FONT"))
      entry.style.fontFamily = Quickshell.env("ARANEA_MENU_RENDER_FONT")
    entry.desktopActions.wallpaper.runner = function (argv, done) {
      harness.finish(false, "unexpected wallpaper owner call")
    }
    entry.projectClient.runner = function (argv, done) {
      harness.finish(false, "unexpected project owner process")
    }
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
        var fontScale = Math.max(0.75, Number(Quickshell.env("ARANEA_MENU_RENDER_FONT_SCALE") || 1))
        if (fontScale !== 1) {
          Style.fontBaseSize = Math.round(Style.fontBaseSize * fontScale)
          var fonts = Object.assign({}, Style.fontOverrides)
          Object.keys(fonts).forEach(function (key) {
            fonts[key] = Math.round(Number(fonts[key]) * fontScale)
          })
          Style.fontOverrides = fonts
        }
        if (Quickshell.env("ARANEA_MENU_RENDER_SQUARE") === "1")
          Style.cornerRadius = 0
        if (Quickshell.env("ARANEA_MENU_RENDER_BORDER_WIDTH") === "0")
          entry.style.borderSpec = Border.none()
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
        if (harness.fixture === "project-search") {
          var projects = ProjectPreview.sample("project-search")
          entry.projectClient.snapshot = projects.projectSnapshot
          entry.projectClient.available = true
          source.refreshNow()
          entry.setFilter("project:")
          entry.selectedIndex = 0
          entry.cursorActive = true
        } else if (harness.fixture === "actions" || harness.fixture.indexOf("action-") === 0) {
          var key = "action:audio:7:speaker"
          var snapshot = {
            dnd: {
              available: true,
              enabled: false,
              quietHours: true
            },
            audio: {
              available: true,
              outputs: [
                {
                  key: "7:speaker",
                  label: harness.fixture === "action-long-label" ? "USB Studio Monitor Interface With A Very Long Descriptive Device Name" : "Studio Speakers",
                  current: false
                },
                {
                  key: "8:headset",
                  label: "Headphones",
                  current: true
                }
              ]
            },
            wallpaper: {
              available: true,
              activeId: "night",
              scheduled: true,
              choices: [
                {
                  id: "night",
                  label: "Night",
                  available: true
                },
                {
                  id: "day",
                  label: "Day",
                  available: true
                }
              ]
            }
          }
          var feedback = ({})
          if (harness.fixture === "action-pending")
            feedback[key] = {
              status: "pending",
              message: ""
            }
          if (harness.fixture === "action-error")
            feedback[key] = {
              status: "failed",
              message: "Timed out changing audio output"
            }
          if (entry.desktopActions.beginShowcase(snapshot, feedback) !== "ok") {
            harness.finish(false, "action fixture refused")
            return
          }
          entry.setFilter(harness.fixture === "actions" ? "action:" : "action: audio")
          if (harness.fixture !== "actions") {
            for (var row = 0; row < entry.displayModel.count; row++)
              if (entry.displayModel.get(row).desktopKey === key)
                entry.selectedIndex = row
            entry.cursorActive = true
          }
        } else {
          entry.setFilter(harness.fixture === "no-match" ? "zzzz no matches" : "p")
        }
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
