// Device row in the Filament style: a web node (lit when the device is
// the active one), a glyph in a fixed-width slot so labels line up across
// dropdowns, the label, and a trailing detail. Unavailable devices are
// dimmed and never chosen. The row spans the item's full width.
import QtQuick
import qs.Commons

Item {
  id: row

  // Device glyph (a Nerd Font icon).
  property string glyph: ""
  // Device name.
  property string label: ""
  // Trailing detail, e.g. "unplugged".
  property string detail: ""
  // Whether this is the active device.
  property bool active: false
  // Whether the device can be chosen.
  property bool available: true
  // Whether the keyboard cursor is on this row.
  property bool hasCursor: false

  // Emitted when an available row is clicked or activated.
  signal chosen
  // Emitted when the pointer enters the row.
  signal entered

  // Chooses the device, unless it is unavailable.
  function activate() {
    if (available)
      chosen()
  }

  implicitHeight: Style.space(30)
  opacity: available ? 1 : 0.45

  Rectangle {
    anchors.fill: parent
    color: row.hasCursor ? Util.alpha(DesignTokens.accent, 0.08) : "transparent"
    border.width: row.hasCursor ? 1 : 0
    border.color: DesignTokens.accent
  }
  Rectangle {
    id: marker
    width: Style.space(8)
    height: width
    rotation: 45
    x: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    color: row.active ? DesignTokens.accent : "transparent"
    border.width: 1
    border.color: row.active ? DesignTokens.accent : Util.alpha(DesignTokens.foreground, 0.35)
  }
  Text {
    id: glyphText
    x: marker.x + marker.width + Style.space(10)
    width: Style.space(18)
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignHCenter
    text: row.glyph
    color: DesignTokens.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
  Text {
    anchors.left: glyphText.right
    anchors.leftMargin: Style.space(10)
    anchors.right: detailText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: row.label
    elide: Text.ElideRight
    color: DesignTokens.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
  Text {
    id: detailText
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: row.detail
    color: Util.alpha(DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onContainsMouseChanged: if (containsMouse)
      row.entered()
    onClicked: row.activate()
  }
}
