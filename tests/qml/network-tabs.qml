// Network's page tabs use pointer actions without changing VPN state themselves.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.network" as Network

ShellRoot {
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    when: false
  }
  // Track the selected page without invoking connection actions.
  property string picked: ""
  FloatingWindow {
    visible: true
    implicitWidth: 380
    implicitHeight: 70
    Network.NetworkTabs {
      id: tabs
      width: 360
      vpnAvailable: true
      bluetoothAvailable: true
      connectedCount: 2
      onPageRequested: function (page) {
        picked = page
      }
    }
  }
  Component.onCompleted: {
    var bluetooth = t.findChild(tabs, "bluetoothTab")
    t.check(bluetooth !== null, "Network offers a Bluetooth tab")
    var vpn = t.findChild(tabs, "vpnTab")
    t.check(vpn.text.indexOf("2") >= 0, "VPN tab exposes its connected count")
    t.check(t.findChild(tabs, "networkTab").selected && !vpn.selected, "Network is the default page")
    t.step(350, function () {
      pointer.mouseClick(vpn)
      t.equal(picked, "vpn", "VPN tab requests an internal page change")
      tabs.page = "vpn"
      t.check(vpn.selected, "selected VPN page has an active tab")
      pointer.mouseClick(bluetooth)
      t.equal(picked, "bluetooth", "Bluetooth tab requests an internal page change")
      tabs.page = "bluetooth"
      t.check(bluetooth.selected && !vpn.selected, "selected Bluetooth page has an active tab")
      tabs.vpnAvailable = false
      t.check(tabs.visible && !vpn.visible && bluetooth.visible, "Bluetooth remains available without VPN")
      tabs.bluetoothAvailable = false
      t.check(!tabs.visible, "tabs disappear if the optional VPN component is absent")
      t.done()
    })
  }
}
