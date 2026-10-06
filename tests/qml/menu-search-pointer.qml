// A scoped global-search control must settle even when typing preserves row keys.
import QtQuick
import QtTest
import Quickshell
import qs.Ui
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  // Layout stamp before a query reveals the previously hidden affordance.
  property real before: 0
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    name: "searchPointer"
    when: false
  }
  Menu.Menu {
    id: menu
    windowEnabled: false
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
    run: function (command) {
      t.check(false, "search navigation must not dispatch")
    }
  }
  FloatingWindow {
    implicitWidth: 520
    implicitHeight: 400
    visible: true
    PointerMoveGate {
      id: gate
      referenceItem: surface
    }
    Menu.MenuSurface {
      id: surface
      width: menu.cardWidth
      height: menu.cardHeight
      root: menu
      pointerGate: gate
    }
  }
  // Locates the actual production Search everywhere control.
  function control() {
    return t.findChild(surface, "searchEverywhere")
  }
  // Parks the mouse at the control's future location while it is hidden.
  function park() {
    var point = control().mapToItem(surface, 8, control().height / 2)
    pointer.mouseMove(surface, point.x, point.y)
    gate.reset()
  }
  Component.onCompleted: {
    menu.openRoute("root")
    t.waitFor(function () {
      return menu.rowsLoaded && menu.opened
    }, 10000, "menu sources load", function () {
      menu.openRoute("system")
      t.equal(menu.displayModel.count, 1, "one-leaf scoped menu opens")
      t.step(400, function () {
        park()
        before = menu.layoutChangedAt
        var keys = menu.displayKeys
        menu.setFilter("lock")
        t.equal(menu.displayKeys, keys, "typing preserves every result key")
        t.equal(menu.layoutChangedAt, before, "equal result keys retain the existing row stamp")
        t.check(control().visible, "query reveals the production affordance")
        pointer.mouseClick(control(), 8, control().height / 2)
        t.equal(menu.activeMenu, "system", "immediate stationary click on newly appearing search is refused")
        menu.openRoute("system")
        t.step(400, function () {
          park()
          menu.setFilter("lock")
          t.step(400, function () {
            pointer.mouseClick(control(), 8, control().height / 2)
            t.check(menu.activeMenu === "root" && menu.filterText === "lock", "settled click performs query-preserving global search")
            menu.openRoute("system")
            t.step(400, function () {
              park()
              menu.setFilter("lock")
              t.step(30, function () {
                pointer.mouseMove(control(), 12, control().height / 2)
                pointer.mouseMove(control(), 18, control().height / 2)
                pointer.mouseClick(control(), 18, control().height / 2)
                t.check(menu.activeMenu === "root" && menu.filterText === "lock", "shared gate accepts a real move after appearance without waiting 300ms")
                t.done()
              })
            })
          })
        })
      })
    })
  }
}
