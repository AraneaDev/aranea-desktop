// Real launcher geometry: expanded root viewport and constrained-screen fit.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: root
  QmlTest {
    id: t
  }
  QtObject {
    id: view
    property int width: 1440
    property int height: 810
    property int cardTop: -1
    property int maxRowsHeight: -1
    function revealCursor() {
    }
    function focusKeys() {
    }
    function disarmPointer() {
    }
  }
  Menu.Menu {
    id: menu
    windowEnabled: false
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
  }
  Component.onCompleted: t.waitFor(function () {
    return menu.rowsLoaded && menu.menuSourcesReady
  }, 4000, "menu loaded", function () {
    menu.openRoute("root")
    menu.view = view
    t.check(menu.cardWidth <= Style.space(540), "root shares the compact submenu width")
    menu.selectedIndex = 0
    menu.cursorActive = true
    menu.handleKey({
      key: Qt.Key_Down,
      modifiers: Qt.NoModifier,
      text: "",
      accepted: false
    })
    t.equal(menu.selectedIndex, 1, "Down moves to the next command")
    menu.handleKey({
      key: Qt.Key_Up,
      modifiers: Qt.NoModifier,
      text: "",
      accepted: false
    })
    t.equal(menu.selectedIndex, 0, "Up returns to the previous visual command row")
    var expandedChrome = menu.style.chromeHeight
    t.check(menu.availableRowsHeight() > menu.style.baseRowHeight * 7, "normal root viewport fits at least seven rows")
    t.check(menu.cardHeight < 790, "normal root card fits within margins")
    view.height = 420
    t.step(10, function () {
      t.check(menu.style.chromeHeight < expandedChrome, "short screens compress the command deck to leave room for results")
      t.check(menu.cardHeight < 420, "short-screen root stays inside margins")
      t.check(menu.visibleRowsHeight > 0, "short-screen root keeps usable scrolling")
      Style.spacingScale = 1.5
      t.step(20, function () {
        t.check(menu.visibleRowsHeight >= menu.style.detailRowHeight * 2, "short screens with enlarged controls retain two usable result rows")
        t.done()
      })
    })
  })
}
