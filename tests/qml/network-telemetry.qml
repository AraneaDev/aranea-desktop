// Real command/poll lifetime: never overlap a slow read or cancel it on close.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.network" as Network

ShellRoot {
  QmlTest {
    id: t
  }
  NetworkFixture {
    id: fixture
  }
  Network.NetworkTelemetry {
    id: telemetry
  }
  Component.onCompleted: fixture.configure({
    delay: 3,
    started: 0,
    finished: 0,
    response: "iface\twlan0\nrx_bytes\t100\ntx_bytes\t50\ninternet_ping_ms\t12"
  }, function () {
    telemetry.refresh()
    telemetry.refresh()
    telemetry.pollingEnabled = true
    t.waitFor(function () {
      return fixture.state.started === 1
    }, 1500, "explicit refresh starts the real details command", function () {
      t.step(1700, function () {
        t.equal(fixture.state.started, 1, "refresh and poll cannot overlap an in-flight details read")
        t.equal(fixture.state.finished, 0, "details read is still pending when polling is disabled")
        telemetry.pollingEnabled = false
        telemetry.resetMeasurements()
        telemetry.resetLinkHistory()
        t.waitFor(function () {
          return telemetry.info.iface === "wlan0" && fixture.state.finished === 1
        }, 2000, "in-flight read survives polling being disabled", function () {
          t.equal(telemetry.internetPingLatency, 12, "late closed result still updates ping measurements")
          t.equal(telemetry.linkHistory, [], "late closed result cannot refill graph history")
          t.step(1700, function () {
            t.equal(fixture.state.started, 1, "disabled polling does not launch another command")
            fixture.configure({
              delay: 0,
              response: "iface\teth0\nrx_bytes\t9000\ntx_bytes\t4000\ninternet_ping_ms\t24"
            }, function () {
              telemetry.pollingEnabled = true
              t.waitFor(function () {
                return telemetry.info.iface === "eth0"
              }, 2500, "reenabling polling reads the next connection", function () {
                telemetry.pollingEnabled = false
                t.equal(telemetry.downloadRate, 0, "polled interface switch starts rate calculation from zero")
                t.equal(telemetry.internetPingSamples, [24], "polled interface switch resets ping history")
                t.equal(telemetry.linkHistory, [
                  {
                    iface: "eth0",
                    rx: 0,
                    tx: 0
                  }
                ], "polled result records the updated interface and rates")
                t.done()
              })
            })
          })
        })
      })
    })
  })
}
