// Aranea VPN bar widget (araneadev.vpn): the bar entry point for the VPN
// dropdown. This is a skeleton only: the icon stays hidden (zero width)
// until a later task wires real VPN state (NetworkManager profiles and
// own-app VPNs, via VpnLogic.js) into visibility and a dropdown view. The
// IPC target already answers open/close/show/hide/toggle (Panel's own
// IpcHandler), though toggling currently shows nothing.
import QtQuick
import qs.Ui

Panel {
  id: root
  moduleName: "araneadev.vpn"
  ipcTarget: "aranea.vpn"

  // Hidden until a later task shows the icon for an active or available VPN.
  implicitWidth: 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The glyph shared with araneadev.network's VPN rows (VpnLogic.VPN_GLYPH).
    text: String.fromCodePoint(0xf0582)

    onPressed: root.toggle()
  }
}
