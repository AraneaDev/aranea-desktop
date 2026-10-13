// The existing VPN controller follows its Network host and keeps keyed input.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.vpn" as Vpn
import "plugins/araneadev.vpn/VpnLogic.js" as VpnLogic

ShellRoot {
  QmlTest {
    id: t
  }
  QtObject {
    id: host
    property bool networkOpen: false
    property var keyCatcher: focusTarget
    function openVpnDropdown() {
      networkOpen = true
      vpn.controller.show()
    }
    function close() {
      networkOpen = false
      vpn.controller.hide()
    }
  }
  QtObject {
    id: focusTarget
    property int restores: 0
    function forceActiveFocus() {
      restores++
    }
  }
  QtObject {
    id: view
    property int disarmed: 0
    function disarmPointer() {
      disarmed++
    }
    function ensureVisible(section, index) {
    }
  }
  Vpn.Panel {
    id: vpn
    embedded: true
    embeddingHost: host
    hostedDropdown: view
  }
  Component.onCompleted: {
    vpn.open()
    t.check(host.networkOpen && vpn.opened, "legacy VPN open enters the host's VPN page")
    t.check(!vpn.visible && vpn.implicitWidth === 0, "embedded controller creates no separate bar entry")
    vpn.fixture = VpnLogic.parseFixture('[{"name":"Office","kind":"nm","connected":true},{"name":"Backup","kind":"nm","connected":false}]')
    vpn.activateKeyboard()
    t.check(vpn.keyboardCursor && vpn.cursorKey !== "", "first Enter reveals a keyed VPN row")
    vpn.navigateKeyboard(0, 1)
    t.equal(vpn.cursorFlat, 1, "hosted navigation moves to the next VPN row")
    t.check(view.disarmed >= 2, "hosted keyboard navigation disarms the hosted view")
    vpn.openPrompt("Office", "fixture user")
    vpn.cancelPrompt()
    t.step(20, function () {
      t.equal(focusTarget.restores, 1, "cancel returns keyboard focus to Network's catcher")
      vpn.openPrompt("Office", "fixture user")
      vpn.promptBusy = true
      t.step(20, function () {
        t.equal(focusTarget.restores, 2, "connect start returns keyboard focus to Network's catcher")
        vpn.promptPassword = "inert fixture text"
        vpn.close()
        t.check(!host.networkOpen && !vpn.opened, "closing VPN closes its host")
        t.equal(vpn.promptPassword, "", "closing the host clears unsubmitted credentials")
        t.equal(vpn.fixture, null, "display fixtures clear on host close")
        t.done()
      })
    })
  }
}
