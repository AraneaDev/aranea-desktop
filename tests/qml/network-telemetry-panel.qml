// Real Network host lifecycle: telemetry remains public and resets in place.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.network" as Network

ShellRoot {
  QmlTest {
    id: t
  }
  Window {
    visible: true
    width: 1000
    height: 800
    Network.Panel {
      id: network
    }
  }
  Component.onCompleted: t.step(300, function () {
    network.open()
    network.updateDetails("iface\twlan0\nrx_bytes\t100\ntx_bytes\t50\nrouter_ping_ms\t2\ninternet_ping_ms\t10")
    t.equal(network.downloadRate, 0, "first sample starts throughput at zero")
    t.equal(network.linkHistory.length, 1, "open host records the first graph sample")
    network.activePage = "vpn"
    network.prevSampleTime = Date.now() / 1000 - 1
    network.updateDetails("iface\twlan0\nrx_bytes\t300\ntx_bytes\t150\nrouter_ping_ms\t4\ninternet_ping_ms\t20")
    t.check(network.downloadRate > 150 && network.downloadRate <= 210, "public previous sample write controls real throughput")
    t.equal(network.routerPingLatency, 3, "host forwards rolling router latency")
    t.equal(network.internetPingLatency, 15, "host forwards rolling internet latency")
    t.equal(network.linkHistory[1].rx, network.downloadRate, "graph records rates after throughput application")
    t.equal(network.linkHistory.length, 2, "telemetry continues while another hosted page is selected")
    var history = network.linkHistory
    var info = network.info
    var sampleTime = network.prevSampleTime
    network.pendingBand = "5"
    network.updateDetails("")
    t.equal(network.info, info, "reconnecting band retains the last good details")
    t.equal(network.linkHistory, history, "suppressed sample does not grow graph history")
    t.equal(network.prevSampleTime, sampleTime, "suppressed sample leaves throughput baseline alone")
    network.pendingBand = ""
    network.updateDetails("iface\teth0\nrx_bytes\t9000\ntx_bytes\t4000\nrouter_ping_ms\t7\ninternet_ping_ms\t30")
    t.equal(network.downloadRate, 0, "interface switch resets throughput")
    t.equal(network.routerPingSamples, [7], "interface switch replaces ping history")
    t.equal(network.linkHistory.length, 1, "interface switch starts a fresh graph")
    network.passwordSsid = "fixture"
    network.passwordText = "unsubmitted"
    network.close()
    t.equal(network.passwordText, "", "host still clears unsubmitted credentials")
    t.equal(network.prevSampleTime, 0, "close resets throughput baseline")
    t.equal(network.routerPingSamples, [], "close clears router ping history")
    t.equal(network.internetPingSamples, [], "close clears internet ping history")
    t.equal(network.internetPingLatency, -1, "close clears displayed ping latency")
    t.equal(network.linkHistory, [], "close clears graph history")
    t.equal(network.info.iface, "eth0", "close retains cached connection details")
    network.updateDetails("iface\teth0\nrx_bytes\t10000\ntx_bytes\t4500\ninternet_ping_ms\t40")
    t.equal(network.linkHistory, [], "a result arriving after close adds no graph sample")
    t.equal(network.internetPingSamples, [40], "a result arriving after close still applies ping state")
    network.updateDetails("")
    t.equal(network.info, {}, "real disconnect clears details when no band change is busy")
    t.check(!network.hasTransferStats && !network.hasInternetPing, "real disconnect removes available stats")
    t.done()
  })
}
