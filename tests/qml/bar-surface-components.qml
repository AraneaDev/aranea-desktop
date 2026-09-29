// Behaviour contracts for larger bar surface components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.bar" as BarComponents

ShellRoot {
  QmlTest {
    id: t
  }

  BarComponents.BarModuleSlot {
    id: slot
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

  Component.onCompleted: {
    t.equal(slot.moduleId, "clock", "bar slots expose module identity")
    t.equal(slot.openIndicatorVisible, true, "bar slots expose indicator state")
    t.equal(drag.active, true, "bar drag overlays expose active state")
    t.equal(drag.barPosition, "top", "bar drag overlays expose bar position")
    t.equal(gesture.dragThreshold > 0, true, "center gesture areas expose a drag threshold")
    t.done()
  }
}
