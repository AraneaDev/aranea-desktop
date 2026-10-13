// Missing optional controllers must never prevent the Power surface loading.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.power" as Power

ShellRoot {
  // Whether the fixture includes the Display controller.
  property bool expectDisplay: true
  // Whether the fixture includes the Health controller.
  property bool expectHealth: true
  QmlTest {
    id: t
  }
  Power.Panel {
    id: system
  }
  Component.onCompleted: t.step(100, function () {
    t.equal(!!system.displayController, expectDisplay, "Display controller availability matches installed directory")
    t.equal(!!system.healthController, expectHealth, "Health controller availability matches installed directory")
    system.open()
    t.check(system.opened && system.activePage === "power", "Power remains usable with optional plugins missing")
    if (!system.displayController) {
      system.selectPage("display")
      t.equal(system.activePage, "power", "missing Display cannot select an empty page")
    }
    if (!system.healthController) {
      system.selectPage("health")
      t.equal(system.activePage, "power", "missing Health cannot select an empty page")
    }
    if (system.displayController) {
      system.displayController.open()
      t.check(system.activePage === "display" && system.displayController.opened && !!system.displayController.activeDropdown, "installed Display page remains usable without Health")
      system.close()
      system.open()
    }
    if (system.healthController) {
      system.healthController.open()
      t.check(system.activePage === "health" && system.healthController.opened && !!system.healthController.activeDropdown, "installed Health page remains usable without Display")
    }
    system.close()
    t.done()
  })
}
