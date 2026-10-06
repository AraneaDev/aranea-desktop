// The Aranea VPN dropdown's header: the VPN glyph (dim when none is up,
// accent when any is, urgent after a failure), "VPN" and the connection
// caption ("2 of 5 connected" or "Not connected"). No switch: there is no
// single radio to toggle. Pure view: plain inputs in, nothing out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Aranea.DropdownHeader {
  id: header
  refined: true

  // The icon state from VpnLogic.iconState: "idle", "up" or "alert".
  property string iconState: "idle"

  objectName: "vpnHeader"
  title: "VPN"
  glyphColor: header.iconState === "alert" ? Aranea.DesignTokens.urgent : header.iconState === "up" ? Aranea.DesignTokens.accent : Util.alpha(Aranea.DesignTokens.foreground, 0.55)
}
