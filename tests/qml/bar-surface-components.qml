// Behaviour contracts for larger bar surface components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.bar" as BarComponents

ShellRoot {
  QmlTest {
    id: t
  }

  BarComponents.Bar {
    id: tooltipBar
    motionEnabled: false
    barConfig: ({
        transparent: false
      })
  }
  Item {
    id: firstTarget
    property bool tooltipHovered: true
  }
  Item {
    id: secondTarget
    property bool tooltipHovered: true
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
      tooltipBar.showTooltip(firstTarget, "First")
      t.check(!tooltipBar.tooltipShown, "first tooltip waits for initial delay")
      t.waitFor(function () {
        return tooltipBar.tooltipShown
      }, 1000, "first tooltip appears", function () {
        tooltipBar.hideTooltip(firstTarget)
        tooltipBar.showTooltip(secondTarget, "Second")
        t.step(30, function () {
          t.check(tooltipBar.tooltipShown && tooltipBar.tooltipText === "Second", "tooltip handoff skips the initial delay")
          t.done()
        })
      })
    })
  }
}
