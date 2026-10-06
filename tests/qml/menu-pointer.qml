// The Aranea menu's pointer rules, with real pointer events on the result
// list and a root tile in a window, wired to the real Menu.qml (its own
// window off) the way MenuWindow wires them: the mint outline marks Enter's
// target and shows from open on the first row; hover fills the row under
// the pointer after a real move but never moves the outline; the first
// Down moves it straight to the second row; typing keeps it on the top
// match so Enter launches that match even with the pointer over another
// row; the hover fill clears when the rows change under a still pointer;
// the empty state shows no outline; a click is keyed by the row's item id
// and refused when the row holds another item on release; the rows
// changing stamps the layout (an equal rebuild does not) and a click
// inside the 300 ms settle window is refused; rows survive a rebuild; a
// click into a submenu puts the outline on its first row; and a root tile
// tints only after a real pointer move and settles and keys its clicks.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // Commands and launches the menu made, newest last.
  property var ran: []
  // Tiles the tile under test activated.
  property int tileClicks: 0
  // The row pressed before the results changed.
  property var pressedRow: null
  // The layout stamp a step compares against.
  property real stampBefore: 0
  // The top row's app id when Enter was pressed.
  property string topAppId: ""

  QmlTest {
    id: t
  }

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
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
    // Three apps, as the library's sorted rows.
    function sortedEntries(query) {
      return [
        {
          entry: {
            id: "firefox",
            name: "Firefox"
          }
        },
        {
          entry: {
            id: "firewall",
            name: "Firewall"
          }
        },
        {
          entry: {
            id: "gimp",
            name: "GIMP"
          }
        }
      ]
    }
    // Nothing to refresh offscreen.
    function refreshIcons() {
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
    // The test's own menu, never the installed Omarchy's.
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
    run: function (command) {
      shell.ran = shell.ran.concat([command])
    }
  }

  FloatingWindow {
    implicitWidth: 520
    implicitHeight: 640
    visible: true

    Menu.MenuRootTile {
      id: tile
      x: 0
      y: 0
      width: 160
      height: 96
      tileData: ({
          id: "tile.setup",
          label: "Setup",
          detail: "CONFIGURE",
          icon: "S"
        })
      onActivated: shell.tileClicks += 1
    }

    Menu.MenuResultList {
      id: results
      x: 0
      y: 120
      width: 480
      height: 500
      model: menu.displayModel
      selectedIndex: menu.selectedIndex
      cursorActive: menu.outlineShown
      filterText: menu.filterText
      fullRootHeader: menu.fullRootHeader
      layoutChangedAt: menu.layoutChangedAt
      rowHeightForDetail: menu.rowHeightForDetail
      onRowActivated: function (index, key) {
        menu.activateKey(index, key)
      }
    }
  }

  // A fake key event: CODE, with TEXT when it types.
  function key(code, text) {
    return {
      key: code,
      modifiers: Qt.NoModifier,
      text: text || "",
      accepted: false
    }
  }

  // Types TEXT into the menu one key at a time.
  function type(text) {
    for (var i = 0; i < text.length; i++)
      menu.handleKey(key(0, text[i]))
  }

  // The row delegate at INDEX, or null.
  function rowAt(index) {
    return results.list.itemAtIndex(index)
  }

  // The display index of item ID, or -1.
  function indexOf(id) {
    for (var i = 0; i < menu.displayModel.count; i++)
      if (menu.displayModel.get(i).itemId === id)
        return i
    return -1
  }

  // Moves the pointer onto row INDEX and then a few pixels on (two real
  // samples, so the gate counts it as a move).
  function hoverRow(index) {
    var row = rowAt(index)
    pointer.mouseMove(row, 40, row.height / 2)
    pointer.mouseMove(row, 46, row.height / 2)
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then finishes.
  function run(steps) {
    if (steps.length === 0) {
      t.done()
      return
    }
    t.step(steps[0][0], function () {
      steps[0][1]()
      run(steps.slice(1))
    })
  }

  Component.onCompleted: {
    menu.openRoute("root")
    t.waitFor(function () {
      return menu.rowsLoaded && menu.opened && menu.displayModel.count >= 3
    }, 10000, "menu sources load and the root opens", function () {
      run([[400, function () {
            // ---------- Open: the outline is on the top row ----------
            t.check(menu.cursorActive && menu.selectedIndex === 0, "the cursor is on the first row on open")
            t.check(menu.outlineShown && rowAt(0).hasCursor && t.findChild(rowAt(0), "cursorOutline").visible, "the outline marks Enter's target from open")
            t.check(!rowAt(0).hovered && !rowAt(1).hovered && !rowAt(2).hovered, "no row is hover-filled under a still pointer")

            // ---------- Hover fills, never moves the cursor ----------
            hoverRow(2)
          }], [60, function () {
            t.check(rowAt(2).hovered, "a real move onto a row fills it")
            t.check(rowAt(2).borderLeft === 0 && rowAt(2).borderTop === 0 && rowAt(2).borderRight === 0 && rowAt(2).borderBottom === 0, "with the fill only, no border, as the pickers' hover")
            t.check(!rowAt(0).hovered && !rowAt(1).hovered, "and only that row")
            t.equal(menu.selectedIndex, 0, "hovering another row does not move the keyboard cursor")
            t.check(rowAt(0).hasCursor && !rowAt(2).hasCursor, "the outline stays on the first row")

            // ---------- The arrows move the outline ----------
            menu.handleKey(key(Qt.Key_Down))
            t.equal(menu.selectedIndex, 1, "the first Down moves the keyboard cursor to the second row")
            t.check(rowAt(1).hasCursor && t.findChild(rowAt(1), "cursorOutline").visible && !rowAt(0).hasCursor, "and shows the outline on the next row")
            t.check(rowAt(2).hovered && !rowAt(2).hasCursor, "the hover fill stays where the pointer is")
            menu.handleKey(key(Qt.Key_Up))
            t.equal(menu.selectedIndex, 0, "Up moves it back")
            t.check(rowAt(0).hasCursor && !rowAt(1).hasCursor, "with the outline")
            hoverRow(1)
          }], [60, function () {
            t.equal(menu.selectedIndex, 0, "a real move after the arrows still does not move the cursor")
            t.check(rowAt(1).hovered && rowAt(0).hasCursor, "it fills the hovered row while the outline stays put")

            // ---------- Type, then Enter targets the top item ----------
            type("fire")
            t.check(menu.displayModel.count >= 2, "the search shows several matches")
            t.equal(menu.selectedIndex, 0, "typing keeps the cursor on the first match")
            t.check(menu.outlineShown && rowAt(0).hasCursor, "with the outline shown")
            t.check(!rowAt(0).hovered && !rowAt(1).hovered, "the rows changing under the still pointer drop the hover fill")
            hoverRow(1)
          }], [60, function () {
            t.check(rowAt(1).hovered, "a real move fills the second match")
            t.equal(menu.selectedIndex, 0, "hovering it does not steal the keyboard cursor")
            topAppId = menu.displayModel.get(0).appId
            t.check(topAppId !== "" && topAppId !== menu.displayModel.get(1).appId, "the top match is an app other than the hovered one")
            menu.handleKey(key(Qt.Key_Return))
            t.check(shell.ran.some(function (r) {
              return r[0] === "launch" && r[1] === topAppId
            }), "Enter launches the top match")
            t.equal(shell.ran.filter(function (r) {
              return r[0] === "launch"
            }).length, 1, "and only it")
            t.check(!menu.opened, "and closes the menu")
            menu.openRoute("root")
          }], [400, function () {
            // ---------- Typing keeps the outline on row 0; none when empty ----------
            type("s")
            t.check(menu.outlineShown && menu.selectedIndex === 0 && rowAt(0).hasCursor, "typing keeps the outline on the top row")
            type("qqq")
            t.check(menu.displayModel.count === 0 && !menu.outlineShown, "the empty state shows no outline")
            shell.ran = []
            menu.handleKey(key(Qt.Key_Return))
            t.check(menu.opened && shell.ran.length === 0, "and Enter does nothing there")
            menu.setFilter("")
          }], [400, function () {
            // ---------- Keyed refusal ----------
            t.check(!menu.activateKey(0, "no.such.item"), "a key the row does not hold is refused")
            t.check(menu.opened && menu.activeMenu === "root", "and does nothing")
            shell.ran = []
            pressedRow = rowAt(0)
            var before = menu.displayModel.get(0).itemId
            pointer.mousePress(pressedRow, 40, pressedRow.height / 2)
            menu.setFilter("lock")
            t.check(menu.displayModel.get(0).itemId !== before, "the results change under the pressed row")
            t.check(rowAt(0) === pressedRow, "the row delegate survives the rebuild")
          }], [400, function () {
            pointer.mouseRelease(pressedRow, 40, pressedRow.height / 2)
            t.equal(shell.ran.length, 0, "a release on a row that now holds another item is refused")
            t.check(menu.opened && menu.filterText === "lock", "and the menu is untouched")

            menu.setFilter("")
          }], [400, function () {
            // ---------- Settle after the results change ----------
            stampBefore = menu.layoutChangedAt
            menu.rebuildDisplay()
            t.equal(menu.layoutChangedAt, stampBefore, "an equal rebuild does not stamp the layout")
            pressedRow = rowAt(0)
            menu.setFilter("s")
            t.check(menu.layoutChangedAt > stampBefore, "the results changing stamps the layout")
            t.check(rowAt(0) === pressedRow, "the first row keeps its delegate")
            pointer.mouseClick(pressedRow, 40, pressedRow.height / 2)
            t.check(menu.opened && menu.activeMenu === "root" && menu.filterText === "s" && shell.ran.length === 0, "a click right after the results change is refused")
            menu.setFilter("")
          }], [400, function () {
            var setup = indexOf("setup")
            pointer.mouseClick(rowAt(setup), 40, rowAt(setup).height / 2)
            t.equal(menu.activeMenu, "setup", "a settled click opens the clicked row")
            t.equal(menu.selectedIndex, 0, "the new menu puts the cursor on its first row")
            t.check(menu.outlineShown && rowAt(0).hasCursor, "with the outline on it")

            // ---------- Root tile: gated tint, keyed and settled click ----------
            tile.pointerGate.reset()
            pointer.mouseMove(tile, 40, 40)
          }], [60, function () {
            t.check(!tile.hovered, "a tile under a still pointer is not tinted")
            pointer.mouseMove(tile, 50, 40)
          }], [60, function () {
            t.check(tile.hovered, "a real move onto the tile tints it")
            tile.layoutChangedAt = Date.now()
            pointer.mouseClick(tile, 50, 40)
            t.equal(tileClicks, 0, "a tile click right after a layout change is refused")
          }], [400, function () {
            pointer.mouseClick(tile, 50, 40)
            t.equal(tileClicks, 1, "a settled tile click activates it")
            pointer.mousePress(tile, 50, 40)
            tile.tileData = {
              id: "tile.files",
              label: "Files",
              detail: "BROWSE",
              icon: "F"
            }
            pointer.mouseRelease(tile, 50, 40)
            t.equal(tileClicks, 1, "a release on a tile that changed underneath is refused")
            menu.openRoute("root")
            menu.desktopSearch.compositor = null
            menu.desktopSearch.fixtureWindows = [
              {
                address: "0xaaa",
                title: "Fixture A"
              },
              {
                address: "0xbbb",
                title: "Fixture B"
              }
            ]
            menu.desktopSearch.runner = function (argv) {
              shell.ran = shell.ran.concat([argv])
              return true
            }
            menu.desktopSearch.refreshNow()
            menu.setFilter("window: Fixture")
          }], [400, function () {
            pressedRow = rowAt(0)
            pointer.mousePress(pressedRow, 40, pressedRow.height / 2)
            menu.desktopSearch.fixtureWindows = [
              {
                address: "0xbbb",
                title: "Fixture B"
              }
            ]
            menu.desktopSearch.refreshNow()
            t.check(rowAt(0) === pressedRow, "desktop window delegate survives replacement")
            shell.ran = []
          }], [400, function () {
            pointer.mouseRelease(pressedRow, 40, pressedRow.height / 2)
            t.equal(shell.ran.length, 0, "closing a window during pointer press cannot launch its replacement")
            t.check(menu.opened && !menu.cursorActive, "vanished pointer target clears selection and retains menu")
          }]])
    })
  }
}
