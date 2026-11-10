// Real Network host lifecycle: telemetry remains public and resets in place.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Networking
import "fixtures/network-host" as NetworkBoundary
import "lib"
import "plugins/araneadev.network" as Network

ShellRoot {
  QmlTest {
    id: t
  }
  TestCase {
    id: keys
    when: false
  }
  NetworkFixture {
    id: fixture
  }
  QtObject {
    id: host
    property string position: "top"
    property string fontFamily: "sans-serif"
    property color foreground: "white"
    property color barForeground: "white"
    property color urgent: "red"
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property int sizeHorizontal: 32
    property int iconSize: 16
    property int barSize: 32
    property int iconCanvas: 24
    property int iconSlot: 32
    function showTooltip() {
    }
    function hideTooltip() {
    }
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
    NetworkBoundary.Networking.devices = {
      values: [
        {
          type: DeviceType.Wired,
          connected: true
        }
      ]
    }
    network.info = {
      iface: "eth0",
      type: "ethernet"
    }
    NetworkBoundary.Networking.connectivity = NetworkConnectivity.Full
    network.updatePingLatency({
      iface: "eth0",
      internet_ping_ms: "12"
    })
    t.equal(network.statsView.ping, "12 ms", "full link shows measured latency")
    NetworkBoundary.Networking.connectivityCheckEnabled = false
    t.equal(network.connectivity, "unknown", "disabled checks ignore cached state")
    t.equal(network.statsView.ping, "12 ms", "unknown connectivity keeps real measurements")
    NetworkBoundary.Networking.connectivityCheckEnabled = true
    network.bar = host
    NetworkBoundary.Networking.connectivity = NetworkConnectivity.Portal
    t.check(network.hasCaptivePortal, "NM portal state exposes sign-in")
    network.updatePingLatency({
      iface: "eth0",
      internet_ping_ms: ""
    })
    t.equal(network.statsView.ping, "--", "portal hides invented timeout")
    t.equal(network.statsView.loss, "--", "portal hides invented loss")
    t.check(!network.statsView.lossy, "hidden loss is not highlighted")
    network.open()
    network.activePage = "network"
    network.focusSection = "header"
    network.setHeaderCursor(network.portalHeaderIndex)
    network.chooseCursorRow("header")
    network.cursorActive = true
    network.keyboardCursor = true
    network.keyCatcher.forceActiveFocus()
    keys.keyPress(Qt.Key_Return)
    t.waitFor(function () {
      return fixture.state.portalArgv !== undefined
    }, 1500, "portal helper executes", function () {
      t.equal(fixture.state.portalArgv, ["http://ping.omacom.io/nm-check.txt"], "portal helper receives fixed HTTP URL as one argv")
      NetworkBoundary.Networking.connectivity = NetworkConnectivity.Full
      t.equal(network.headerCursorKey, "", "vanished selected portal clears its cursor identity")
      t.check(!network.keyboardCursor, "vanished selected portal hides the outline instead of highlighting another action")
      t.check(!network.cursorRowConfirmed("header"), "vanished portal never confirms a replacement header action")
      keys.keyRelease(Qt.Key_Return)
      t.check(!network.keyboardCursor && network.headerCursorKey === "", "releasing the old portal key cannot adopt or activate another action")
      NetworkBoundary.Networking.connectivity = NetworkConnectivity.Limited
      t.equal(network.statsView.ping, "--", "limited link hides latency")
      t.equal(network.statsView.loss, "--", "limited link hides loss")
      NetworkBoundary.Networking.connectivity = NetworkConnectivity.None
      t.equal(network.statsView.loss, "--", "offline link hides loss")
      NetworkBoundary.Networking.connectivity = NetworkConnectivity.Full
      t.check(!network.hasCaptivePortal, "full link removes sign-in")
      t.equal(network.headerKeyRows().filter(function (row) {
        return row.key === "portal"
      }).length, 0, "portal keyboard action disappears with state")
      network.open()
      network.dnsProvider = "DHCP"
      fixture.configure({
        dnsDelay: 0.3,
        dnsExit: 1
      }, function () {
        network.setDns("Cloudflare")
        t.check(network.opened, "DNS selection leaves panel open")
        t.equal(network.selectedDnsProvider, "Cloudflare", "pending DNS is optimistic")
        t.waitFor(function () {
          return network.pendingDnsProvider === ""
        }, 1500, "failed DNS settles", function () {
          t.equal(network.selectedDnsProvider, "DHCP", "failed DNS rolls back")
          t.check(network.opened, "failed DNS keeps panel open")
          network.close()
          t.done()
        })
      })
    })
  })
}
