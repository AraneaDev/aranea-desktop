// The real Network host owns Bluetooth's lifecycle and keyboard surface.
// Native windows are adapted by the runner; controllers and views stay real.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.network" as Network
import "plugins/araneadev.bluetooth" as Bluetooth
import "plugins/araneadev.vpn" as Vpn

ShellRoot {
  // Count Bluetooth power requests forwarded by the Network host.
  property int powerRequests: 0
  TestCase {
    id: keys
    when: false
  }
  FloatingWindow {
    id: keyboardWindow
    visible: true
    implicitWidth: 400
    implicitHeight: 500
  }
  Component {
    id: inertBluetooth
    Bluetooth.Panel {
      embedded: true
      embeddingHost: host
      function toggleBluetooth() {
        powerRequests++
      }
    }
  }
  QmlTest {
    id: t
  }
  QtObject {
    id: sibling
    property bool opened: true
  }
  QtObject {
    id: siblingHost
    property var bluetoothController: sibling
  }
  QtObject {
    id: barFixture
    property color barForeground: "white"
    property color urgent: "red"
    property string fontFamily: "sans-serif"
    property string position: "top"
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property int barSize: 32
    function hideTooltip(owner) {
    }
    function moduleWidgets(name) {
      return name === "omarchy.network" ? [host, siblingHost] : []
    }
  }
  Network.Panel {
    id: host
  }
  Component.onCompleted: t.step(100, function () {
    var bt = host.bluetoothController
    t.check(bt !== undefined && bt !== null, "Network loads the optional Bluetooth controller")
    if (!bt) {
      t.done()
      return
    }
    host.bar = barFixture
    t.equal(bt.openSibling(), sibling, "discovery handoff finds Bluetooth hosted on another monitor")
    host.bar = null
    bt.open()
    t.check(host.opened && host.activePage === "bluetooth" && bt.opened, "legacy Bluetooth open selects the host page")
    t.check(!bt.visible && bt.implicitWidth === 0, "embedded Bluetooth has no independent bar entry")
    t.check(bt.activeDropdown !== null, "embedded controller targets the hosted pure view")
    host.keyCatcher.moveRequested(0, 1)
    t.check(bt.cursorActive && bt.keyboardCursor, "first hosted key reveals the Bluetooth cursor")
    host.passwordSsid = "fixture network"
    host.passwordText = "inert fixture text"
    host.keyCatcher.textKey("N")
    t.check(host.opened && !bt.opened, "leaving Bluetooth closes only its controller")
    t.equal(host.passwordText, "", "page changes clear unsubmitted Wi-Fi credentials")
    host.keyCatcher.textKey("V")
    t.check(host.activePage === "vpn" && host.vpnController.opened, "V selects the shared VPN page")
    host.vpnController.openPrompt("inert fixture profile", "inert fixture user")
    host.vpnController.promptPassword = "inert fixture text"
    host.keyCatcher.textKey("B")
    t.equal(host.vpnController.promptPassword, "", "leaving VPN clears unsubmitted credentials")
    t.check(bt.opened, "returning to Bluetooth reopens its controller")
    // Replace only the hardware action; the real key catcher and page routing stay real.
    bt.parent.sourceComponent = inertBluetooth
    bt = host.bluetoothController
    host.keyCatcher.parent = keyboardWindow.contentItem
    host.keyCatcher.forceActiveFocus()
    keys.keyClick(Qt.Key_B)
    t.equal(powerRequests, 0, "B selects Bluetooth without toggling its radio")
    keys.keyClick(Qt.Key_T)
    t.equal(powerRequests, 1, "T runs the hosted Bluetooth power action")
    t.check(t.findChild(bt.activeDropdown, "keyHint").text.indexOf("t power") >= 0, "hosted footer advertises its usable power key")
    bt.close()
    t.check(!host.opened && !bt.opened, "legacy Bluetooth close closes the shared popup")
    bt.toggle()
    t.check(host.opened && bt.opened, "legacy Bluetooth toggle reopens the shared page")
    host.close()
    t.check(!bt.opened, "closing Network closes the embedded Bluetooth lifecycle")
    bt.embedded = false
    bt.open()
    t.check(bt.opened && !host.opened && bt.activeDropdown !== null, "standalone fallback owns its popup and view")
    t.check(t.findChild(bt.activeDropdown, "keyHint").text.indexOf("b power") >= 0, "standalone footer preserves its original power key")
    bt.close()
    t.check(!bt.opened, "standalone fallback closes independently")
    t.done()
  })
}
