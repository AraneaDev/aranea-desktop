// The Aranea Network dropdown's view sections, each driven by plain
// properties in a real window with real pointer clicks: the header shows
// QR, speed and the Wi-Fi switch only when their flags are set, each emits
// its signal, the scan pulse shows only while scanning and cursorIndex
// outlines exactly that (visible) action; the graph puts idle samples on
// the bottom, a peak at the top and draws no points without samples; the
// Link section hides without stats, lists its stats in stock order and
// copies the IP but never a "--"; Interfaces shows only with two or more
// links and never outlines; VPN hides when empty, emits toggle from its
// switch, shows "Couldn't connect" (or the failure's own text, e.g.
// "Couldn't disconnect") in the urgent colour on failure and
// breathes while busy; Band hides with visible false, shows pills only
// when pillsVisible, emits pick and toggleAuto and explains its switch as
// stock does; DNS marks the selected pill, emits pick and explains Custom;
// pills draw no outline without the cursor (pointer hover included) and
// exactly one with it, and pointer hover reaches the sections through the
// PointerMoveGate. A forget button that appears under a still pointer
// ignores a click until it settles.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib"
import "plugins/araneadev.network" as Network
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  QmlTest {
    id: t
  }

  // Signals the sections emitted, as [name, args...], in emission order.
  property var log: []

  // Synthesizes the pointer events (TestCase's mouseClick/mouseMove),
  // never run as a test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  FloatingWindow {
    id: win
    implicitWidth: 400
    implicitHeight: 2400
    visible: true

    PointerMoveGate {
      id: gate
      referenceItem: stack
    }

    Column {
      id: stack
      x: 20
      width: 360
      spacing: 12

      Network.NetworkHeader {
        id: hdrAll
        width: parent.width
        glyph: String.fromCodePoint(0xf05a9)
        title: "Interwebz24Ghz (2.4 GHz)"
        caption: "Wiring bits"
        canQr: true
        canSpeed: true
        canToggle: true
        wifiOn: true
        toggleHint: "Turn Wi-Fi off"
        scanning: true
        pointerGate: gate
        onQr: log.push(["qr"])
        onSpeed: log.push(["speed"])
        onToggleWifi: log.push(["toggleWifi"])
        onHoverAction: function (index) {
          log.push(["hoverAction", index])
        }
      }
      Network.NetworkHeader {
        id: hdrNone
        width: parent.width
        title: "Ethernet"
      }
      Network.NetworkHeader {
        id: hdrPartial
        width: parent.width
        title: "Interwebz5Ghz"
        canSpeed: true
        canToggle: true
      }

      Network.NetworkGraph {
        id: graphIdle
        width: 340
        samples: [
          {
            rx: 0,
            tx: 0
          },
          {
            rx: 0,
            tx: 0
          },
          {
            rx: 0,
            tx: 0
          }
        ]
      }
      Network.NetworkGraph {
        id: graphPeak
        width: 340
        samples: [
          {
            rx: 1000,
            tx: 500
          },
          {
            rx: 4000000,
            tx: 1000
          }
        ]
      }
      Network.NetworkGraph {
        id: graphEmpty
        width: 340
        samples: []
      }

      Network.NetworkLinkSection {
        id: link
        width: parent.width
        stats: ({
            visible: true,
            receiving: "3.4 MB/s",
            sending: "120 KB/s",
            ping: "14 ms",
            loss: "0%",
            lossy: false,
            downloaded: "1.8 GB",
            uploaded: "210 MB",
            ip: "192.168.0.126",
            gateway: "--"
          })
        samples: [
          {
            rx: 1000,
            tx: 10
          }
        ]
        onCopy: function (value) {
          log.push(["copy", value])
        }
      }
      Network.NetworkLinkSection {
        id: linkHidden
        width: parent.width
        stats: ({
            visible: false
          })
      }

      Network.NetworkInterfacesSection {
        id: ifaceOne
        width: parent.width
        rows: [
          {
            key: "wlan0",
            glyph: String.fromCodePoint(0xf05a9),
            label: "wlan0",
            detail: "Wi-Fi · connected",
            active: true
          }
        ]
      }
      Network.NetworkInterfacesSection {
        id: ifaceTwo
        width: parent.width
        rows: [
          {
            key: "wlan0",
            glyph: String.fromCodePoint(0xf05a9),
            label: "wlan0",
            detail: "Wi-Fi · connected",
            active: true
          },
          {
            key: "enp3s0",
            glyph: String.fromCodePoint(0xf0200),
            label: "enp3s0",
            detail: "Ethernet · cable unplugged",
            active: false
          }
        ]
      }

      Network.NetworkVpnSection {
        id: vpnEmpty
        width: parent.width
        rows: []
      }
      Network.NetworkVpnSection {
        id: vpn
        width: parent.width
        pointerGate: gate
        rows: [
          {
            key: "u-1",
            glyph: String.fromCodePoint(0xf0582),
            label: "office-wg",
            detail: "WireGuard · 10.8.0.3",
            active: true
          },
          {
            key: "u-2",
            glyph: String.fromCodePoint(0xf0582),
            label: "home-openvpn",
            detail: "VPN",
            active: false
          }
        ]
        status: ({
            "u-1": {
              busy: true,
              failed: false
            },
            "u-2": {
              busy: false,
              failed: true
            }
          })
        onToggle: function (index) {
          log.push(["toggle", index])
        }
        onRowHovered: function (index) {
          log.push(["vpnHover", index])
        }
      }

      Network.NetworkBandSection {
        id: bandHidden
        width: parent.width
        visible: false
        title: "WI-FI BAND"
      }
      Network.NetworkBandSection {
        id: bandAuto
        width: parent.width
        title: "WI-FI BAND: 2.4GHZ"
        auto: true
        currentLabel: "2.4ghz"
        pillsVisible: false
        options: [
          {
            key: "2.4",
            label: "2.4ghz",
            tooltip: "Stay on 2.4ghz",
            selected: true
          },
          {
            key: "5",
            label: "5ghz",
            tooltip: "Stay on 5ghz",
            selected: false
          }
        ]
      }
      Network.NetworkBandSection {
        id: band
        width: parent.width
        title: "WI-FI BAND"
        auto: false
        currentLabel: "2.4ghz"
        pillsVisible: true
        busy: true
        pointerGate: gate
        options: [
          {
            key: "2.4",
            label: "2.4ghz",
            tooltip: "Stay on 2.4ghz",
            selected: true
          },
          {
            key: "5",
            label: "5ghz",
            tooltip: "Stay on 5ghz",
            selected: false
          }
        ]
        onToggleAuto: log.push(["toggleAuto"])
        onPick: function (key) {
          log.push(["bandPick", key])
        }
        onPillHovered: function (auto, index) {
          log.push(["bandHover", auto, index])
        }
      }

      Network.NetworkDnsSection {
        id: dns
        width: parent.width
        pointerGate: gate
        options: [
          {
            key: "DHCP",
            label: "DHCP",
            selected: true,
            tooltip: "Use DNS from DHCP"
          },
          {
            key: "Cloudflare",
            label: "Cloudflare",
            selected: false,
            tooltip: "Set DNS to Cloudflare"
          },
          {
            key: "Google",
            label: "Google",
            selected: false,
            tooltip: "Set DNS to Google"
          },
          {
            key: "Custom",
            label: "Custom",
            selected: false,
            tooltip: "Set custom DNS servers"
          }
        ]
        onPick: function (key) {
          log.push(["dnsPick", key])
        }
        onPillHovered: function (index) {
          log.push(["dnsHover", index])
        }
      }
    }
  }

  // A forget button created under a still pointer (a Repeater rebuild):
  // a click right after it appears was aimed at another row's.
  FloatingWindow {
    id: freshWindow
    implicitWidth: 200
    implicitHeight: 80
    visible: true

    Item {
      id: freshHost
      anchors.fill: parent

      // How many times a fresh forget button was clicked.
      property int clickedCount: 0

      Loader {
        id: freshLoader
        x: 20
        y: 20
        active: false
        sourceComponent: Aranea.ForgetButton {
          forgettable: true
          hasCursor: true
          pointerGate: freshGate
          onClicked: freshHost.clickedCount += 1
        }
      }
      PointerMoveGate {
        id: freshGate
        referenceItem: freshHost
      }
    }
  }

  // How many cursor outlines in ITEM are drawn (a border or a fill).
  function litOutlines(item) {
    return t.findChildren(item, "cursorOutline").filter(function (o) {
      return o.visible && (o.border.width > 0 || o.color.a > 0)
    }).length
  }

  // The last logged entry, as JSON, or "none".
  function last() {
    return log.length ? JSON.stringify(log[log.length - 1]) : "none"
  }

  // Whether every point in PTS sits at Y (within half a pixel).
  function allAt(pts, y) {
    return pts.length > 0 && pts.every(function (p) {
      return Math.abs(p.y - y) < 0.5
    })
  }

  // A forget button that appears under a still pointer ignores clicks for
  // about 300 ms, unless the gate accepted a real move onto it.
  function freshForget() {
    pointer.mouseMove(freshHost, 30, 28)
    t.step(60, function () {
      pointer.mouseMove(freshHost, 32, 28)
      t.step(60, function () {
        freshLoader.active = true
        t.step(30, function () {
          pointer.mouseClick(freshHost, 32, 28)
          t.equal(freshHost.clickedCount, 0, "a click right after forget appears under a still pointer is ignored")
          t.step(350, function () {
            pointer.mouseClick(freshHost, 32, 28)
            t.equal(freshHost.clickedCount, 1, "once it has settled, a click forgets")
            t.done()
          })
        })
      })
    })
  }

  Component.onCompleted: t.step(300, function () {
    // ---------- Header ----------
    var qrAll = t.findChild(hdrAll, "qrAction")
    var speedAll = t.findChild(hdrAll, "speedAction")
    var switchAll = t.findChild(hdrAll, "wifiSwitch")
    t.check(qrAll !== null && qrAll.visible, "QR shows with canQr")
    t.check(speedAll !== null && speedAll.visible, "speed shows with canSpeed")
    t.check(switchAll !== null && switchAll.visible, "the Wi-Fi switch shows with canToggle")
    t.check(!t.findChild(hdrNone, "qrAction").visible, "QR hides without canQr")
    t.check(!t.findChild(hdrNone, "speedAction").visible, "speed hides without canSpeed")
    t.check(!t.findChild(hdrNone, "wifiSwitch").visible, "the switch hides without canToggle")
    t.equal(t.findChild(hdrAll, "qrTip").text, "Show QR code", "QR explains itself")
    t.equal(t.findChild(hdrAll, "speedTip").text, "Run a speed test", "speed explains itself")
    t.equal(t.findChild(hdrAll, "toggleTip").text, "Turn Wi-Fi off", "the switch's tooltip is toggleHint")
    t.check(switchAll.checked, "the switch follows wifiOn")
    t.check(t.findChild(hdrAll, "scanPulse").visible, "the pulse shows while scanning")
    t.check(!t.findChild(hdrNone, "scanPulse").visible, "the pulse hides without scanning")
    t.equal(t.findChild(hdrAll, "headerCaption").text, "WIRING BITS", "the caption reaches DropdownHeader")

    pointer.mouseClick(qrAll)
    t.equal(last(), JSON.stringify(["qr"]), "clicking QR emits qr")
    pointer.mouseClick(speedAll)
    t.equal(last(), JSON.stringify(["speed"]), "clicking speed emits speed")
    pointer.mouseClick(switchAll)
    t.equal(last(), JSON.stringify(["toggleWifi"]), "clicking the switch emits toggleWifi")

    t.equal(litOutlines(hdrAll), 0, "no header outline at cursorIndex -1")
    hdrAll.cursorIndex = 1
    t.equal(litOutlines(hdrAll), 1, "cursorIndex 1 outlines exactly one action")
    t.equal(litOutlines(speedAll), 1, "cursorIndex 1 outlines speed (QR, speed, switch)")
    hdrAll.cursorIndex = 2
    t.equal(litOutlines(switchAll), 1, "cursorIndex 2 outlines the switch")
    hdrAll.cursorIndex = -1
    hdrPartial.cursorIndex = 1
    t.equal(litOutlines(hdrPartial), 1, "a header without QR outlines one action")
    t.equal(litOutlines(t.findChild(hdrPartial, "wifiSwitch")), 1, "without QR, index 1 is the switch")

    // ---------- Graph ----------
    var h = graphIdle.height
    t.check(h > 0, "the graph has a height")
    t.equal(graphIdle.objectName, "linkGraph", "the graph is named linkGraph")
    t.check(allAt(graphIdle.points.rx, h) && allAt(graphIdle.points.tx, h), "idle samples sit every point at the bottom")
    var peakRx = graphPeak.points.rx
    t.check(peakRx.length === 2 && Math.abs(peakRx[1].y) < 0.5, "a peak reaches the top")
    t.check(Math.abs(peakRx[1].x - graphPeak.width) < 0.5, "the newest point sits on the right edge")
    t.equal(graphEmpty.points.rx.length, 0, "no samples draw no receive points")
    t.equal(graphEmpty.points.tx.length, 0, "no samples draw no send points")

    // ---------- Link ----------
    t.check(link.visible, "Link shows with stats.visible")
    t.check(!linkHidden.visible, "Link hides without stats.visible")
    t.check(t.findChild(link, "linkGraph") !== null, "Link carries the graph")
    t.equal(t.findChildren(link, "statLabel").map(function (l) {
      return l.text
    }), ["Receiving", "Sending", "Ping", "Packet loss", "Downloaded", "Uploaded", "IP address", "Gateway"], "the stats are in stock order")
    t.equal(t.findChild(link, "linkCount").text, "last 60 s", "Link reads last 60 s")
    var ipValue = t.findChild(link, "ipValue")
    t.equal(ipValue.text, "192.168.0.126", "the IP shows")
    t.equal(t.findChild(link, "ipTip").text, "Copy to clipboard", "the IP explains copying")
    pointer.mouseClick(ipValue)
    t.equal(last(), JSON.stringify(["copy", "192.168.0.126"]), "clicking the IP copies it")
    var before = log.length
    pointer.mouseClick(t.findChild(link, "gatewayValue"))
    t.equal(log.length, before, "clicking a \"--\" gateway copies nothing")

    // ---------- Interfaces ----------
    t.check(!ifaceOne.visible, "one interface hides the section")
    t.check(ifaceTwo.visible, "two interfaces show it")
    var ifRows = t.findChildren(ifaceTwo, "interfaceRow")
    t.equal(ifRows.length, 2, "two interface rows")
    t.check(ifRows[0].active && !ifRows[1].active, "active comes from the row")
    t.equal(t.findChild(ifaceTwo, "interfacesCount").text, "2", "the count shows")
    t.equal(litOutlines(ifaceTwo), 0, "interface rows never outline")

    // ---------- VPN ----------
    t.check(!vpnEmpty.visible, "no VPN profiles hide the section")
    t.check(vpn.visible, "VPN profiles show it")
    t.equal(t.findChild(vpn, "vpnCount").text, "1 up", "the count reads N up")
    var vpnRows = t.findChildren(vpn, "vpnRow")
    var vpnSwitches = t.findChildren(vpn, "vpnSwitch")
    t.equal(vpnRows.length, 2, "two VPN rows")
    t.check(vpnSwitches[0].checked && !vpnSwitches[1].checked, "the switch follows active")
    pointer.mouseClick(vpnSwitches[0])
    t.equal(last(), JSON.stringify(["toggle", 0]), "the switch emits toggle(0)")
    pointer.mouseClick(vpnRows[1], 40, vpnRows[1].height / 2)
    t.equal(last(), JSON.stringify(["toggle", 1]), "a row click emits toggle(1)")
    t.equal(vpnRows[1].detail, "Couldn't connect", "a failed profile reads Couldn't connect")
    t.equal(t.findChild(vpnRows[1], "detailText").color, Aranea.DesignTokens.urgent, "the failure is urgent")
    t.equal(vpnRows[0].detail, "WireGuard · 10.8.0.3", "a healthy profile keeps its detail")
    t.check(t.findChild(vpnRows[0], "busyPulse").running, "a busy profile breathes")
    t.check(!t.findChild(vpnRows[1], "busyPulse").running, "an idle profile doesn't")
    var vpnStatusBefore = vpn.status
    vpn.status = {
      "u-1": {
        busy: false,
        failed: true,
        text: "Couldn't disconnect"
      }
    }
    t.equal(vpnRows[0].detail, "Couldn't disconnect", "a failed down reads Couldn't disconnect")
    vpn.status = vpnStatusBefore
    t.equal(litOutlines(vpn), 0, "no VPN outline without the cursor")
    vpn.cursorIndex = 1
    t.equal(litOutlines(vpn), 1, "the cursor outlines one VPN row")
    vpn.cursorIndex = -1

    // ---------- Band ----------
    t.check(!bandHidden.visible, "the band hides with visible false")
    t.check(bandAuto.visible && band.visible, "the band shows otherwise")
    t.check(!t.findChild(bandAuto, "bandPills").visible, "Automatic hides the pills")
    t.check(t.findChild(band, "bandPills").visible, "pillsVisible shows the pills")
    t.equal(t.findChild(band, "bandTitle").text, "WI-FI BAND", "the title shows")
    t.equal(t.findChild(bandAuto, "autoTip").text, "Stay on 2.4ghz", "Automatic offers to stay (stock)")
    t.equal(t.findChild(band, "autoTip").text, "Let Wi-Fi pick the band", "a pin offers Automatic (stock)")
    var bandPills = t.findChildren(band, "pill")
    t.equal(bandPills.length, 2, "two band pills")
    t.check(bandPills[0].busy && !bandPills[1].busy, "busy breathes on the selected band")
    pointer.mouseClick(bandPills[1])
    t.equal(last(), JSON.stringify(["bandPick", "5"]), "a pill emits pick")
    pointer.mouseClick(t.findChild(band, "autoSwitch"))
    t.equal(last(), JSON.stringify(["toggleAuto"]), "the switch emits toggleAuto")
    band.cursorAuto = true
    t.equal(litOutlines(band), 1, "the cursor on Automatic outlines one thing")
    t.equal(litOutlines(t.findChild(band, "autoSwitch")), 1, "it's the switch")
    band.cursorAuto = false
    band.cursorIndex = 1
    t.equal(litOutlines(bandPills[1]), 1, "the cursor outlines its band pill")
    band.cursorIndex = -1

    // ---------- DNS ----------
    var dnsPills = t.findChildren(dns, "pill")
    t.equal(dnsPills.length, 4, "four DNS pills")
    t.check(dnsPills[0].selected && !dnsPills[1].selected, "the selected pill is marked")
    t.check(t.findChild(dnsPills[0], "pillUnderline").visible, "the selected pill is underlined")
    t.check(!t.findChild(dnsPills[1], "pillUnderline").visible, "others aren't")
    t.equal(dnsPills[3].tooltipText, "Set custom DNS servers", "Custom explains itself")
    t.equal(t.findChild(dns, "dnsTitle").text, "DNS PROVIDER", "the caption reads DNS PROVIDER")
    pointer.mouseClick(dnsPills[1])
    t.equal(last(), JSON.stringify(["dnsPick", "Cloudflare"]), "clicking Cloudflare emits pick")

    // ---------- Pills and the cursor ----------
    t.equal(litOutlines(dns), 0, "no pill outline without the cursor")
    dns.cursorIndex = 2
    t.equal(litOutlines(dns), 1, "the cursor outlines exactly one pill")
    t.equal(litOutlines(dnsPills[2]), 1, "it's the cursor's pill")
    dns.cursorIndex = -1

    // ---------- Pointer hover, through the gate ----------
    log = []
    gate.reset()
    pointer.mouseMove(dnsPills[2], 10, 5)
    t.step(60, function () {
      pointer.mouseMove(dnsPills[2], 16, 6)
      t.step(60, function () {
        t.check(log.some(function (e) {
          return e[0] === "dnsHover" && e[1] === 2
        }), "a real move over a pill reports pillHovered(2)")
        t.equal(litOutlines(dns), 0, "pointer hover draws no pill outline")
        log = []
        pointer.mouseMove(qrAll, 4, 4)
        t.step(60, function () {
          pointer.mouseMove(qrAll, 8, 6)
          t.step(60, function () {
            t.check(log.some(function (e) {
              return e[0] === "hoverAction" && e[1] === 0
            }), "a real move over QR reports hoverAction(0)")
            log = []
            var autoSw = t.findChild(band, "autoSwitch")
            pointer.mouseMove(autoSw, 4, 4)
            t.step(60, function () {
              pointer.mouseMove(autoSw, 10, 6)
              t.step(60, function () {
                t.check(log.some(function (e) {
                  return e[0] === "bandHover" && e[1] === true && e[2] === -1
                }), "a real move over Automatic reports pillHovered(true, -1)")
                log = []
                pointer.mouseMove(vpnRows[1], 40, 6)
                t.step(60, function () {
                  pointer.mouseMove(vpnRows[1], 46, 8)
                  t.step(60, function () {
                    t.check(log.some(function (e) {
                      return e[0] === "vpnHover" && e[1] === 1
                    }), "a real move over a VPN row reports rowHovered(1)")
                    freshForget()
                  })
                })
              })
            })
          })
        })
      })
    })
  })
}
