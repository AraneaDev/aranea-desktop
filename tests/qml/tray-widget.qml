// Tray icon dispatch through the bar's click registry, including menu-only apps.
import QtQuick
import Quickshell
import QtTest
import "lib"
import "plugins/araneadev.tray" as Tray

ShellRoot {
  id: testRoot
  property int activations: 0
  property int secondaryActivations: 0
  property var targets: []
  property int menus: 0
  property var menuPoint: null
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }
  QtObject {
    id: app
    property string title: "Fixture"
    property string tooltipTitle: "Fixture"
    property string icon: ""
    property int status: 1
    property bool onlyMenu: false
    property var menu: null
    function activate() {
      testRoot.activations++
    }
    function secondaryActivate() {
      testRoot.secondaryActivations++
    }
    function display(window, x, y) {
    }
  }
  QtObject {
    id: bar
    property bool vertical: false
    property int barSize: 30
    property color foreground: "white"
    property string position: "top"
    property var activePopout: null
    function registerClickTarget(target) {
      testRoot.targets.push(target)
    }
    function unregisterClickTarget(target) {
      var at = testRoot.targets.indexOf(target)
      if (at >= 0)
        testRoot.targets.splice(at, 1)
    }
    function showTooltip(target, text) {
    }
    function hideTooltip(target) {
    }
    function requestPopout(owner) {
      activePopout = owner
    }
    function releasePopout(owner) {
      activePopout = null
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 60
    implicitHeight: 60
    Tray.TrayItemButton {
      id: widget
      bar: bar
      modelData: app
      width: 30
      height: 30
      onMenuRequested: function (mouse) {
        testRoot.menus++
        testRoot.menuPoint = mouse
      }
    }
  }
  Component.onCompleted: t.step(100, function () {
    var icon = widget
    t.check(icon !== null, "fixture has a tray icon")
    t.check(testRoot.targets.indexOf(icon) >= 0, "tray icon registers with bar click routing")
    t.check(icon && typeof icon.triggerPress === "function", "tray icon exposes routed presses")
    if (icon && typeof icon.triggerPress === "function") {
      icon.triggerPress(Qt.LeftButton)
      t.equal(testRoot.activations, 1, "routed left click activates app once")
      icon.triggerPress(Qt.MiddleButton)
      t.equal(testRoot.secondaryActivations, 1, "routed middle click secondary activates")
      icon.triggerPress(Qt.RightButton)
      t.equal(testRoot.menus, 1, "routed right click opens menu")
      t.equal([testRoot.menuPoint.x, testRoot.menuPoint.y], [15, 15], "routed menu has fallback anchor coordinates")
      app.onlyMenu = true
      icon.triggerPress(Qt.LeftButton)
      t.equal(testRoot.menus, 2, "menu-only left click opens menu")
      t.equal(testRoot.activations, 1, "menu-only click does not activate app")
      pointer.mousePress(icon, 10, 10, Qt.RightButton)
      t.equal(testRoot.menus, 2, "right press waits for completed click")
      pointer.mouseRelease(icon, 10, 10, Qt.RightButton)
      t.equal(testRoot.menus, 3, "right release opens menu once")
      widget.bar = null
      t.check(testRoot.targets.indexOf(icon) < 0, "detached tray icon unregisters")
    }
    t.done()
  })
}
