// Consolidated Health shortcut follows real issues and keeps its open anchor.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.health" as Health

ShellRoot {
  QmlTest {
    id: t
  }
  QtObject {
    id: service
    property var metrics: ({})
    property string status: "healthy"
    property var problems: []
    function panelOpened() {
    }
    function panelClosed() {
    }
  }
  FloatingWindow {
    visible: true
    width: 200
    height: 60
    Health.HealthPanel {
      id: panel
      alertOnly: true
      service: null
    }
  }
  Component.onCompleted: t.step(100, function () {
    t.check(!panel.visible && panel.implicitWidth === 0, "unavailable Health does not add a permanent icon")
    panel.service = service
    t.check(!panel.visible && panel.implicitWidth === 0, "healthy service leaves the bar clear")
    service.status = "attention"
    service.problems = [
      {
        key: "disk:/",
        summary: "Disk nearly full",
        urgency: 1
      }
    ]
    t.check(panel.visible && panel.implicitWidth > 0, "a real issue reveals the shortcut")
    service.status = "healthy"
    service.problems = []
    t.check(!panel.visible, "clearing issues removes the shortcut")
    service.metrics = null
    panel.open()
    t.check(panel.visible, "opening Health retains a usable anchor")
    panel.close()
    t.check(!panel.visible, "closing restores the quiet bar")
    panel.alertOnly = false
    t.check(panel.visible, "standalone Health remains available without System")
    t.done()
  })
}
