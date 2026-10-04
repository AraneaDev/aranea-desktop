// The Link section of the Aranea Network dropdown: a "LINK" caption with
// "last 60 s", the throughput graph, and stock's stats in a four-column
// grid (label, value, label, value). The IP address and gateway copy on
// click unless they read "--". Pure view: plain inputs in, signals out.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: section

  // The stats, already formatted: {visible, receiving, sending, ping, loss,
  // lossy, downloaded, uploaded, ip, gateway}. lossy colours ping and loss
  // urgent, as stock does when packets are lost.
  property var stats: ({})
  // Rate samples for the graph, oldest first: [{rx, tx}]. Separate from
  // stats so a sample tick never rebuilds the grid.
  property var samples: []
  // Optional PointerMoveGate (qs.Ui); unused (nothing here moves the
  // keyboard cursor) but accepted like every other section.
  property var pointerGate: null

  // Emitted when a copyable value (IP address or gateway) is clicked.
  signal copy(string value)

  // A stat's label, muted.
  component StatLabel: Text {
    objectName: "statLabel"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  // A stat's value, right-aligned; copyable values take a click and say so.
  component StatValue: Text {
    id: value
    // Whether a click copies this value ("--" never does).
    property bool copyable: false
    // Emitted when a copyable value is clicked.
    signal copyRequested(string value)
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    color: Aranea.DesignTokens.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    Aranea.HoverTint {
      z: -1
      active: copyMouse.enabled
    }
    MouseArea {
      id: copyMouse
      anchors.fill: parent
      enabled: value.copyable && value.text !== "" && value.text !== "--"
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: value.copyRequested(value.text)
    }
    PanelToolTip {
      // "ipValue" names its tip "ipTip", for tests.
      objectName: value.objectName.replace("Value", "Tip")
      visible: copyMouse.enabled && copyMouse.containsMouse
      text: "Copy to clipboard"
    }
  }

  // The stat named KEY, or "--" when missing.
  function stat(key) {
    var s = section.stats || {}
    return s[key] !== undefined && s[key] !== "" ? String(s[key]) : "--"
  }

  objectName: "linkSection"
  visible: !!(section.stats && section.stats.visible)
  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: captionText.implicitHeight
    Text {
      id: captionText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "LINK"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      objectName: "linkCount"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "last 60 s"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
  Aranea.LinkGraph {
    width: parent.width
    samples: section.samples
  }
  GridLayout {
    width: parent.width
    columns: 4
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(4)

    StatLabel {
      text: "Receiving"
    }
    StatValue {
      text: section.stat("receiving")
    }
    StatLabel {
      text: "Sending"
    }
    StatValue {
      text: section.stat("sending")
    }
    StatLabel {
      text: "Ping"
    }
    StatValue {
      text: section.stat("ping")
      color: section.stats && section.stats.lossy ? Aranea.DesignTokens.urgent : Aranea.DesignTokens.foreground
    }
    StatLabel {
      text: "Packet loss"
    }
    StatValue {
      text: section.stat("loss")
      color: section.stats && section.stats.lossy ? Aranea.DesignTokens.urgent : Aranea.DesignTokens.foreground
    }
    StatLabel {
      text: "Downloaded"
    }
    StatValue {
      text: section.stat("downloaded")
    }
    StatLabel {
      text: "Uploaded"
    }
    StatValue {
      text: section.stat("uploaded")
    }
    StatLabel {
      text: "IP address"
    }
    StatValue {
      objectName: "ipValue"
      text: section.stat("ip")
      copyable: true
      onCopyRequested: function (value) {
        section.copy(value)
      }
    }
    StatLabel {
      text: "Gateway"
    }
    StatValue {
      objectName: "gatewayValue"
      text: section.stat("gateway")
      copyable: true
      onCopyRequested: function (value) {
        section.copy(value)
      }
    }
  }
}
