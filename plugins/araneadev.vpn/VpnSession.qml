// A connected VPN's session details in the Aranea VPN dropdown, under its
// row: a small muted grid of IP, Server (only when known) and Up, then the
// link's traffic graph (Aranea.LinkGraph) once it has samples. Hidden when
// there is nothing to show. Pure view: plain inputs in, nothing out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: session

  // The session IP, "" when unknown.
  property string ip: ""
  // The server (OpenVPN remote, OpenConnect gateway, WireGuard endpoint),
  // "" when unknown.
  property string server: ""
  // The uptime, already formatted ("1 h 12 min"), "" when unknown.
  property string up: ""
  // Rate samples for the graph, oldest first: [{rx, tx}].
  property var samples: []

  objectName: "vpnSession"
  visible: session.ip !== "" || session.server !== "" || session.up !== "" || session.samples.length > 0
  spacing: Style.space(4)

  // A muted key in the details grid.
  component Key: Text {
    color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
  }
  // A value in the details grid.
  component Value: Text {
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.82)
    font.family: Aranea.Typography.technicalFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  Grid {
    width: session.width
    columns: 2
    columnSpacing: Style.space(10)
    rowSpacing: Style.space(2)

    Key {
      objectName: "ipKey"
      visible: session.ip !== ""
      text: "IP"
    }
    Value {
      objectName: "sessionIp"
      visible: session.ip !== ""
      text: session.ip
    }
    Key {
      objectName: "serverKey"
      visible: session.server !== ""
      text: "Server"
    }
    Value {
      objectName: "sessionServer"
      visible: session.server !== ""
      text: session.server
    }
    Key {
      objectName: "upKey"
      visible: session.up !== ""
      text: "Up"
    }
    Value {
      objectName: "sessionUp"
      visible: session.up !== ""
      text: session.up
    }
  }
  Aranea.LinkGraph {
    width: session.width
    height: Style.space(26)
    visible: session.samples.length > 0
    samples: session.samples
  }
}
