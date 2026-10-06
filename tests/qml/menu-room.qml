// Real launcher geometry: expanded root viewport and constrained-screen fit.
import QtQuick
import Quickshell
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
    t.check(menu.availableRowsHeight() > menu.style.baseRowHeight * 7, "normal root viewport fits at least seven rows")
    t.check(menu.cardHeight < 790, "normal root card fits within margins")
    view.height = 420
    t.step(10, function () {
      t.check(menu.cardHeight < 420, "short-screen root stays inside margins")
      t.check(menu.visibleRowsHeight > 0, "short-screen root keeps usable scrolling")
      t.done()
    })
  })
}
