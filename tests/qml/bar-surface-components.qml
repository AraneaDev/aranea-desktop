// Behaviour contracts for larger bar surface components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.bar" as BarComponents

ShellRoot {
  QmlTest {
    id: t
  }

  QtObject {
    id: barOwner
    property bool motionEnabled: true
    property bool vertical: false
    property bool transparent: false
    property color background: "black"
    property color barForeground: "white"
    property string position: "top"
    property var barDragSource: null
    property var activePopout: null
    property var barWidgetRegistry: null
    property var shell: null
    function registerModuleSlot(item) {
    }
    function unregisterModuleSlot(item) {
    }
    function moduleClickTargetAt(item, x, y) {
      return false
    }
  }

  BarComponents.BarModuleSlot {
    id: slot
    owner: barOwner
    width: 30
    height: 30
    moduleId: "clock"
    openIndicatorVisible: true
  }

  BarComponents.BarDragOverlay {
    id: drag
    active: true
    barPosition: "top"
  }
  BarComponents.CenterGestureArea {
    id: gesture
  }
  BarComponents.CustomCommandModule {
    id: custom
    entry: ({
        id: "custom"
      })
  }

  Component.onCompleted: {
    t.equal(slot.moduleId, "clock", "bar slots expose module identity")
    t.equal(slot.openIndicatorVisible, true, "bar slots expose indicator state")
    t.equal(drag.active, true, "bar drag overlays expose active state")
    t.equal(drag.barPosition, "top", "bar drag overlays expose bar position")
    t.equal(gesture.dragThreshold > 0, true, "center gesture areas expose a drag threshold")
    t.equal(custom.moduleName, "custom", "custom command modules expose their entry identity")
    slot.openIndicatorVisible = false
    t.step(200, function () {
      var indicator = t.childrenOf(slot).find(function (item) {
        return item.z === 50
      })
      t.check(indicator && indicator.opacity === 0, "bar indicator finishes its hide animation")
      barOwner.motionEnabled = false
      slot.openIndicatorVisible = true
      t.equal(indicator.opacity, 0.75, "bar indicator changes immediately with motion disabled")
      t.done()
    })
  }
}
