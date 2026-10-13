// Backend-validated acknowledgments update the live list without hiding other checks.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.health" as Health

ShellRoot {
  QmlTest {
    id: t
  }
  Health.Monitor {
    id: monitor
    autoStart: false
    acknowledgmentCommand: ["sh", "-c", "printf '%s' '{\"acknowledged\":[\"container:demo\"]}'"]
  }
  Component.onCompleted: {
    monitor.setProblems("container", [
      {
        key: "container:demo",
        check: "container",
        name: "demo",
        exitCode: 15
      }
    ])
    monitor.setProblems("unit", [
      {
        key: "unit:user:demo.service",
        check: "unit",
        unit: "demo.service",
        scope: "user"
      }
    ])
    monitor.refreshAcknowledgments()
    t.waitFor(function () {
      return !monitor.acknowledgmentChecking && monitor.openProblems.length === 1
    }, 4000, "acknowledged stop clears through the real backend transport", function () {
      t.equal(monitor.openProblems[0].check, "unit", "service failures remain visible")
      monitor.acknowledgmentCommand = ["sh", "-c", "printf '%s' '{\"acknowledged\":[]}'"]
      monitor.refreshAcknowledgments()
      t.waitFor(function () {
        return !monitor.acknowledgmentChecking && monitor.openProblems.length === 2
      }, 4000, "a later unacknowledged occurrence becomes visible", function () {
        t.equal(monitor.acknowledgedContainerKeys.length, 0, "expired acknowledgment stops filtering")
        monitor.acknowledgmentCommand = ["/nonexistent/aranea-health-ack"]
        monitor.refreshAcknowledgments()
        t.waitFor(function () {
          return !monitor.acknowledgmentChecking
        }, 4000, "failed backend startup settles", function () {
          t.equal(monitor.openProblems.length, 2, "an unavailable acknowledgment backend never hides issues")
          t.done()
        })
      })
    })
  }
}
