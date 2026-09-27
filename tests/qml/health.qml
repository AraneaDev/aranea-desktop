// Behaviour of the health checks (Monitor.qml) and service (Service.qml)
// with the automatic checks off and docker replaced by a shell function: a
// failed `docker ps` keeps the container problems it already had, a snapshot
// with a crashed container reports it, and a reloaded service takes over the
// open dropdown's count while the old one lets go.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.health" as Health
import "plugins/araneadev.health/HealthBridge.js" as HealthBridge

ShellRoot {
  id: testRoot

  // A docker whose daemon answers but whose `docker ps` fails.
  readonly property string psFails: "case $1 in info) echo 27.0 ;; ps) exit 1 ;; *) sleep 30 ;; esac"
  // A docker with one container that exited with status 1.
  readonly property string psCrashed: "case $1 in info) echo 27.0 ;; " + "ps) printf '%s\\n' '{\"Names\":\"web\",\"Image\":\"nginx\",\"State\":\"exited\",\"Status\":\"Exited (1) 2 minutes ago\"}' ;; " + "*) sleep 30 ;; esac"

  QmlTest {
    id: t
  }

  Health.Monitor {
    id: failing
    autoStart: false
    dockerCommand: ["sh", "-c", testRoot.psFails, "docker"]
  }

  Health.Monitor {
    id: crashed
    autoStart: false
    dockerCommand: ["sh", "-c", testRoot.psCrashed, "docker"]
  }

  // Health services, created by the reload check.
  Component {
    id: serviceComponent
    Health.Service {
      checksEnabled: false
    }
  }

  // Keys of a monitor's open problems.
  function keys(monitor) {
    return monitor.openProblems.map(function (p) {
      return p.key
    })
  }

  Component.onCompleted: {
    // A container problem from before; then docker ps fails.
    failing.setProblems("container", [
      {
        key: "container:db",
        check: "container",
        name: "db",
        image: "postgres",
        exitCode: 1,
        exits: 1,
        loop: false
      }
    ])
    failing.startDocker()
    crashed.startDocker()

    // A reload: the new service publishes before the old one goes, and the
    // open dropdown moves its count across (as Panel.qml does).
    var oldService = serviceComponent.createObject(testRoot)
    oldService.panelOpened()
    t.check(oldService.metrics.topActive, "an open dropdown turns on top sampling")
    var newService = serviceComponent.createObject(testRoot)
    t.check(HealthBridge.current() === newService, "the new service is published")
    oldService.panelClosed()
    newService.panelOpened()
    oldService.destroy()

    t.step(1500, function () {
      t.equal(keys(failing), ["container:db"], "a failed docker ps keeps the container problems")
      t.equal(failing.known.container, false, "the container check is marked unavailable")
      t.equal(keys(crashed), ["container:web"], "a crashed container is reported")

      t.check(HealthBridge.current() === newService, "the old service going away leaves the new one published")
      t.check(newService.metrics.topActive, "top sampling stays on after the reload")
      newService.panelClosed()
      newService.panelClosed()
      t.equal(newService.openPanels, 0, "an extra close never goes below zero")
      t.check(!newService.metrics.topActive, "closing the dropdown stops top sampling")
      t.done()
    })
  }
}
