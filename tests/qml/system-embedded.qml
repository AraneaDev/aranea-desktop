// Battery/System owns the window; embedded controllers retain live actions.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.power" as Power

ShellRoot {
  QmlTest {
    id: t
  }
  QtObject {
    id: healthService
    property var metrics: null
    property int openPanels: 0
    function panelOpened() {
      openPanels++
    }
    function panelClosed() {
      openPanels--
    }
  }
  Window {
    id: testWindow
    visible: true
    width: 1000
    height: 800
    TestCase {
      id: input
      when: false
    }
    Power.Panel {
      id: system
    }
  }
  // Deliver a key to the hosted System page.
  function press(key) {
    testWindow.requestActivate()
    system.keyCatcher.forceActiveFocus()
    input.keyClick(key)
  }
  Component.onCompleted: t.step(100, function () {
    t.check(!!system.displayController, "System loads the existing Display controller")
    t.check(!!system.healthController, "System loads the existing Health controller")
    if (!system.displayController || !system.healthController) {
      t.done()
      return
    }
    system.healthController.service = healthService
    system.displayController.open()
    t.check(system.opened && system.activePage === "display", "legacy Display open selects the shared page")
    t.check(system.displayController.opened && !system.displayController.visible && system.displayController.implicitWidth === 0, "Display lifecycle opens without another bar control")
    system.displayController.navigateKeyboard(0, 1)
    t.check(system.displayController.keyboardCursor && system.displayController.cursorActive, "shared keyboard navigation reveals Display controls")
    press(Qt.Key_S)
    t.equal(system.activePage, "health", "real S key selects Health through the native catcher")
    t.check(!system.displayController.opened && system.healthController.opened, "switching pages releases Display and opens Health")
    t.equal(healthService.openPanels, 1, "Health sampling counts the selected embedded page")
    t.check(system.healthController.resourcesExpanded, "Health resources start expanded")
    t.check(!system.healthController.visible && system.healthController.implicitWidth === 0, "embedded Health creates no extra bar control")
    press(Qt.Key_D)
    t.equal(system.activePage, "display", "D shortcut selects Display")
    t.equal(healthService.openPanels, 0, "switching away releases Health sampling")
    press(Qt.Key_P)
    t.equal(system.activePage, "power", "P shortcut selects Power")
    press(Qt.Key_H)
    t.check(system.activePage === "power" && system.keyboardCursor, "real h key retains native left navigation")
    system.healthController.open()
    t.equal(healthService.openPanels, 1, "reopening embedded Health counts exactly once")
    system.healthController.close()
    t.check(!system.opened && !system.healthController.opened, "Health actions close the shared host")
    t.equal(healthService.openPanels, 0, "closing System releases Health sampling")
    system.open()
    t.equal(system.activePage, "power", "fresh System open restores the familiar Power page")
    system.close()
    // Existing plugins can still use the same controller as standalone widgets.
    system.displayController.embedded = false
    system.healthController.embedded = false
    system.displayController.open()
    t.check(system.displayController.opened && !system.opened, "standalone Display fallback opens independently")
    system.displayController.close()
    system.healthController.open()
    t.check(system.healthController.opened && !system.opened, "standalone Health fallback opens independently")
    system.healthController.close()
    t.equal(healthService.openPanels, 0, "standalone fallback also releases Health sampling")
    t.done()
  })
}
